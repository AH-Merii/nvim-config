-- @desc     gitsigns sees edits to a tracked file as hunks, and ]g / [g move between them
-- @areas    git keys
-- @budget   15
vim.cmd.edit("main.lua")
local buf = vim.api.nvim_get_current_buf()
local gs = require("gitsigns")
check("gitsigns attaches to a tracked file", wait_until(function() return vim.b[buf].gitsigns_status_dict ~= nil end, 5000))
vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "local changed = 2" })
vim.api.nvim_buf_set_lines(buf, 6, 7, false, { "return M -- changed" })
local function hunks() return gs.get_hunks(buf) or {} end
check("two hunks detected", wait_until(function() return #hunks() == 2 end, 5000), #hunks())
local function move(keys, want)
  feed(keys)
  wait_until(function() return vim.fn.line(".") == want end, 2000)
  return vim.fn.line(".")
end
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local l = move("]g", 2)
check("]g goes to the first hunk", l == 2, l)
l = move("]g", 7)
check("]g goes to the second hunk", l == 7, l)
l = move("[g", 2)
check("[g goes back", l == 2, l)
vim.cmd("edit!")
