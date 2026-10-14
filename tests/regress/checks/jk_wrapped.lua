-- @desc     j and k move by screen line through a wrapped line and by real lines with a count, and stop quietly at the ends
-- @areas    keys editing
-- @budget   10
vim.o.columns, vim.o.lines = 80, 30
local lines = { "one", "two", ("x"):rep(300) }
for i = 4, 40 do
  lines[i] = "line " .. i
end
vim.fn.writefile(lines, "wrapped.txt")
vim.cmd.edit("wrapped.txt")
vim.wo.wrap = true
local function at() return { vim.fn.line("."), vim.fn.winline() } end

vim.api.nvim_win_set_cursor(0, { 3, 0 })
local row = vim.fn.winline()
feed("j")
check("j on a wrapped line goes to its next screen line", vim.deep_equal(at(), { 3, row + 1 }), vim.inspect(at()))
feed("k")
check("k comes back up it", vim.deep_equal(at(), { 3, row }), vim.inspect(at()))
feed("5j")
check("5j moves 5 real lines", at()[1] == 8, vim.inspect(at()))
feed("2k")
check("2k moves 2 real lines", at()[1] == 6, vim.inspect(at()))
vim.cmd("normal! G")
vim.v.errmsg = ""
feed("j")
check("j on the last line stays there with no error", at()[1] == 40 and vim.v.errmsg == "", vim.inspect({ at(), vim.v.errmsg }))
