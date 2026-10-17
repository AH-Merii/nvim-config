-- A buffer's facts (lua/ui/facts.lua) on a fixture language, the fake tool backend and in-process servers:
-- nvim --clean --headless -l tests/unit/facts_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local fake = require("fake_backend")
local fake_server = require("fake_server")
local tools = require("tools")
local lang = require("lang")
local facts = require("ui.facts")

local tmp = h.tmpdir()
require("tools.state").file = tmp .. "/state/projects.json"

-- A language with catalog tools: stylua and shfmt format, ruff lints unless the fakesrv server runs, yamllint lints.
-- A second one only lints, with yamllint.
-- facts, format and linting read the registry from package.loaded.lang
local registry = lang._from({
  factlang = {
    filetypes = { "factsft" },
    servers = { fakesrv = {} },
    formatters = { "stylua", "shfmt" },
    linters = { ruff = { covered_by = "fakesrv" }, yamllint = {} },
  },
  otherlang = { filetypes = { "factsother" }, linters = { yamllint = {} } },
})
package.loaded.lang = registry

--- Runs what handlers scheduled; two rounds cover a schedule made from a scheduled callback.
local function settle()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    vim.wait(1000, function() return ran end, 5)
  end
end

-- Every FactsChanged, by buffer
local changes = {} ---@type integer[]
vim.api.nvim_create_autocmd("User", { pattern = facts.event, callback = function(ev) table.insert(changes, ev.data.buf) end })

local n = 0
--- A file of the fixture language in a fresh dir, its tools on a fake backend (stylua, ruff and yamllint installed,
--- shfmt not), resolved unless opts.resolve is false; facts and the event log start empty. opts.pins: what the dir's
--- mise config pins. The returned projects table is the fake's: a test changes a project's pins through it.
---@param opts? { resolve?: boolean, pins?: table<string, string> }
---@return integer buf, string root, table backend, table projects
local function open(opts)
  opts = opts or {}
  n = n + 1
  local dir = ("%s/%d"):format(tmp, n)
  vim.fn.mkdir(dir, "p")
  vim.env.PATH = dir -- an empty system PATH: only the fake's tools are found
  local projects = { [dir] = opts.pins }
  local backend = fake({ global = { stylua = "2.0.0", ruff = "0.17.0", yamllint = "1.35.0" }, projects = projects })
  tools.setup({ backend = backend })
  facts.setup()
  vim.cmd.edit(dir .. "/a.facts")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "factsft"
  local root = tools.root(buf)
  if opts.resolve ~= false then
    h.await(function(done) tools.resolve_all({ "stylua", "shfmt", "ruff", "yamllint" }, root, done) end)
    tools.project(root)
    h.await(function(done) tools.project(root, done) end)
  end
  settle()
  changes = {}
  return buf, root, backend, projects
end

---@param buf integer
local function brief(buf)
  local f = facts.get(buf)
  return { servers = f.servers, formatters = f.formatters, linters = f.linters, missing = f.missing, unanswered = f.unanswered }
end
local resolved = { servers = {}, formatters = { "stylua" }, linters = { "ruff", "yamllint" }, missing = { "shfmt" }, unanswered = false }

h.case("what will run and what is missing: found tools run, a missing one is listed and does not run", function()
  local buf = open()
  h.eq(brief(buf), resolved)
end)

h.case("a new filetype gets its own language's tools, with one FactsChanged", function()
  local buf = open()
  facts.get(buf)
  vim.bo[buf].filetype = "factsother"
  settle()
  h.eq({ brief(buf), changes }, { { servers = {}, formatters = {}, linters = { "yamllint" }, missing = {}, unanswered = false }, { buf } })
end)

h.case("the project prompt: a pinning config waits for an answer until it is answered, with one FactsChanged each way", function()
  -- An answer that changes no tool's result: stylua is 2.0.0 in the project and globally
  local buf, root = open({ pins = { stylua = "2.0.0" } })
  h.eq(facts.get(buf).unanswered, true, "before the answer")
  h.await(function(done) tools.set_choice(root, "global", done) end)
  h.await(function(done) tools.resolve("stylua", root, done) end)
  settle()
  h.eq({ facts.get(buf).unanswered, changes }, { false, { buf } }, "after it")
  -- A config written later that pins a tool this buffer doesn't run; tools refreshes on the write
  local other, other_root, _, projects = open()
  h.eq(facts.get(other).unanswered, false, "with no config")
  projects[other_root] = { yamllint = "1.35.0" }
  tools.refresh()
  h.await(function(done) tools.project(other_root, done) end)
  settle()
  h.eq({ facts.get(other).unanswered, changes }, { true, { other } }, "once a config pins a tool")
end)

h.case("a buffer that isn't a file takes the cwd as its root, and follows a :cd", function()
  open()
  local cwd, elsewhere = vim.fn.getcwd(), tmp .. "/elsewhere"
  vim.fn.mkdir(elsewhere, "p")
  vim.cmd.enew()
  h.eq(facts.get(0).root, vim.fs.normalize(cwd), "before")
  h.await(function(done) tools.project(facts.get(0).root, done) end)
  settle()
  vim.cmd.cd(elsewhere)
  settle()
  local root = facts.get(0).root
  vim.cmd.cd(cwd)
  h.eq(root, elsewhere, "after :cd")
end)

h.case("a server appears on attach and goes on detach; its covered linter does not run while it is attached", function()
  local buf = open()
  local srv = fake_server.start({ buf = buf, name = "fakesrv" })
  settle()
  h.eq(facts.get(buf).servers, { "fakesrv" }, "attached")
  h.eq(facts.get(buf).linters, { "yamllint" }, "linters while fakesrv runs")
  srv.stop()
  settle()
  h.eq(facts.get(buf).servers, {}, "stopped")
  h.eq(facts.get(buf).linters, { "ruff", "yamllint" }, "linters once fakesrv is gone")
end)

h.case("a server with two clients on the buffer is listed once", function()
  local buf = open()
  local a, b = fake_server.start({ buf = buf, name = "fakesrv" }), fake_server.start({ buf = buf, name = "fakesrv" })
  settle()
  h.eq(facts.get(buf).servers, { "fakesrv" })
  a.stop()
  b.stop()
end)

h.case("a stopping server is not running", function()
  local buf = open()
  local srv = fake_server.start({ buf = buf, name = "fakesrv" })
  settle()
  srv.client():stop()
  -- no event fires when a stop starts; any later reason to look again must not count it
  vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
  h.eq(facts.get(buf).servers, {}, "while it shuts down")
  srv.stop()
end)

h.case("a server detaching is not running, even read while LspDetach runs", function()
  local buf = open()
  local srv = fake_server.start({ buf = buf, name = "fakesrv" })
  settle()
  local seen
  local au = vim.api.nvim_create_autocmd("LspDetach", { buffer = buf, callback = function() seen = facts.get(buf).servers end })
  vim.lsp.buf_detach_client(buf, srv.id)
  vim.api.nvim_del_autocmd(au)
  h.eq(seen, {}, "read in LspDetach")
  settle()
  h.eq(facts.get(buf).servers, {}, "after")
  srv.stop()
end)

h.case("a read with no event since serves the facts as they were; ToolsChanged and an attach make the next read fresh", function()
  local buf, root, backend = open()
  facts.get(buf)
  -- A client attaches with every event ignored: only a cache that something invalidates would miss it
  local srv = fake_server.start({ buf = vim.api.nvim_create_buf(true, false), name = "fakesrv" })
  vim.o.eventignore = "all"
  vim.lsp.buf_attach_client(buf, srv.id)
  vim.o.eventignore = ""
  h.ok(vim.lsp.buf_is_attached(buf, srv.id), "set up: the client attached")
  h.eq(facts.get(buf).servers, {}, "no event since the last read")
  srv.stop()
  settle()
  h.await(function(done) backend.use_global({ "shfmt@latest" }, done) end)
  tools.refresh(root)
  h.await(function(done) tools.resolve("shfmt", root, done) end)
  settle()
  h.eq({ facts.get(buf).formatters, facts.get(buf).missing }, { { "stylua", "shfmt" }, {} }, "after shfmt was installed")
  local srv = fake_server.start({ buf = buf, name = "fakesrv" })
  settle()
  h.eq(facts.get(buf).servers, { "fakesrv" }, "after an attach")
  srv.stop()
end)

h.case("one FactsChanged per change, none for an event that changes nothing", function()
  local buf = open()
  facts.get(buf)
  local srv = fake_server.start({ buf = buf, name = "fakesrv" })
  settle()
  h.eq(changes, { buf }, "an attach")
  changes = {}
  vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf, modeline = false })
  settle()
  h.eq(changes, {}, "FileType and BufEnter that change nothing")
  srv.stop()
  h.eq(changes, { buf }, "a detach")
end)

h.case("a tool still resolving is neither run nor missing; the facts follow once it resolves, with one FactsChanged", function()
  local buf = open({ resolve = false })
  h.eq(brief(buf), { servers = {}, formatters = {}, linters = {}, missing = {}, unanswered = false }, "before resolving")
  h.ok(vim.wait(3000, function() return #changes > 0 end, 5), "no FactsChanged once the tools resolved")
  settle()
  h.eq(changes, { buf }, "events")
  h.eq(brief(buf), resolved, "resolved")
end)

h.case("facts read while a refresh finds the same tools again follow once it ends, though no ToolsChanged fires", function()
  local buf, root = open()
  facts.get(buf)
  tools.refresh(root)
  vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
  h.eq(facts.get(buf).formatters, {}, "while stylua resolves again")
  h.await(function(done) tools.resolve_all({ "stylua", "shfmt", "ruff", "yamllint" }, root, done) end)
  settle()
  h.eq(brief(buf), resolved, "after")
end)

h.case("a renamed buffer gets the root and checkout of its new place", function()
  local buf = open()
  local repo = tmp .. "/renamed"
  vim.fn.mkdir(repo .. "/.git", "p")
  facts.get(buf)
  vim.api.nvim_buf_set_name(buf, repo .. "/b.facts")
  h.eq({ facts.get(buf).root, facts.get(buf).repo }, { repo, repo })
end)

h.case("the git checkout: the folder's .git dir or file above it, none outside one", function()
  local repo, linked, outside = tmp .. "/repo", tmp .. "/linked", tmp .. "/outside"
  vim.fn.mkdir(repo .. "/.git", "p")
  h.write(linked .. "/.git", { "gitdir: " .. repo .. "/.git/worktrees/linked" })
  facts.setup()
  for _, case in ipairs({ { repo .. "/sub/a.txt", repo }, { linked .. "/a.txt", linked }, { outside .. "/a.txt", nil } }) do
    vim.cmd.edit(case[1])
    h.eq(facts.get(0).repo, case[2], case[1])
  end
  -- git init in outside/, then the buffer is entered again
  local buf = vim.api.nvim_get_current_buf()
  settle()
  h.eq(facts.get(buf).repo, nil, "before git init")
  vim.fn.mkdir(outside .. "/.git", "p")
  changes = {}
  vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf, modeline = false })
  settle()
  h.eq({ facts.get(buf).repo, changes }, { outside, { buf } }, "a checkout made since, on the next visit")
end)

h.finish()
