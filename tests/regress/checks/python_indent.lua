-- @desc     in python, a new line keeps its block's indent after a one-line compound statement and after a line with a bracket in a string or comment, and aligns after an open paren, also after <leader>TT turns treesitter off and on
-- @areas    treesitter editing
-- @budget   15
local lines = {
  "def extract(s, items, out, p):",
  "    i = s.find('\"interviews\":[{')",
  '    for it in items: it["_page"] = p; out[it["id"]] = it',
  "    x = 1  # a [ in a comment",
  '    s = "a[{"',
  "    result = call(alpha,",
}
-- line -> the indent `o` gives the line it opens below it
local cases = {
  { 3, 4, "after a one-line for, below a line with an open bracket in a string" },
  { 4, 4, "after a line with an open bracket in a comment" },
  { 5, 4, "after a line with open brackets in a string" },
  { 6, 18, "after an open paren with an argument, aligned with it" },
}
vim.fn.writefile(lines, "indent.py")
vim.cmd.edit("indent.py")
local buf = vim.api.nvim_get_current_buf()
check("treesitter attaches", wait_until(function() return vim.treesitter.highlighter.active[buf] ~= nil end, 3000))

local function run(when)
  for _, c in ipairs(cases) do
    local line, want, what = c[1], c[2], c[3]
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    feed("oX<Esc>")
    local got = vim.fn.indent(line + 1)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    check(("%s: %s, indent %d"):format(when, what, want), got == want, got)
  end
end
run("once treesitter attaches")
feed("<Space>TT")
feed("<Space>TT")
check("<leader>TT turns treesitter off and on", vim.treesitter.highlighter.active[buf] ~= nil)
run("after <leader>TT off and on")
