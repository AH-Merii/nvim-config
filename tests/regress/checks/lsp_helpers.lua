-- @desc     the LSP status commands (features/lsp_status.lua) run; :LspInfo names the client and log; :LspLog opens the log in a tab; no deprecated LSP calls
-- @areas    lsp
-- @budget   30
-- @needs    lua-language-server
vim.cmd.edit("main.lua")
local buf = vim.api.nvim_get_current_buf()
local missing, why = wait_attach(buf, { "lua_ls" }, 15000)
check("lua_ls attached", #missing == 0, table.concat(why, "; "))

-- run with output captured and :silent so the printed report (which has "Errors:" lines) stays out of :messages
local function run(cmd)
  vim.v.errmsg = ""
  local ok, res = pcall(vim.api.nvim_exec2, "silent " .. cmd, { output = true })
  local out = ok and res.output or tostring(res)
  return ok and vim.v.errmsg == "", out
end
for _, cmd in ipairs({ "LspStatus", "LspCapabilities", "LspDiagnostics", "Status" }) do
  local ok, out = run(cmd)
  check(":" .. cmd .. " runs and prints a report", ok and out:find("%S") ~= nil, not ok and out or nil)
end
local ok, text = run("LspInfo")
check(":LspInfo runs", ok, not ok and text or nil)
check(":LspInfo shows the real log path", text:find(vim.lsp.log.get_filename(), 1, true) ~= nil, vim.lsp.log.get_filename())
check(":LspInfo lists the attached client", text:find("lua_ls", 1, true) ~= nil)

local tabs = #vim.api.nvim_list_tabpages()
local okl, err = pcall(vim.cmd, "LspLog")
check(":LspLog runs", okl, err)
check(":LspLog opens a new tab", #vim.api.nvim_list_tabpages() == tabs + 1)
local shown = vim.fn.resolve(vim.api.nvim_buf_get_name(0))
check(":LspLog shows the LSP log", shown == vim.fn.resolve(vim.lsp.log.get_filename()), shown)
vim.v.errmsg = ""

local dep = deprecations()
check("checkhealth vim.deprecated completed", dep ~= "TIMEOUT")
check("no client.is_stopped deprecation", not dep:find("is_stopped", 1, true))
check("no vim.lsp.get_log_path deprecation", not dep:find("get_log_path", 1, true))
