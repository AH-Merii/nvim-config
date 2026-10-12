-- @desc     each project gets its own server even without the server's root markers, and a refresh that moves the binary restarts the running server from the new one, in that project only
-- @areas    lsp tools
-- @budget   40
-- @needs    ruff
-- Two projects marked only by .venv (a tools root marker, not one of ruff's), in a temp dir: FIX and the run dir
-- sit under .git dirs, which ruff takes for its root. A stand-in .venv/bin/ruff in one of them logs its args and
-- runs the suite's ruff.
local tools = require("tools")
local base = vim.fn.tempname()
local a, b = base .. "/a", base .. "/b"
local log = base .. "/started.log"
local bufs = {}
for _, dir in ipairs({ a, b }) do
  vim.fn.mkdir(dir .. "/.venv/bin", "p")
  vim.fn.writefile({ "x = 1" }, dir .. "/x.py")
  vim.cmd.edit(dir .. "/x.py")
  bufs[dir] = vim.api.nvim_get_current_buf()
end
local function client(dir) return vim.lsp.get_clients({ bufnr = bufs[dir], name = "ruff" })[1] end

local up = wait_until(function() return client(a) ~= nil and client(b) ~= nil end, 15000)
if not check("ruff attaches in both projects", up, ("a=%s b=%s"):format(tostring(client(a) ~= nil), tostring(client(b) ~= nil))) then
  vim.fn.delete(base, "rf")
  return
end
local ca, cb = client(a), client(b)
check(
  "one client per project, rooted there",
  ca.id ~= cb.id and ca.root_dir == a and cb.root_dir == b,
  ("%s %s"):format(tostring(ca.root_dir), tostring(cb.root_dir))
)

local global = tools.get("ruff", a)
local bin = a .. "/.venv/bin/ruff"
vim.fn.writefile({ "#!/bin/sh", 'echo "$*" >> ' .. vim.fn.shellescape(log), "exec " .. vim.fn.shellescape(global.path) .. ' "$@"' }, bin)
vim.fn.setfperm(bin, "rwxr-xr-x")
tools.refresh(a)
local moved = wait_until(function()
  local now = client(a)
  return now ~= nil and now.id ~= ca.id and now.initialized
end, 15000)
check("the refresh that moved ruff restarted project a's server", moved, vim.inspect(tools.get("ruff", a)))
local ok, lines = pcall(vim.fn.readfile, log)
check(
  "the new server runs the project's binary",
  ok and vim.iter(lines):any(function(l) return l:find("^server") ~= nil end),
  ok and table.concat(lines, " | ") or "no log"
)
check("project b's server kept running", client(b) ~= nil and client(b).id == cb.id)
vim.lsp.stop_client(vim.lsp.get_clients({ name = "ruff" }), true)
vim.fn.delete(base, "rf")
