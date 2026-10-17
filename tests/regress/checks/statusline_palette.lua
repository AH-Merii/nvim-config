-- @desc     the statusline's path draws its project, folders and file name in colours of onedark's active style
-- @areas    ui
-- @budget   15
local style = vim.g.onedark_config.style
local palette = require("onedark.palette")[style]
check("onedark has a palette for the active style", palette ~= nil, style)
if not palette then return end
local colours = {}
for _, value in pairs(palette) do
  colours[value] = true
end

vim.fn.mkdir("deep/folder", "p")
vim.fn.writefile({ "return 1" }, "deep/folder/file.lua")
vim.o.columns = 200
vim.cmd.edit("deep/folder/file.lua")
local project = vim.fs.basename(FIX)
local path = project .. "/deep/folder/file.lua"
local function drawn()
  return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win(), maxwidth = 200, highlights = true })
end
wait_until(function() return drawn().str:find(path, 1, true) ~= nil end, 2000)
local line = drawn()
--- The fg of the colour the line draws at byte `at` (0-based), as "#rrggbb"
local function fg_at(at)
  local group
  for _, h in ipairs(line.highlights) do
    if h.start <= at then
      group = h.groups and h.groups[#h.groups] or h.group
    end
  end
  local fg = group and vim.api.nvim_get_hl(0, { name = group, link = false }).fg
  return fg and ("#%06x"):format(fg) or "none"
end
local start = line.str:find(path, 1, true)
if not check("the path shows the project, its folders and the file", start ~= nil, line.str) then return end
for _, part in ipairs({
  { what = "project name", at = start - 1 },
  { what = "folder names", at = start + #project },
  { what = "file name", at = start - 1 + #project + #"/deep/folder/" },
}) do
  local fg = fg_at(part.at)
  check(("%s: drawn in a colour of onedark's %s style"):format(part.what, style), colours[fg] == true, fg)
end
