-- @desc     gcc toggles comments in a parserless buffer (Comment.nvim pre_hook), gcc/gbc work in lua, gcc comments a markdown code fence
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
feed("gbc")
check("lua: gbc block comment", vim.fn.getline(1):find("^%-%-%[%[") ~= nil, vim.fn.getline(1))
vim.cmd("edit!")

-- ts-context-commentstring is not wired, so the fence may get either -- or <!-- -->; only "it comments" is asserted
vim.cmd.edit("notes.md")
local fence = vim.fn.search([[^print("hi")$]], "w")
check("markdown: fixture fence line found", fence > 0)
if fence > 0 then
  vim.api.nvim_win_set_cursor(0, { fence, 0 })
  feed("gcc")
  check("markdown lua fence: gcc comments the line", vim.fn.getline(fence) ~= 'print("hi")' and vim.fn.getline(fence):find('print("hi")', 1, true) ~= nil, vim.fn.getline(fence))
end
vim.cmd("edit!")
