-- linting/'s adapter for nvim-lint: nvim-lint runs each linter with the binary the resolver finds for the buffer's
-- project, its cwd and env, and leaves the user's :tcd and :lcd as they were. Nothing outside linting/ runs nvim-lint.

local tools = require("tools")

local M = {}

local severities = { error = vim.diagnostic.severity.ERROR, warn = vim.diagnostic.severity.WARN, info = vim.diagnostic.severity.INFO }

-- How the config runs a linter, merged over nvim-lint's own definition of it; a linter nvim-lint lacks gets its whole
-- definition here, with `cmd` its bare binary name (the resolved path replaces it). Kept by tool, not by language:
-- nvim-lint keys linters by name for every filetype, as the catalog keys their binaries
local definitions = {
  -- jdx's maintained fork of actionlint, with GNU-style options and actionlint's JSON plus a rule id and a severity.
  -- Its default profile adds security rules that zizmor already reports (template-injection, unpinned-uses, ...); the
  -- correctness profile is what actionlint checks
  jactionlint = {
    cmd = "jactionlint",
    stdin = true,
    args = { "--format", "{{json .}}", "--profile", "correctness", "--stdin-filename", function() return vim.api.nvim_buf_get_name(0) end, "-" },
    ignore_exitcode = true, -- exits 1 when it has findings
    parser = function(output)
      local diagnostics = {}
      for _, item in ipairs(output ~= "" and vim.json.decode(output) or {}) do
        table.insert(diagnostics, {
          lnum = item.line - 1,
          end_lnum = (item.end_line or item.line) - 1,
          col = item.column - 1,
          end_col = item.end_column,
          severity = severities[item.severity] or vim.diagnostic.severity.WARN,
          source = "jactionlint",
          code = item.id,
          message = item.message,
        })
      end
      return diagnostics
    end,
  },
}

-- Linters whose parser matches file names relative to Neovim's cwd, so they keep running there
local keep_cwd = { tflint = true }

function M.setup()
  local lint = require("lint")
  -- Every filetype a language declares, variants included, each with its whole list (lua/lang/). Runs name their
  -- linters from lang.of, so nvim-lint's union of a dotted filetype's parts decides nothing
  lint.linters_by_ft = vim.deepcopy(require("lang").views().lint)
  for name, def in pairs(definitions) do
    local builtin = lint.linters[name]
    if type(builtin) == "function" then
      lint.linters[name] = function() return vim.tbl_extend("force", builtin(), def) end
    else
      lint.linters[name] = vim.tbl_extend("force", builtin or {}, def)
    end
  end
end

--- nvim-lint's diagnostic namespace for linter name.
---@param name string
---@return integer
function M.namespace(name) return require("lint").get_namespace(name) end

--- The binary the resolver looks up for a linter: its catalog binary, else its command when that is a bare name.
---@param name string
---@param linter? lint.Linter|fun(): lint.Linter its definition, default nvim-lint's
---@return string?
function M.binary(name, linter)
  local bin = tools.catalog.binary("linter", name)
  if bin then
    return bin
  end
  if not linter then
    local ok, lint = pcall(require, "lint")
    linter = ok and lint.linters[name] or nil
  end
  if type(linter) == "function" then
    linter = linter()
  end
  local cmd = type(linter) == "table" and linter.cmd
  return type(cmd) == "string" and not cmd:find("/") and cmd or nil
end

-- golangcilint builds its version-specific args once, when its module loads, from the golangci-lint and go on Neovim's
-- PATH (lint/linters/golangcilint.lua); build them again with the resolved binary and its runtime first
local args_by_path = {} ---@type table<string, table|false>
---@param result tools.Result
local function golangcilint_args(result)
  if args_by_path[result.path] == nil then
    local file = vim.api.nvim_get_runtime_file("lua/lint/linters/golangcilint.lua", false)[1]
    local path = vim.env.PATH
    vim.env.PATH = vim.fs.dirname(result.path) .. ":" .. (result.env and result.env.PATH or path)
    local ok, linter = pcall(dofile, file)
    vim.env.PATH = path
    args_by_path[result.path] = ok and type(linter) == "table" and linter.args or false
  end
  return args_by_path[result.path] or nil
end

--- The global, tab and window dirs (false where the tab or window has none of its own).
local function dirs()
  return {
    vim.fn.getcwd(-1, -1),
    vim.fn.haslocaldir(-1, 0) == 1 and vim.fn.getcwd(-1, 0),
    vim.fn.haslocaldir(0, 0) == 1 and vim.fn.getcwd(0, 0),
  }
end

--- Runs fn and puts back the dirs it moved. nvim-lint evaluates cmd and args after a global :cd to the linter's cwd and
--- back to the window's (lint.lua, with_cwd), which drops the user's :tcd and :lcd.
---@param fn fun()
local function keeping_dirs(fn)
  local before = dirs()
  local ok, err = pcall(fn)
  if not vim.deep_equal(dirs(), before) then
    local mods = { noautocmd = true, silent = true }
    vim.cmd.cd({ before[1], mods = mods })
    if before[2] then
      vim.cmd.tcd({ before[2], mods = mods })
    end
    if before[3] then
      vim.cmd.lcd({ before[3], mods = mods })
    end
  end
  if not ok then
    error(err, 0)
  end
end

---@class linting.Run
---@field root string the buffer's tool root
---@field runs fun(name: string): boolean whether the linter runs on the buffer now
---@field covered fun(name: string, buf: integer): boolean whether a server reporting the same findings is attached

--- Lints the current buffer with names, as run says: only the linters that run, each with its resolved binary.
---@param names string[]
---@param run linting.Run
function M.lint(names, run)
  local opts = {
    filter = function(linter) return run.runs(linter.name) end,
    wrap_linter = function(linter)
      local bin = M.binary(linter.name, linter)
      local result = bin and tools.get(bin, run.root)
      if result then
        linter.cmd = result.path
        if not keep_cwd[linter.name] then
          linter.cwd = run.root
        end
        -- nvim-lint replaces the whole environment when env is set
        linter.env = result.env and vim.tbl_extend("force", vim.fn.environ(), result.env, linter.env or {}) or linter.env
        if linter.name == "golangcilint" and result.path then
          linter.args = golangcilint_args(result) or linter.args
        end
      end
      local parse = linter.parser
      if type(parse) == "function" then
        -- A run that ends after its server attached reports nothing
        linter.parser = function(output, bufnr, ...) return run.covered(linter.name, bufnr) and {} or parse(output, bufnr, ...) end
      end
      return linter
    end,
  }
  keeping_dirs(function() require("lint").try_lint(names, opts) end)
end

-- Loads nvim-lint for linting/, and adds the <leader>ll and <leader>li rows
M.plugins = {
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local linting = require("linting")
      linting.setup()

      -- <leader>li where the filetype's language names a linter; <leader>ll where linting.buffer() would run one, a
      -- linter no attached server covers
      local keys = require("keys")
      keys.need("linter", function(buf) return linting.has(buf) end)
      keys.need("uncovered linter", function(buf)
        if not linting.has(buf) then
          return false
        end
        local plan = linting.plan(buf)
        return vim.iter(plan.linters):any(function(name) return not plan.covered[name] end)
      end)
      keys.feature("lint")({
        {
          "<leader>ll",
          function()
            linting.buffer(vim.api.nvim_get_current_buf())
            vim.notify("Linting...", vim.log.levels.INFO, { title = "nvim-lint" })
          end,
          "Trigger linting for current file",
          need = "uncovered linter",
        },
        {
          "<leader>li",
          function()
            local now = linting.plan(vim.api.nvim_get_current_buf())
            local linters = vim.tbl_map(
              function(name) return now.covered[name] and ("%s (reported by the %s server)"):format(name, now.covered[name]) or name end,
              now.linters
            )
            if #linters == 0 then
              print("No linters configured for filetype: " .. vim.bo.filetype)
            else
              print("Linters for " .. vim.bo.filetype .. ": " .. table.concat(linters, ", "))
            end
          end,
          "Show available linters for current filetype",
          need = "linter",
        },
      })
    end,
  },
}

return M
