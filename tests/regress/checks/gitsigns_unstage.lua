-- @desc     <leader>Gu unstages the staged hunk under the cursor and never stages an unstaged one
-- @areas    git keys
-- @budget   20
vim.cmd.edit("main.lua")
local buf = vim.api.nvim_get_current_buf()
local gs = require("gitsigns")
if not check("gitsigns attaches to a tracked file", wait_until(function() return vim.b[buf].gitsigns_status_dict ~= nil end, 5000)) then return end
local function staged() return vim.system({ "git", "diff", "--cached", "--quiet" }):wait().code ~= 0 end
local function unstaged() return #(gs.get_hunks(buf) or {}) end
local function wait_git(pred, ms) return vim.wait(ms, pred, 100) end

vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "local changed = 2" })
if not check("the edit is an unstaged hunk", wait_until(function() return unstaged() == 1 end, 5000), unstaged()) then return end
vim.api.nvim_win_set_cursor(0, { 2, 0 })
feed("<leader>Gu")
-- staging is async; give a wrong stage time to land
local wrong = wait_git(staged, 1500)
if not check("<leader>Gu on an unstaged hunk stages nothing", not wrong, wrong and "the index now has the hunk" or nil) then return end

feed("<leader>Gs")
if not check("<leader>Gs stages the hunk", wait_git(function() return staged() and unstaged() == 0 end, 5000), unstaged()) then return end
vim.api.nvim_win_set_cursor(0, { 2, 0 })
feed("<leader>Gu")
check("<leader>Gu unstages the staged hunk", wait_git(function() return not staged() and unstaged() == 1 end, 5000), staged() and "still staged" or unstaged())
vim.cmd("edit!")
