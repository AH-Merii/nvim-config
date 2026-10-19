-- The parser backend (parsers.Backend) on nvim-treesitter: what it can install, what it installed, the injections
-- queries in its checkout, and its install and update. Without the plugin there is nothing to install.

local M = {}

---@return table<string, table>
local function table_of()
  local ok, parsers = pcall(require, "nvim-treesitter.parsers")
  return ok and parsers or {}
end

---@param kind "parser"|"queries"
---@return string?
local function install_dir(kind)
  local ok, config = pcall(require, "nvim-treesitter.config")
  return ok and vim.fs.normalize(config.get_install_dir(kind)) or nil
end

local checkout ---@type string|false|nil
--- nvim-treesitter's checkout, whose runtime/queries holds the queries of parsers not installed yet.
---@return string|false
local function root()
  if checkout == nil then
    local file = vim.api.nvim_get_runtime_file("lua/nvim-treesitter/parsers.lua", false)[1]
    checkout = file and vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(file))) or false
  end
  return checkout
end

--- A parser with install info that nvim-treesitter supports (tier 4 is unsupported); query-only entries such as ecma
--- come with the parsers that require them.
function M.available(lang)
  local entry = table_of()[lang]
  return entry ~= nil and entry.install_info ~= nil and entry.tier ~= 4
end

function M.installed(lang)
  local dir = install_dir("parser")
  return dir ~= nil and vim.uv.fs_stat(("%s/%s.so"):format(dir, lang)) ~= nil
end

--- Whether Neovim loads lang now: nvim-treesitter's copy once installed, before that its own (lib/nvim/parser).
---@param lang string
function M.loadable(lang)
  local ok, added = pcall(vim.treesitter.language.add, lang)
  return ok and added == true
end

--- nvim-treesitter's injections query for lang, from its checkout: the same before and after the install, whichever
--- copy of the parser and queries is in use.
function M.injections(lang)
  local src = root() and ("%s/runtime/queries/%s/injections.scm"):format(root(), lang)
  if not (src and vim.uv.fs_stat(src)) then
    return nil
  end
  return table.concat(vim.fn.readfile(src), "\n")
end

--- nvim-treesitter runs `tree-sitter` by name: the one the tool resolver found goes first on PATH.
---@param cli string
local function put_on_path(cli)
  local found = vim.fn.exepath("tree-sitter")
  if found ~= "" and vim.uv.fs_realpath(found) == vim.uv.fs_realpath(cli) then
    return
  end
  vim.env.PATH = vim.fs.dirname(cli) .. ":" .. (vim.env.PATH or "")
end

---@param run fun(ts: table): table the task
---@param langs string[]
---@param cb fun(failed: string[])
local function after(run, langs, cb)
  local ok, ts = pcall(require, "nvim-treesitter")
  if not ok then
    return vim.schedule(function() cb(langs) end)
  end
  -- Neovim's own copy loads either way, so for those only nvim-treesitter's install dir tells
  local before = {}
  for _, lang in ipairs(langs) do
    before[lang] = M.loadable(lang)
  end
  run(ts):await(function()
    vim.schedule(function()
      cb(vim.tbl_filter(function(lang) return not M.installed(lang) and (before[lang] or not M.loadable(lang)) end, langs))
    end)
  end)
end

function M.install(langs, opts, cb)
  put_on_path(opts.cli)
  -- looked up at each call, so a check can stand in for it (tests/regress/checks/ts_install_once.lua)
  after(function(ts) return ts.install(langs) end, langs, cb)
end

function M.update(langs, cb)
  after(function(ts) return ts.update(langs, { summary = true }) end, langs, cb)
end

return M
