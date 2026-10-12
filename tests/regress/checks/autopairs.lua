-- @desc     brackets auto-pair in lua, the table trailing-comma rule fires inside a table, and typing pairs prints nothing
-- @areas    editing treesitter
-- @budget   15
vim.cmd.edit("main.lua")
local buf = vim.api.nvim_get_current_buf()
wait_until(function() return vim.treesitter.highlighter.active[buf] ~= nil end, 3000)
vim.cmd("messages clear")
-- the event loop runs between a user's keystrokes; without that turn :edit! races treesitter's scheduled fold updates
local function type_keys(keys)
  feed(keys)
  local turned = false
  vim.schedule(function() turned = true end)
  wait_until(function() return turned end, 1000)
end
type_keys("Golocal t = {<Esc>")
type_keys("olocal u = (<Esc>")
local line1 = vim.fn.getline(vim.fn.line(".") - 1)
check("lua: { auto-pairs outside a table", line1 == "local t = {}", line1)
check("lua: ( auto-pairs", vim.fn.getline(".") == "local u = ()", vim.fn.getline("."))
type_keys("Golocal z = { a = {<Esc>")
local z = vim.fn.getline(".")
check("lua: { inside a table constructor closes with a trailing comma", z == "local z = { a = {}, }" or z == "local z = { a = {},", z)
local msgs = vim.api.nvim_exec2("messages", { output = true }).output
check("typing pairs adds nothing to :messages", vim.trim(msgs) == "", msgs)
vim.cmd("edit!")
