-- Profiling: snacks' profiler
local M = {}

function M.setup()
  local function icon(glyph, color) return { icon = glyph, color = color } end
  require("keys").feature("profiling")({
    { "<leader>P", group = "Profiler", icon = icon("󰓅", "orange") },
    { "<leader>Pp", function() Snacks.profiler.toggle() end, "Toggle Profiler" },
    { "<leader>Ps", function() Snacks.profiler.scratch() end, "Profiler Scratch" },
    { "<leader>Ph", function() Snacks.profiler.highlight() end, "Profiler Highlight" },
  })
end

return M
