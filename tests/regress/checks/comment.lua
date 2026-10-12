-- @desc     built-in gcc toggles comments in a parserless buffer and in lua, and comments a markdown code fence in the fence's language
-- @areas    editing treesitter
-- @budget   15
vim.cmd.edit("app.conf")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("gcc")
check("conf (no parser): gcc comments the line", vim.fn.getline(1) == "# key = value", vim.fn.getline(1))
feed("gcc")
check("conf (no parser): gcc uncomments it", vim.fn.getline(1) == "key = value", vim.fn.getline(1))
vim.cmd("edit!")

vim.cmd.edit("main.lua")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("gcc")
check("lua: gcc line comment", vim.fn.getline(1) == "-- local M = {}", vim.fn.getline(1))
feed("gcc")
check("lua: gcc uncomments it", vim.fn.getline(1) == "local M = {}", vim.fn.getline(1))
vim.cmd("edit!")

-- the commentstring comes from the injected language at the cursor (:h commenting)
vim.cmd.edit("notes.md")
local fence = vim.fn.search([[^print("hi")$]], "w")
check("markdown: fixture fence line found", fence > 0)
if fence > 0 then
  vim.api.nvim_win_set_cursor(0, { fence, 0 })
  feed("gcc")
  check("markdown lua fence: gcc comments the line as lua", vim.fn.getline(fence) == '-- print("hi")', vim.fn.getline(fence))
end
vim.cmd("edit!")
