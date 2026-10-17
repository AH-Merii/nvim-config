-- @desc     quitting while a server is still initializing leaves no process behind: tflint and its bundled plugin child exit with Neovim
-- @areas    lsp
-- @budget   20
-- @needs    tflint

-- tflint's answer to initialize never reaches its client, so the client is still initializing when the harness quits;
-- quitting in the same window by hand is a race, this holds it open
local rpc = vim.lsp.rpc
local start, answered = rpc.start, false
rpc.start = function(cmd, ...)
  local client = start(cmd, ...)
  if type(cmd) == "table" and vim.fs.basename(cmd[1]) == "tflint" then
    local request = client.request
    client.request = function(method, params, callback, ...)
      if method == "initialize" then
        return request(method, params, function() answered = true end, ...)
      end
      return request(method, params, callback, ...)
    end
  end
  return client
end

local function read(path)
  local f = io.open(path)
  if not f then return "" end
  local text = f:read("*a") or ""
  f:close()
  return text
end

--- the first of pid's children whose command line has arg (nvim-lint may be running tflint as a linter too). Each
--- thread lists the children it forked, and Go forks from any thread, so nvim_get_proc_children can miss them
local function child(pid, arg)
  for tid in vim.fs.dir("/proc/" .. pid .. "/task") do
    for p in read(("/proc/%d/task/%s/children"):format(pid, tid)):gmatch("%d+") do
      if vim.list_contains(vim.split(read("/proc/" .. p .. "/cmdline"), "\0"), arg) then return tonumber(p) end
    end
  end
end

vim.fn.writefile({ 'variable "x" {}' }, "main.tf")
vim.cmd.edit("main.tf")
-- tflint starts its plugin child (tflint --act-as-bundled-plugin) on its own; once it answered, both are up
local server, plugin
wait_until(function()
  server = child(vim.fn.getpid(), "--langserver")
  plugin = server and child(server, "--act-as-bundled-plugin")
  return answered and plugin ~= nil
end, 15000)
check("precondition: tflint answered initialize and runs its plugin child", answered and plugin ~= nil, ("answered=%s server=%s plugin=%s"):format(answered, server, plugin))
check("precondition: the tflint client is still initializing", #vim.lsp.get_clients({ name = "tflint" }) == 0)
-- the harness quits next; suite.sh fails the check if tflint or its plugin outlive it
