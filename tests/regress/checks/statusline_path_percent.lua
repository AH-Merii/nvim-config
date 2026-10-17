-- @desc     a % in a directory or file name shows as itself in the statusline's path, at full width and when only the file name fits
-- @areas    ui
-- @budget   15
vim.fn.mkdir("100%", "p")
vim.fn.writefile({ "return 1" }, "100%/a%b.lua")
vim.cmd.edit(vim.fn.fnameescape("100%/a%b.lua"))
local function statusline()
  require("lualine").refresh({ place = { "statusline" }, force = true })
  return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win(), maxwidth = 400 }).str
end
for _, case in ipairs({
  { width = 400, want = "100%/a%b.lua", what = "the directory and file name" },
  { width = 20, want = "a%b.lua", what = "the file name alone" },
}) do
  vim.o.columns = case.width
  local drawn = statusline()
  check(("%d columns: %s draw as typed"):format(case.width, case.what), drawn:find(case.want, 1, true) ~= nil, drawn)
end
