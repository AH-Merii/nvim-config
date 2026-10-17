-- @desc     hidden characters (NonText, SpecialKey) are drawn in the config's colour, not onedark's grey, after startup and after the colorscheme reloads
-- @areas    ui
-- @budget   15
local groups = { "NonText", "SpecialKey" }
local function hex(name)
  local fg = vim.api.nvim_get_hl(0, { name = name, link = false }).fg
  return fg and ("#%06x"):format(fg) or "none"
end
-- onedark draws both in its style's grey (onedark/highlights.lua, hl.common)
local grey = require("onedark.palette")[vim.g.onedark_config.style].grey

local startup = {}
for _, name in ipairs(groups) do
  startup[name] = hex(name)
  check(name .. " after startup is the config's colour, not onedark's grey", startup[name] ~= grey,
    ("%s, onedark's grey %s"):format(startup[name], grey))
end
vim.cmd.colorscheme("onedark")
for _, name in ipairs(groups) do
  check(name .. " keeps that colour after :colorscheme onedark", hex(name) == startup[name],
    ("startup %s, after reload %s"):format(startup[name], hex(name)))
end
