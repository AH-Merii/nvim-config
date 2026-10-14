-- @desc     the statusline shows the cursor's line, column and place in the file right after it moves, before lualine rebuilds it, and the search count as the cursor moves between matches
-- @areas    ui
-- @budget   15
-- Headless, moving the cursor fires no CursorMoved, so lualine rebuilds nothing unless the check fires an event.
local lines = {}
for i = 1, 100 do
  lines[i] = (i == 20 or i == 40 or i == 60) and "a needle here" or ("word " .. i)
end
vim.fn.writefile(lines, "statusline.txt")
vim.cmd.edit("statusline.txt")
require("lualine").refresh({ place = { "statusline" }, force = true })
local function statusline()
  return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win(), maxwidth = 400 }).str
end
local function has(s) return statusline():find(s, 1, true) ~= nil end

vim.api.nvim_win_set_cursor(0, { 11, 3 })
check("on line 11 at column 4: 11:4", has("11:4"), statusline())
check("and 11% through the file", has("11%"), statusline())
vim.api.nvim_win_set_cursor(0, { 1, 0 })
check("on the first line: Top", has("Top"), statusline())
vim.api.nvim_win_set_cursor(0, { 100, 0 })
check("on the last line: Bot", has("Bot"), statusline())

vim.fn.setreg("/", "needle")
vim.o.hlsearch = true
vim.v.hlsearch = 1
-- lualine applies a refresh on its next 16 ms tick; its own timer refreshes once a second, so a count that comes
-- only from that timer is mostly still missing after 100 ms
vim.api.nvim_win_set_cursor(0, { 20, 2 })
vim.api.nvim_exec_autocmds("CursorMoved", {})
wait_until(function() return has("[1/3]") end, 100)
check("on the first of three matches: [1/3]", has("[1/3]"), statusline())
vim.api.nvim_win_set_cursor(0, { 40, 2 })
vim.api.nvim_exec_autocmds("CursorMoved", {})
wait_until(function() return has("[2/3]") end, 100)
check("on the second: [2/3]", has("[2/3]"), statusline())
