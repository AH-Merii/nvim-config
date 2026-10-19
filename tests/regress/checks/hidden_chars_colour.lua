-- @desc     hidden characters ('list') are drawn in one colour, whichever group draws them (NonText for eol, extends and precedes; Whitespace for space, lead, trail, tab and nbsp; SpecialKey), after startup and after the colorscheme reloads
-- @areas    ui
-- @budget   15
local groups = { "NonText", "Whitespace", "SpecialKey" }
local function hex(name)
  local fg = vim.api.nvim_get_hl(0, { name = name, link = false }).fg
  return fg and ("#%06x"):format(fg) or "none"
end

local function one_colour(when)
  local colours = {}
  for _, name in ipairs(groups) do
    colours[#colours + 1] = name .. " " .. hex(name)
  end
  local first = hex(groups[1])
  local same = vim.iter(groups):all(function(name) return hex(name) == first and first ~= "none" end)
  check("the hidden characters share one colour " .. when, same, table.concat(colours, ", "))
end

one_colour("after startup")
vim.cmd.colorscheme("onedark")
one_colour("after :colorscheme onedark")
