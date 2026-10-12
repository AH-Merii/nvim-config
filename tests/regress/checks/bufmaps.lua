-- @desc     maps set with buf= stay buffer-local (lua ftplugin, q in help) and q closes the help window
-- @areas    keys
-- @budget   10
vim.cmd.edit("main.lua")
local m = vim.fn.maparg("<space>!", "n", false, true)
check("lua ftplugin map exists and is buffer-local", m.buffer == 1, vim.inspect(m.buffer))
vim.cmd.edit("app.py")
check("lua ftplugin map does not leak into other buffers", vim.fn.maparg("<space>!", "n") == "", vim.fn.maparg("<space>!", "n"))
vim.cmd("help help")
local q = vim.fn.maparg("q", "n", false, true)
check("q is buffer-local in help", q.buffer == 1, vim.inspect(q.buffer))
local wins = #vim.api.nvim_list_wins()
feed("q")
check("q closes the help window", wait_until(function() return #vim.api.nvim_list_wins() == wins - 1 end, 2000))
