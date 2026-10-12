-- @desc     VimResized equalises windows and leaves the user on the tab they were on
-- @areas    ui
-- @budget   10
vim.cmd.edit("main.lua")
vim.cmd("vsplit | vertical resize 20")
vim.cmd("tabnew app.py")
vim.cmd("tabfirst")
local first = vim.api.nvim_get_current_tabpage()
local w = vim.api.nvim_tabpage_list_wins(first)
local before = math.abs(vim.api.nvim_win_get_width(w[1]) - vim.api.nvim_win_get_width(w[2]))
vim.api.nvim_exec_autocmds("VimResized", {})
check("stays on the current tab", vim.api.nvim_get_current_tabpage() == first)
local after = math.abs(vim.api.nvim_win_get_width(w[1]) - vim.api.nvim_win_get_width(w[2]))
check("windows equalised", before > 1 and after <= 1, ("width diff %d -> %d"):format(before, after))
