-- The linting module through its interface (require("linting")): a buffer's plan from a fixture language and the
-- fake tool backend, the "linter" need, and its runs, findings and relints against a fake nvim-lint. Servers are
-- in-process fakes: nvim --clean --headless -l tests/unit/linting_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local fake = require("fake_backend")
local server = require("fake_server")
local tools = require("tools")

local tmp = h.tmpdir()
require("tools.state").file = tmp .. "/state/projects.json"

-- A fixture language with linters the catalog knows; the ruff server reports what the ruff linter does
package.loaded.lang = require("lang")._from({
  one = { filetypes = { "fixone" }, linters = { ruff = { covered_by = "ruff" }, yamllint = {} } },
  none = { filetypes = { "fixnone" } },
})

-- nvim-lint, faked: each try_lint is logged with the linters its filter let through, as its wrap_linter left them
local runs = {} ---@type { buf: integer, ran: { name: string, cmd: string, cwd: string }[] }[]
local finding = { lnum = 0, col = 0, message = "a finding" }
local lint = {
  linters = {
    ruff = { cmd = "ruff", parser = function() return { finding } end },
    yamllint = { cmd = "yamllint", parser = function() return { finding } end },
  },
  linters_by_ft = {},
  get_namespace = function(name) return vim.api.nvim_create_namespace("fake-lint." .. name) end,
}
function lint.try_lint(names, opts)
  local ran, wrapped = {}, {}
  for _, name in ipairs(names) do
    local linter = vim.deepcopy(lint.linters[name] or {})
    linter.name = name
    if opts.filter(linter) then
      linter = opts.wrap_linter(vim.deepcopy(linter))
      table.insert(ran, { name = name, cmd = linter.cmd, cwd = linter.cwd })
      wrapped[name] = linter
    end
  end
  table.insert(runs, { buf = vim.api.nvim_get_current_buf(), ran = ran, linters = wrapped })
end
package.loaded.lint = lint

local linting = require("linting")
linting.setup()

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

--- Runs fn and waits for the ToolsChanged it causes.
local function changing(fn)
  local fired = false
  vim.api.nvim_create_autocmd("User", { pattern = tools.event, once = true, callback = function() fired = true end })
  fn()
  h.ok(vim.wait(3000, function() return fired end, 5), "no ToolsChanged")
end
local function resolved(root)
  changing(function() h.await(function(done) tools.resolve_all({ "ruff", "yamllint" }, root, done) end) end)
end

h.case("a plan lists the language's linters and runs those whose binary is found", function()
  local buf, root = setup({ ruff = "1.0.0" }, "fixone")
  resolved(root)
  h.eq(linting.plan(buf), { linters = { "ruff", "yamllint" }, run = { "ruff" }, covered = {} })
end)

h.case("a covered linter stops running while its server is attached, and only its own server covers it", function()
  local buf, root = setup({ ruff = "1.0.0", yamllint = "1.0.0" }, "fixone")
  resolved(root)
  h.eq(linting.plan(buf).run, { "ruff", "yamllint" }, "no server")
  local other = server.start({ buf = buf, name = "other" })
  h.eq(linting.plan(buf).run, { "ruff", "yamllint" }, "another server attached")
  local ruff = server.start({ buf = buf, name = "ruff" })
  h.eq({ linting.plan(buf).run, linting.plan(buf).covered }, { { "yamllint" }, { ruff = "ruff" } }, "the ruff server attached")
  -- a reader on LspDetach, as the statusline is, while the client still counts as attached
  local id = vim.api.nvim_create_autocmd("LspDetach", { callback = function(ev) linting.plan(ev.buf) end })
  ruff.stop()
  vim.api.nvim_del_autocmd(id)
  h.eq({ linting.plan(buf).run, linting.plan(buf).covered }, { { "ruff", "yamllint" }, {} }, "the ruff server stopped")
  other.stop()
end)

h.case("a plan follows a binary that appears, once ToolsChanged says so", function()
  local buf, root, system = setup({ ruff = "1.0.0" }, "fixone")
  resolved(root)
  h.eq(linting.plan(buf).run, { "ruff" }, "yamllint missing")
  h.bin(system .. "/yamllint", "1.0.0")
  changing(function() tools.refresh(root) end)
  h.eq(linting.plan(buf).run, { "ruff", "yamllint" }, "yamllint, found on the system PATH")
end)

h.case("a plan made while a refresh looks a binary up again fills in, also when the binary did not move", function()
  local buf, root = setup({ ruff = "1.0.0" }, "fixone")
  resolved(root)
  tools.refresh(root)
  vim.bo[buf].filetype = "fixone"
  h.ok(
    vim.wait(3000, function() return vim.deep_equal(linting.plan(buf).run, { "ruff" }) end, 5),
    "the plan never ran ruff again: " .. vim.inspect(linting.plan(buf))
  )
end)

--- Two project dirs: A has ruff in its .venv, B has nothing; their roots resolved, so no lookup is pending.
local function two_projects(n_)
  local a, b = ("%s/proj%d/a"):format(tmp, n_), ("%s/proj%d/b"):format(tmp, n_)
  h.bin(a .. "/.venv/bin/ruff", "1.0.0")
  vim.fn.mkdir(b .. "/.git", "p")
  resolved(b)
  return a, b
end

h.case("a buffer that isn't a file plans in the new cwd after :cd", function()
  setup({}, "fixnone")
  local a, b = two_projects(1)
  vim.cmd.cd(b)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].filetype = "fixone"
  h.eq(linting.plan(buf).run, {}, "in b")
  vim.cmd.cd(a)
  h.ok(vim.wait(3000, function() return vim.deep_equal(linting.plan(buf).run, { "ruff" }) end, 5), "in a: " .. vim.inspect(linting.plan(buf)))
  vim.cmd.cd(tmp)
end)

h.case("a renamed buffer plans in its new root", function()
  setup({}, "fixnone")
  local a, b = two_projects(2)
  vim.cmd.edit(h.write(b .. "/x.txt", { "x" }))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "fixone"
  h.eq(linting.plan(buf).run, {}, "in b")
  vim.cmd.file(a .. "/x.txt")
  h.ok(vim.wait(3000, function() return vim.deep_equal(linting.plan(buf).run, { "ruff" }) end, 5), "in a: " .. vim.inspect(linting.plan(buf)))
end)

h.case("a lint follows the buffer's root when a project marker appears, never running a linter unresolved", function()
  setup({ ruff = "1.0.0" }, "fixnone")
  local p = tmp .. "/marker"
  vim.cmd.edit(h.write(p .. "/sub/a.txt", { "x" }))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "fixone"
  resolved(p .. "/sub")
  runs = {}
  linting.buffer(buf)
  h.eq(runs[#runs].ran[1] and runs[#runs].ran[1].cwd, p .. "/sub", "the lint before the marker, from the file's dir")
  vim.fn.mkdir(p .. "/.git", "p")
  runs = {}
  linting.buffer(buf)
  h.ok(vim.wait(3000, function() return vim.iter(runs):any(function(r) return #r.ran > 0 end) end, 5), "no lint ran ruff after the marker")
  for _, r in ipairs(runs) do
    for _, ran in ipairs(r.ran) do
      h.eq({ ran.cwd, ran.cmd:find("/installs/ruff/1.0.0/bin/ruff$") ~= nil }, { p, true }, "a lint after the marker: " .. vim.inspect(ran))
    end
  end
end)

h.case("the linter need: the language names a linter, installed or not", function()
  h.eq(linting.has(setup({}, "fixone")), true, "named, nothing installed")
  h.eq(linting.has(setup({ ruff = "1.0.0" }, "fixnone")), false, "none named")
end)

h.case("a lint runs the linters that run, each with its resolved binary, from the project root", function()
  local buf, root = setup({ ruff = "1.0.0" }, "fixone")
  resolved(root)
  runs = {}
  linting.buffer(buf)
  h.eq(#runs, 1, "one lint")
  h.eq(runs[1].ran, { { name = "ruff", cmd = tools.get("ruff", root).path, cwd = root } }, "what ran")
  h.ok(runs[1].ran[1].cmd:find("/installs/ruff/1.0.0/bin/ruff$") ~= nil, "ruff from the fake backend's global install: " .. runs[1].ran[1].cmd)
end)

h.case("a covered linter's findings drop when its server attaches, and a run that ends after that reports none", function()
  local buf, root = setup({ ruff = "1.0.0", yamllint = "1.0.0" }, "fixone")
  resolved(root)
  runs = {}
  linting.buffer(buf)
  local ruff_ns, yaml_ns = lint.get_namespace("ruff"), lint.get_namespace("yamllint")
  vim.diagnostic.set(ruff_ns, buf, { finding })
  vim.diagnostic.set(yaml_ns, buf, { finding })
  local other = server.start({ buf = buf, name = "other" })
  h.eq(#vim.diagnostic.get(buf, { namespace = ruff_ns }), 1, "ruff's finding, with another server attached")
  local srv = server.start({ buf = buf, name = "ruff" })
  h.eq(#vim.diagnostic.get(buf, { namespace = ruff_ns }), 0, "ruff's finding, once the ruff server attached")
  h.eq(#vim.diagnostic.get(buf, { namespace = yaml_ns }), 1, "yamllint's finding, which no server covers")
  h.eq(runs[1].linters.ruff.parser("", buf), {}, "what the run started before the server attached reports")
  h.eq(#runs[1].linters.yamllint.parser("", buf), 1, "what yamllint's run reports")
  srv.stop()
  other.stop()
end)

h.case("ToolsChanged lints the root's buffers again with the linter that appeared, and only those", function()
  local buf, root, system = setup({ ruff = "1.0.0" }, "fixone")
  resolved(root)
  -- a buffer of the same filetype in another project
  local other = root .. "-other"
  vim.fn.mkdir(other .. "/.git", "p")
  vim.cmd.edit(h.write(other .. "/b.txt", { "x" }))
  vim.bo.filetype = "fixone"
  resolved(other)
  h.bin(system .. "/yamllint", "1.0.0")
  runs = {}
  changing(function() tools.refresh(root) end)
  h.eq(runs, { { buf = buf, ran = { { name = "yamllint", cmd = system .. "/yamllint", cwd = root } }, linters = runs[1] and runs[1].linters } })
end)

h.case("a nofile buffer is never linted: not on entering it, by an explicit lint or by ToolsChanged; it plans and needs no linter", function()
  local file, root, system = setup({ ruff = "1.0.0" }, "fixone")
  resolved(root)
  -- what vim.lsp.util.open_floating_preview makes for a hover: a scratch buffer (buftype nofile) given a filetype, whose
  -- root is the cwd
  vim.cmd.cd(root)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "fixone"
  runs = {}
  vim.api.nvim_set_current_buf(buf)
  linting.buffer(buf)
  h.bin(system .. "/yamllint", "1.0.0")
  changing(function() tools.refresh(root) end)
  local function linted(b) return vim.iter(runs):any(function(r) return r.buf == b end) end
  h.ok(linted(file), "ToolsChanged did not lint the file of the same filetype in the same root: " .. vim.inspect(runs))
  h.ok(not linted(buf), "the nofile buffer was linted: " .. vim.inspect(runs))
  h.eq({ linting.plan(buf), linting.has(buf) }, { { linters = {}, run = {}, covered = {} }, false }, "its plan and the linter need")
  vim.cmd.cd(tmp)
end)

h.case("a lint whose nvim-lint call raises passes the error on and leaves vim.uv.spawn as it was", function()
  local buf, root = setup({ ruff = "1.0.0" }, "fixone")
  resolved(root)
  local spawn, try = vim.uv.spawn, lint.try_lint
  lint.try_lint = function() error("nvim-lint failed") end
  local ok, err = pcall(linting.buffer, buf)
  lint.try_lint = try
  h.ok(not ok and tostring(err):find("nvim-lint failed", 1, true) ~= nil, "the error: " .. tostring(err))
  h.ok(rawequal(vim.uv.spawn, spawn), "vim.uv.spawn is still replaced")
end)

h.finish()
