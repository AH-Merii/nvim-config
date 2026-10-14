-- @desc     the statuscolumn numbers the cursor line absolutely and the rest relative to it right after the cursor moves or 'relativenumber' changes, and shows a mark set on a line
-- @areas    ui
-- @budget   15
local lines = {}
for i = 1, 40 do
  lines[i] = "line " .. i
end
vim.fn.writefile(lines, "numbers.txt")
vim.cmd.edit("numbers.txt")
vim.wo.number, vim.wo.relativenumber = true, true

local function row(lnum) return vim.api.nvim_eval_statusline(vim.o.statuscolumn, { winid = 0, use_statuscol_lnum = lnum }).str end
local function numbers(from, to)
  local out = {}
  for l = from, to do
    out[#out + 1] = tonumber(row(l):match("(%d+)%s*$"))
  end
  return out
end

vim.api.nvim_win_set_cursor(0, { 5, 0 })
check("cursor on line 5: lines 3 to 7 read 2 1 5 1 2", vim.deep_equal(numbers(3, 7), { 2, 1, 5, 1, 2 }), vim.inspect(numbers(3, 7)))
-- right away, within any cache's lifetime
vim.api.nvim_win_set_cursor(0, { 6, 0 })
check("after moving to line 6: lines 3 to 7 read 3 2 1 6 1", vim.deep_equal(numbers(3, 7), { 3, 2, 1, 6, 1 }), vim.inspect(numbers(3, 7)))
vim.wo.relativenumber = false
check("with 'norelativenumber': lines 3 to 7 read 3 to 7", vim.deep_equal(numbers(3, 7), { 3, 4, 5, 6, 7 }), vim.inspect(numbers(3, 7)))
vim.wo.relativenumber = true

vim.api.nvim_buf_set_mark(0, "q", 3, 0, {})
wait_until(function() return row(3):find("q", 1, true) ~= nil end, 2000)
check("a mark set on line 3 shows on its row", row(3):find("q", 1, true) ~= nil, vim.inspect(row(3)))
check("and not on the next", row(4):find("q", 1, true) == nil, vim.inspect(row(4)))
