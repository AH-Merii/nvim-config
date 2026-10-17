-- Files: scratch buffers and renaming the file
local M = {}

function M.setup()
  local function icon(glyph, color) return { icon = glyph, color = color } end
  require("keys").feature("files")({
    { "<leader>.", function() Snacks.scratch({ ft = "markdown" }) end, "Toggle Scratch Buffer", icon = icon("󰎕", "grey") },
    { "<leader>lR", function() Snacks.rename.rename_file() end, "Rename File", icon = icon("󰑕", "green") },
  })
end

return M
