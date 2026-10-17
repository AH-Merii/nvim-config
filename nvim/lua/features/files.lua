-- Files: writing, quitting, scratch buffers and renaming the file
local M = {}

function M.setup()
  local function icon(glyph, color) return { icon = glyph, color = color } end
  require("keys").feature("files")({
    { "<leader>.", function() Snacks.scratch({ ft = "markdown" }) end, "Toggle Scratch Buffer", icon = icon("󰎕", "grey") },
    { "<leader>lR", function() Snacks.rename.rename_file() end, "Rename File", icon = icon("󰑕", "green") },
  })

  require("keys").feature("files")({
    -- Fast saving
    { "<leader>w", ":write!<CR>", "Write", silent = true, icon = { icon = "", color = "green" } },
    { "<leader>q", ":q!<CR>", "Quit", silent = true, icon = { icon = "", color = "red" } },
  })
end

return M
