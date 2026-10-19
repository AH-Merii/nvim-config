-- The parsers a buffer needs and their installs, through the parsers module's interface, on a fake parser backend
-- for nvim-treesitter and the fake tool backend for tree-sitter. Rules: D117 to D120 in
-- docs/rearchitecture-decisions.md.
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local fake = require("fake_parsers")
local fake_tools = require("fake_backend")
local tools = require("tools")
local parsers = require("parsers")

local tmp = h.tmpdir()
require("tools.state").file = tmp .. "/state/projects.json"
require("tools.ux").file = tmp .. "/state/offered.json"

local list_uis = vim.api.nvim_list_uis
local function ui(on) vim.api.nvim_list_uis = on and function() return { {} } end or list_uis end

-- The languages the cases share: python injects regex and comment, and regex injects printf in turn (a second
-- level); markdown injects markdown_inline and regex; Neovim loads lua, vim and vimdoc before any install, and
-- nvim-treesitter has them too.
local world = {
  available = { "python", "regex", "comment", "printf", "markdown", "markdown_inline", "toml", "luadoc", "lua", "vim", "vimdoc" },
  loadable = { "lua", "vim", "vimdoc" },
  injections = {
    python = [[
((string_content) @injection.content (#set! injection.language "regex"))
((comment) @injection.content (#set! injection.language "comment"))]],
    regex = [[((pattern) @injection.content (#set! injection.language "printf"))]],
    markdown = [[
((inline) @injection.content (#set! injection.language "markdown_inline"))
((code) @injection.content (#set! injection.language "regex"))]],
    lua = [[
((string) @injection.content (#set! injection.language "vim"))
((comment) @injection.content (#set! injection.language "luadoc"))]],
  },
}

local n = 0
--- A fresh project dir, tree-sitter found unless opts.cli is false, a UI, installs on, and parsers on a fake backend.
---@param opts? { cli?: boolean, fail?: table<string, true>, backend?: table }
---@return table backend, string root
local function setup(opts)
  opts = opts or {}
  n = n + 1
  local root = ("%s/%d"):format(tmp, n)
  vim.fn.mkdir(root .. "/.git", "p")
  vim.env.PATH = root .. "/system"
  local global = { pyrefly = "1.0.0", ruff = "1.0.0", tombi = "1.0.0" }
  if opts.cli ~= false then
    global["tree-sitter"] = "0.27.1"
  end
  tools.setup({ backend = fake_tools({ global = global, latest = "0.27.1" }) })
  local backend = opts.backend or fake(vim.tbl_extend("force", world, { fail = opts.fail }))
  parsers.setup({ backend = backend })
  ui(true)
  vim.g.install_tools = nil
  return backend, root
end

--- A file buffer in root with filetype ft.
local function open(root, ft, name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, ("%s/%s"):format(root, name or ("file%d.%s"):format(buf, ft)))
  vim.bo[buf].filetype = ft
  return buf
end

--- ensure() on buf; returns the languages its callback got so far (it runs again as installs land).
local function ensure(buf)
  local got = {}
  parsers.ensure(buf, function(lang) table.insert(got, lang) end)
  return got
end

local function settle(cond, what) h.ok(vim.wait(3000, cond, 5), "timed out: " .. what) end
--- Lets scheduled work run, for cases that check nothing happened.
local function idle() vim.wait(50, function() return false end, 5) end

h.case("a language needs its own parser and the languages its injections name, not theirs in turn", function()
  setup()
  h.eq(parsers.needed("python"), { "python", "comment", "regex" })
  h.eq(parsers.needed("regex"), { "regex", "printf" })
  h.eq(parsers.needed("conf"), {}, "a filetype without a parser")
end)

h.case("a language's injections include those of the languages its query inherits, through each inherits line", function()
  setup({
    backend = fake({
      available = { "tsx", "typescript", "regex", "styled", "jsx" },
      injections = {
        tsx = "; inherits: typescript,(jsx)\n",
        typescript = "; inherits: ecma\n",
        ecma = [[((regex) @injection.content (#set! injection.language "regex"))]],
        jsx = [[((tag) @injection.content (#set! injection.language "styled"))]],
      },
    }),
  })
  h.eq(parsers.needed("tsx"), { "tsx", "regex", "styled" })
end)

h.case("names that aren't parsers, commented out, or read from the text are left out", function()
  setup({
    backend = fake({
      available = { "python", "comment", "commented", "bash", "sql" },
      injections = {
        python = [[
; ((x) @injection.content (#set! injection.language "commented"))
((comment) @injection.content (#set! injection.language "comment")) ; (#set! injection.language "commented")
((string) @injection.language (#lua-match? @injection.language "^[a-zA-Z][a-zA-Z0-9]*$"))
((call) @injection.language (#gsub! @injection.language "(.+)/(.+)" "%2"))
((call) @injection.language (#any-of? @injection.language "sql"))
((x) @injection.content (#set! injection.language "notaparser"))
((heredoc) @injection.content (#set! injection.language bash))]],
      },
    }),
  })
  h.eq(parsers.needed("python"), { "python", "bash", "comment" })
end)

h.case("nothing installs until a buffer opens; then its language's missing parsers install together, once", function()
  local backend, root = setup()
  vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
  vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
  idle()
  h.eq(backend.calls, {}, "installs before a buffer")
  local got = ensure(open(root, "python"))
  settle(function() return #got > 0 end, "python's parser")
  h.eq(backend.calls, { { "python", "comment", "regex" } }, "installs")
  h.eq(got, { "python" }, "the buffer's own parser, once it landed")
end)

h.case("a language Neovim bundles still gets nvim-treesitter's copy and its injections, using Neovim's until it lands", function()
  local backend, root = setup()
  local got = ensure(open(root, "lua"))
  h.eq(got, { "lua" }, "lua before any install: Neovim's")
  local help = ensure(open(root, "help"))
  h.eq(help, { "vimdoc" }, "a help buffer before any install")
  settle(function() return #got == 2 and #help == 2 end, "both installs to land")
  h.eq(backend.calls, { { "lua", "luadoc", "vim" }, { "vimdoc" } }, "installs")
  h.eq({ got, help }, { { "lua", "lua" }, { "vimdoc", "vimdoc" } }, "the buffers' parsers once nvim-treesitter's landed")
end)

h.case("a second language installs only what it lacks", function()
  local backend, root = setup()
  local py = ensure(open(root, "python"))
  settle(function() return #py > 0 end, "python")
  local md = ensure(open(root, "markdown"))
  settle(function() return #md > 0 end, "markdown")
  h.eq(backend.calls, { { "python", "comment", "regex" }, { "markdown", "markdown_inline" } })
end)

h.case("a buffer opened while its parsers install waits for that install, and both get their parser when it lands", function()
  local backend, root = setup()
  backend.hold = true
  local first, second = ensure(open(root, "python")), nil
  settle(function() return #backend.calls == 1 end, "the install to start")
  second = ensure(open(root, "python"))
  idle()
  h.eq(#backend.calls, 1, "installs")
  h.eq({ first, second }, { {}, {} }, "before it lands")
  backend.land()
  settle(function() return #first > 0 and #second > 0 end, "both buffers")
  h.eq({ first, second }, { { "python" }, { "python" } })
end)

h.case("a failed install isn't retried for later buffers; retry installs it again", function()
  local backend, root = setup({ fail = { toml = true } })
  local bufs = {}
  for i = 1, 3 do
    bufs[i] = open(root, "toml")
    ensure(bufs[i])
    idle()
  end
  h.eq(backend.calls, { { "toml" } }, "installs for three buffers")
  h.eq(parsers.get("toml").state, "failed", "state")
  h.eq(parsers.missing(bufs[1]), { "toml" }, "the buffer's missing parsers")
  parsers.retry({ "toml" })
  settle(function() return #backend.calls == 2 end, "the retry")
end)

h.case("installs are off with vim.g.install_tools = 'off', and without a UI until one attaches", function()
  local backend, root = setup()
  vim.g.install_tools = "off"
  ensure(open(root, "python"))
  idle()
  h.eq(backend.calls, {}, "installs with install_tools off")
  h.eq(parsers.get("python").state, "missing", "state with install_tools off")

  backend, root = setup()
  ui(false)
  local got = ensure(open(root, "python"))
  idle()
  h.eq(backend.calls, {}, "installs without a UI")
  ui(true)
  vim.api.nvim_exec_autocmds("UIEnter", { modeline = false })
  settle(function() return #got > 0 end, "the install once a UI attached")
  h.eq(backend.calls, { { "python", "comment", "regex" } }, "installs once a UI attached")
end)

h.case("without tree-sitter nothing installs and the parser says why; installing tree-sitter installs them", function()
  local backend, root = setup({ cli = false })
  local got = ensure(open(root, "python"))
  settle(function() return parsers.get("python").state == "failed" end, "python to fail")
  h.ok((parsers.get("python").reason or ""):find("tree-sitter", 1, true), "reason: " .. tostring(parsers.get("python").reason))
  h.eq(backend.calls, {}, "installs")
  h.await(function(done) tools.install({ "tree-sitter" }, root, done) end)
  settle(function() return #got > 0 end, "python once tree-sitter is installed")
  h.eq(backend.calls, { { "python", "comment", "regex" } }, "installs")
end)

h.case("a language's installs show one toast as they start and one as they end; a failure shows an error", function()
  local notify, toasts = vim.notify, {}
  vim.notify = function(msg, level) table.insert(toasts, { msg, level }) end
  local ok, err = pcall(function()
    local _, root = setup({ fail = { toml = true } })
    local got = ensure(open(root, "python"))
    settle(function() return #got > 0 and #toasts >= 2 end, "python's toasts")
    ensure(open(root, "toml"))
    settle(function() return #toasts >= 4 end, "toml's toasts")
  end)
  vim.notify = notify
  assert(ok, err)
  h.eq(vim.list_slice(toasts, 1, 3), {
    { "Installing python, comment, regex", vim.log.levels.INFO },
    { "Installed python, comment, regex", vim.log.levels.INFO },
    { "Installing toml", vim.log.levels.INFO },
  })
  h.eq(toasts[4][2], vim.log.levels.ERROR, "the failure's level")
  h.ok(toasts[4][1]:find("Couldn't install toml", 1, true), "the failure: " .. toasts[4][1])
end)

h.case("the statusline's missing count includes the buffer's failed parsers", function()
  local _, root = setup({ fail = { regex = true } })
  local buf = open(root, "python", "app.py")
  vim.api.nvim_set_current_buf(buf)
  local ux = require("tools.ux")
  settle(function() return ux.status(buf) == "" end, "python's tools to resolve")
  ensure(buf)
  settle(function() return parsers.get("regex").state == "failed" end, "regex to fail")
  settle(function() return ux.status(buf) == "1" end, "a count of 1, got " .. ux.status(buf))
end)

h.case(":Tools lists the buffer's parsers, and tree-sitter while they can't be built", function()
  local _, root = setup({ cli = false })
  local buf = open(root, "python", "app.py")
  vim.api.nvim_set_current_buf(buf)
  ensure(buf)
  settle(function() return parsers.get("python").state == "failed" end, "python to fail")
  local select, rows = vim.ui.select, nil
  vim.ui.select = function(items) rows = vim.tbl_map(function(item) return item.text end, items) end
  local ok, err = pcall(function()
    require("tools.ux").open(buf)
    settle(function() return rows ~= nil end, ":Tools")
  end)
  vim.ui.select = select
  assert(ok, err)
  local function row(name)
    return vim.iter(rows):find(function(text) return text:match("^%S+ " .. vim.pesc(name) .. " ") end)
  end
  h.ok(row("tree-sitter") and row("tree-sitter"):find("^✗"), "tree-sitter row in " .. vim.inspect(rows))
  for _, lang in ipairs({ "python", "comment", "regex" }) do
    h.ok(row(lang) and row(lang):find("^✗") and row(lang):find("parser", 1, true), lang .. " row in " .. vim.inspect(rows))
  end
end)

h.finish()
