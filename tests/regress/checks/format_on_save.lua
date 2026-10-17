-- @desc     writing a file formats it before it is written, and not once <leader>Tf has turned formatting on save off
-- @areas    format keys
-- @budget   20
-- @needs    stylua
local BAD, GOOD = { "local   x  =  1", "return x" }, { "local x = 1", "return x" }
vim.fn.mkdir("save", "p")
vim.fn.writefile(BAD, "save/a.lua")
vim.cmd.edit("save/a.lua")
local buf = vim.api.nvim_get_current_buf()
-- the toggle is mapped at VeryLazy
wait_until(function() return wk_lists(buf, "n", "<leader>Tf") ~= nil end, 5000)
require("format").on_save.set(true)

vim.cmd.write()
check("on: the written file is formatted", vim.deep_equal(vim.fn.readfile("save/a.lua"), GOOD), vim.inspect(vim.fn.readfile("save/a.lua")))
check("on: the buffer is formatted and not modified", vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), GOOD) and not vim.bo[buf].modified)

local label = wk_lists(buf, "n", "<leader>Tf")
feed("<leader>Tf")
check("<leader>Tf flips its label", wait_until(function() return wk_lists(buf, "n", "<leader>Tf") ~= label end, 3000), label)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, BAD)
vim.cmd.write()
check("off: the file is written as it is", vim.deep_equal(vim.fn.readfile("save/a.lua"), BAD), vim.inspect(vim.fn.readfile("save/a.lua")))

feed("<leader>Tf")
vim.cmd.write()
check("on again: the written file is formatted", vim.deep_equal(vim.fn.readfile("save/a.lua"), GOOD), vim.inspect(vim.fn.readfile("save/a.lua")))
