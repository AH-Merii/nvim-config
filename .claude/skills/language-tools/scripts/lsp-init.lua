-- usage: nvim --clean --headless -l lsp-init.lua <server binary> [args...]
-- Starts the server, sends `initialize`, prints serverInfo and the capability names, then shuts it down.
-- Exits 0 when the server answered, 1 on an error or no answer within 20s.
local cmd = _G.arg
if not cmd or #cmd == 0 then
  print("usage: nvim --clean --headless -l lsp-init.lua <server binary> [args...]")
  os.exit(2)
end
local client = vim.lsp.rpc.start(cmd, {
  on_exit = function(code) io.stderr:write("server exited " .. code .. "\n") end,
}, { cwd = vim.uv.cwd() })
local res, err
client.request("initialize", { processId = vim.uv.os_getpid(), rootUri = vim.uri_from_fname(vim.uv.cwd()), capabilities = vim.empty_dict() }, function(e, r) err, res = e, r end)
local ok = vim.wait(20000, function() return res ~= nil or err ~= nil end, 20)
if not ok or err then
  print("FAIL", ok and vim.inspect(err) or "no answer in 20s")
  os.exit(1)
end
print("serverInfo", vim.inspect(res.serverInfo))
local caps = vim.tbl_keys(res.capabilities or {})
table.sort(caps)
print("capabilities", table.concat(caps, " "))
client.request("shutdown", nil, function() client.notify("exit") end)
vim.wait(2000, function() return client.is_closing() end)
os.exit(0)
