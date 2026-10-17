-- The format module through its interface (require("format")): a buffer's plan from a fixture language and the fake
-- tool backend, the "formatter" need, and the report of format.buffer with a fake conform. Servers are in-process
-- fakes: nvim --clean --headless -l tests/unit/format_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local fake = require("fake_backend")
local server = require("fake_server")
local tools = require("tools")

local tmp = h.tmpdir()
require("tools.state").file = tmp .. "/state/projects.json"

-- Fixture languages, with formatters the catalog knows (stylua's binary is stylua, ruff_format's is ruff)
package.loaded.lang = require("lang")._from({
  one = { filetypes = { "fixone" }, formatters = { "stylua", "ruff_format" } },
  none = { filetypes = { "fixnone" } },
})

-- conform, faked: format.buffer's request to it, answered with what the case sets
local asked, answer = {}, { nil, true }
package.loaded.conform = {
  format = function(opts, cb)
    table.insert(asked, opts)
    cb(answer[1], answer[2])
  end,
}

local format = require("format")

local n = 0
--- A fresh project (a git repo) whose system PATH is an empty dir, the resolver on a fake backend with global
--- tools, and a file of filetype ft in it, current.
---@param global table<string, string>
---@param ft string
---@return integer buf, string root, string system
local function setup(global, ft)
  n = n + 1
  local root = ("%s/%d/project"):format(tmp, n)
  local system = ("%s/%d/system"):format(tmp, n)
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(system, "p")
  vim.env.PATH = system
  tools.setup({ backend = fake({ global = global }) })
  vim.cmd.edit(h.write(root .. "/a.txt", { "x" }))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = ft
  return buf, root, system
end

--- Resolves names in root and waits for the ToolsChanged that follows.
local function resolved(names, root)
  local fired = false
  vim.api.nvim_create_autocmd("User", { pattern = tools.event, once = true, callback = function() fired = true end })
  h.await(function(done) tools.resolve_all(names, root, done) end)
  h.ok(vim.wait(3000, function() return fired end, 5), "no ToolsChanged after resolving")
end

--- Runs format.buffer on buf; what conform was asked and what was reported.
local function run(buf)
  asked = {}
  local notes, notify = {}, vim.notify
  vim.notify = function(msg, level) table.insert(notes, { msg = msg, level = level }) end
  format.buffer(buf, { async = true })
  vim.notify = notify
  return asked, notes
end

h.case("a plan lists the language's formatters in order and runs those whose binary is found", function()
  local buf, root = setup({ stylua = "1.0.0" }, "fixone")
  resolved({ "stylua", "ruff" }, root)
  h.eq(format.plan(buf), { formatters = { "stylua", "ruff_format" }, run = { "stylua" } })
end)

h.case("a plan made while a binary is looked up fills in once it is found", function()
  local buf = setup({ stylua = "1.0.0", ruff = "1.0.0" }, "fixone")
  h.eq(format.plan(buf).run, {}, "the first plan, before any lookup")
  h.ok(
    vim.wait(3000, function() return vim.deep_equal(format.plan(buf).run, { "stylua", "ruff_format" }) end, 5),
    "the plan never ran both: " .. vim.inspect(format.plan(buf))
  )
end)

h.case("a plan follows a binary that appears, once ToolsChanged says so", function()
  local buf, root, system = setup({}, "fixone")
  resolved({ "stylua", "ruff" }, root)
  h.eq(format.plan(buf).run, {}, "nothing found")
  h.bin(system .. "/stylua", "1.0.0")
  local fired = false
  vim.api.nvim_create_autocmd("User", { pattern = tools.event, once = true, callback = function() fired = true end })
  tools.refresh(root)
  h.ok(vim.wait(3000, function() return fired end, 5), "no ToolsChanged after the refresh")
  h.eq(format.plan(buf).run, { "stylua" }, "stylua, found on the system PATH")
end)

h.case("a plan made while a refresh looks a binary up again fills in, also when the binary did not move", function()
  local buf, root = setup({ stylua = "1.0.0" }, "fixone")
  resolved({ "stylua", "ruff" }, root)
  tools.refresh(root)
  vim.bo[buf].filetype = "fixone"
  h.ok(
    vim.wait(3000, function() return vim.deep_equal(format.plan(buf).run, { "stylua" }) end, 5),
    "the plan never ran stylua again: " .. vim.inspect(format.plan(buf))
  )
end)

h.case("a buffer whose filetype names no formatter has an empty plan, and a new filetype a new plan", function()
  local buf = setup({ stylua = "1.0.0" }, "fixnone")
  h.eq(format.plan(buf), { formatters = {}, run = {} })
  vim.bo[buf].filetype = "fixone"
  h.eq(format.plan(buf).formatters, { "stylua", "ruff_format" }, "once the filetype is fixone")
  vim.cmd("noautocmd setlocal filetype=fixnone")
  h.eq(format.plan(buf).formatters, {}, "once the filetype is fixnone again, set with no FileType")
end)

--- Two project dirs: A has ruff in its .venv, B has nothing; their roots resolved, so no lookup is pending.
local function two_projects(n_)
  local a, b = ("%s/proj%d/a"):format(tmp, n_), ("%s/proj%d/b"):format(tmp, n_)
  h.bin(a .. "/.venv/bin/ruff", "1.0.0")
  vim.fn.mkdir(b .. "/.git", "p")
  resolved({ "stylua", "ruff" }, b)
  return a, b
end

h.case("a buffer that isn't a file plans in the new cwd after :cd", function()
  setup({}, "fixnone")
  local a, b = two_projects(1)
  vim.cmd.cd(b)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "fixone"
  h.eq(format.plan(buf).run, {}, "in b")
  vim.cmd.cd(a)
  h.ok(vim.wait(3000, function() return vim.deep_equal(format.plan(buf).run, { "ruff_format" }) end, 5), "in a: " .. vim.inspect(format.plan(buf)))
  vim.cmd.cd(tmp)
end)

h.case("a renamed buffer plans in its new root", function()
  setup({}, "fixnone")
  local a, b = two_projects(2)
  vim.cmd.edit(h.write(b .. "/x.txt", { "x" }))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "fixone"
  h.eq(format.plan(buf).run, {}, "in b")
  vim.cmd.file(a .. "/x.txt")
  h.ok(vim.wait(3000, function() return vim.deep_equal(format.plan(buf).run, { "ruff_format" }) end, 5), "in a: " .. vim.inspect(format.plan(buf)))
end)

h.case("the formatter need: a named formatter, installed or not, or a server that formats", function()
  local named = setup({}, "fixone")
  h.eq(format.has(named), true, "a named formatter that is not installed")
  h.eq(format.has(named, true), true, "a named formatter, for a range")

  local buf = setup({}, "fixnone")
  h.eq(format.has(buf), false, "no formatter, no server")
  local srv = server.start({ buf = buf, methods = { "textDocument/formatting" } })
  h.eq(format.has(buf), true, "a server that formats attached")
  h.eq(format.has(buf, true), false, "for a range, by a server that formats only whole buffers")
  srv.register({ "textDocument/rangeFormatting" })
  h.eq(format.has(buf, true), true, "for a range, once the server registers range formatting")
  srv.stop()
  h.eq(format.has(buf), false, "the server stopped")
end)

h.case("format.buffer names the formatters that run, and falls back to a server where none is found", function()
  -- nothing looked up yet: format.buffer waits for the lookups
  local buf = setup({ stylua = "1.0.0" }, "fixone")
  local requests, notes = run(buf)
  h.eq(#requests, 1, "conform asked once")
  h.eq(notes, { { msg = "Formatted a.txt with: stylua", level = vim.log.levels.INFO } })
  local srv = server.start({ buf = buf, methods = { "textDocument/formatting" } })
  _, notes = run(buf)
  h.eq(notes, { { msg = "Formatted a.txt with: stylua", level = vim.log.levels.INFO } }, "with a server that formats too")
  srv.stop()

  buf = setup({}, "fixone")
  resolved({ "stylua", "ruff" }, tools.root(buf))
  srv = server.start({ buf = buf, methods = { "textDocument/formatting" } })
  requests, notes = run(buf)
  h.eq(#requests, 1, "conform asked once, to fall back to the server")
  h.eq(notes, { { msg = "Formatted a.txt with: LSP", level = vim.log.levels.INFO } })
  srv.stop()

  requests, notes = run(buf)
  h.eq(#requests, 0, "conform not asked with nothing to format")
  h.eq(notes, { { msg = "No formatter or LSP available for filetype (fixone)", level = vim.log.levels.WARN } })
end)

h.case("format.buffer reports a failure with its own message, a server's error table as text", function()
  local buf, root = setup({ stylua = "1.0.0" }, "fixone")
  resolved({ "stylua", "ruff" }, root)
  answer = { { code = -32603, message = "server said no" }, nil }
  local _, notes = run(buf)
  answer = { nil, true }
  h.eq(#notes, 1, "one report")
  h.eq(notes[1].level, vim.log.levels.ERROR, "an error")
  h.ok(notes[1].msg:find("server said no", 1, true) and not notes[1].msg:find("table: 0x", 1, true), notes[1].msg)
end)

h.finish()
