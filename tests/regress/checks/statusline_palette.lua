-- @desc     the statusline's path colours come from onedark's active style
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
local function hex(name)
  local fg = vim.api.nvim_get_hl(0, { name = name, link = false }).fg
  return fg and ("#%06x"):format(fg) or "none"
end
-- the project name, the directories and the file name of the path component
for _, group in ipairs({ "LualineProjectRoot", "LualinePath", "LualineFilename" }) do
  check(("%s is a colour of onedark's %s style"):format(group, style), colours[hex(group)] == true, hex(group))
end
