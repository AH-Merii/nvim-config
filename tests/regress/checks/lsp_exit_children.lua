-- @desc     no process a server started outlives the server's exit or Neovim's, even when the server exits without stopping its own children: one killed while it initializes, one that finishes its shutdown, one given an exit_timeout, one restarted
-- @areas    lsp
-- @budget   40
-- @needs    ruff
-- tflint started its plugin child (tflint --act-as-bundled-plugin) and died of the quit's SIGTERM before it could stop
-- it, so the plugin outlived Neovim (CI run 39121923853). Any server can do the same, so stand-in ruff servers each
-- start a child that runs on until it is killed, as such a plugin does, and ignores SIGTERM. The harness quits next;
-- suite.sh fails the check if a child, or a server, is alive 3 s later.
local tools = require("tools")
-- Projects marked only by .venv (where the catalog finds ruff in a project), in a temp dir: FIX sits under a .git dir,
-- which ruff takes for its root
local base = vim.fn.tempname()
local ruff = tools.wait("ruff", FIX, 10000)
if not check("precondition: the suite's ruff resolves", ruff ~= nil and ruff.path ~= nil, vim.inspect(ruff)) then return end
local real = "exec " .. vim.fn.shellescape(ruff.path) .. ' "$@"'

-- server: what the stand-in runs as a server; detached: its child closes the server's pipes, so the server's client
-- sees it exit (a child holding them keeps the client from ever exiting)
local cases = {
  -- reads its input and never answers, so its client is still initializing at the quit
  initializing = { server = 'if [ "$1" = server ]; then exec cat >/dev/null; fi; ' .. real },
  initialized = { server = real },
  -- vim.lsp's own exit handler waits for it, so it is gone before this config's handler runs
  timeout = { server = real },
  -- restarted before the quit
  restart = { server = real, detached = true },
}
local bufs = {}
for name, case in pairs(cases) do
  local dir = base .. "/" .. name
  vim.fn.mkdir(dir .. "/.venv/bin", "p")
  case.log = dir .. "/children.log"
  local bin = dir .. "/.venv/bin/ruff"
  -- nvim-lint runs ruff too (ruff check ...): only the server starts the child
  local child = ("(trap '' TERM; exec sleep 600)%s &"):format(case.detached and " </dev/null >/dev/null 2>&1" or "")
  local start = ('if [ "$1" = server ]; then %s echo $! >> %s; fi'):format(child, vim.fn.shellescape(case.log))
  vim.fn.writefile({ "#!/bin/sh", start, case.server }, bin)
  vim.fn.setfperm(bin, "rwxr-xr-x")
  vim.fn.writefile({ "x = 1" }, dir .. "/x.py")
  vim.cmd.edit(dir .. "/x.py")
  bufs[name] = vim.api.nvim_get_current_buf()
end

local function alive(pid)
  local f = pid and io.open(("/proc/%d/stat"):format(pid))
  if not f then return false end
  local stat = f:read("*a") or ""
  f:close()
  return stat:match("%) (%a)") ~= "Z"
end
--- the pid of the first child the case's server started
local function child(name)
  local ok, lines = pcall(vim.fn.readfile, cases[name].log)
  return ok and tonumber(lines[1]) or nil
end
local function client(name) return vim.lsp.get_clients({ bufnr = bufs[name], name = "ruff" })[1] end

wait_until(function()
  return vim.iter(vim.tbl_keys(cases)):all(function(name) return alive(child(name)) end)
end, 15000)
local up = wait_until(function()
  return vim.iter({ "initialized", "timeout", "restart" }):all(function(name) return client(name) ~= nil and client(name).initialized end)
end, 15000)
check("precondition: the initialized servers' clients are up", up)
check("precondition: the initializing server's client is not", client("initializing") == nil)
for name in pairs(cases) do
  check(("precondition: the %s server's child runs"):format(name), alive(child(name)), tostring(child(name)))
end

if up then
  client("timeout").exit_timeout = 1000

  -- the restarted server's client is gone once its process exited; its child goes with it
  local old = client("restart")
  require("lsp").restart({ old })
  local exited = wait_until(function() return vim.lsp.get_client_by_id(old.id) == nil end, 5000)
  check("precondition: the restarted server's old client exited", exited)
  local gone = wait_until(function() return not alive(child("restart")) end, 2000)
  check("a restarted server's child does not outlive it", gone, tostring(child("restart")))
end
-- the harness quits next
