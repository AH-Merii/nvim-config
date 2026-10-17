-- @desc     quitting leaves no server process behind, whatever each server is doing: tflint still initializing (and its bundled plugin child), yamlls busy validating a large file, lua_ls ignoring shutdown while its pipes are open
-- @areas    lsp
-- @budget   40
-- @needs    tflint yaml-language-server lua-language-server

-- Neovim's exit handler stops only initialized clients, waits only for a numeric exit_timeout (none by default),
-- then exits and closes the pipes of every server still running. Each server below would outlive Neovim in its own
-- way; the harness quits next, and suite.sh fails the check if any of them, or a child, is alive 3 s later.

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

--- the first of pid's children whose command line has an argument ending in arg (nvim-lint may be running tflint as a
--- linter too). Each thread lists the children it forked, and Go forks from any thread, so nvim_get_proc_children can
--- miss them
local function child(pid, arg)
  for tid in vim.fs.dir("/proc/" .. pid .. "/task") do
    for p in read(("/proc/%d/task/%s/children"):format(pid, tid)):gmatch("%d+") do
      for _, a in ipairs(vim.split(read("/proc/" .. p .. "/cmdline"), "\0")) do
        if vim.endswith(a, arg) then return tonumber(p) end
      end
    end
  end
end

vim.fn.writefile({ 'variable "x" {}' }, "main.tf")
vim.fn.writefile({ "local x = 1" }, "init.lua")

vim.cmd.edit("main.tf")
vim.cmd.edit("init.lua")
local missing, why = wait_attach(vim.api.nvim_get_current_buf(), { "lua_ls" }, 20000)
check("precondition: lua_ls attached", #missing == 0, table.concat(why, "; "))
-- tflint starts its plugin child (tflint --act-as-bundled-plugin) on its own; once it answered, both are up
local servers = {}
wait_until(function()
  servers.tflint = child(vim.fn.getpid(), "--langserver")
  servers.plugin = servers.tflint and child(servers.tflint, "--act-as-bundled-plugin")
  return answered and servers.plugin ~= nil
end, 15000)

-- yamlls parses a document on its main thread when first asked about it, about 5 s for 20000 entries here, and reads
-- the EOF of its closed pipes only once done. Asked last, and quit while it is at it
local big = { "services:" }
for i = 1, 20000 do
  vim.list_extend(big, { ("  s%d:"):format(i), ("    image: nginx:%d"):format(i), ("    environment: [A=%d]"):format(i) })
end
vim.fn.writefile(big, "big.yaml")
vim.cmd.edit("big.yaml")
missing, why = wait_attach(vim.api.nvim_get_current_buf(), { "yamlls" }, 20000)
check("precondition: yamlls attached", #missing == 0, table.concat(why, "; "))
servers.yamlls = child(vim.fn.getpid(), "yaml-language-server")
--- the CPU time pid has used, in clock ticks (utime + stime, proc_pid_stat(5))
local function cpu(pid)
  local fields = vim.split((read(("/proc/%d/stat"):format(pid)):match("%) (.*)") or ""), " ")
  return (tonumber(fields[12]) or 0) + (tonumber(fields[13]) or 0)
end
local yamlls, answered_symbols = vim.lsp.get_clients({ bufnr = 0, name = "yamlls" })[1], false
local used = servers.yamlls and cpu(servers.yamlls)
if yamlls and used then
  yamlls:request("textDocument/documentSymbol", { textDocument = vim.lsp.util.make_text_document_params() }, function() answered_symbols = true end)
  wait_until(function() return cpu(servers.yamlls) - used >= 20 end, 10000)
end
local busy = used and cpu(servers.yamlls) - used
check("precondition: yamlls is busy with the document", busy and busy >= 20 and not answered_symbols, ("%s ticks of CPU"):format(busy))
servers.lua_ls = child(vim.fn.getpid(), "lua-language-server")
for _, name in ipairs({ "tflint", "plugin", "yamlls", "lua_ls" }) do
  check(("precondition: %s runs"):format(name), servers[name] ~= nil, vim.inspect(servers))
end
check("precondition: tflint answered initialize", answered)
check("precondition: the tflint client is still initializing", #vim.lsp.get_clients({ name = "tflint" }) == 0)
-- the harness quits next
