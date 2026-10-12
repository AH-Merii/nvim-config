-- @desc     the tflint client gets exit_timeout 500 from after/lsp/tflint.lua
-- @areas    lsp
-- @budget   40
-- @version-sensitive
-- @needs    tflint
-- @allow-leak tflint known --act-as-bundled-plugin orphan
vim.fn.writefile({ 'variable "x" {}' }, FIX .. "/main.tf")
vim.cmd.edit(FIX .. "/main.tf")
local buf = vim.api.nvim_get_current_buf()
info("config exit_timeout: " .. tostring(vim.lsp.config.tflint.exit_timeout))
local missing, why = wait_attach(buf, { "tflint" }, 20000)
local c = vim.lsp.get_clients({ bufnr = buf, name = "tflint" })[1]
check("tflint attached", c ~= nil, #missing > 0 and table.concat(why, "; ") or nil)
check("tflint client exit_timeout == 500", c ~= nil and c.exit_timeout == 500, c and tostring(c.exit_timeout))
