-- The popup lives in lua/keys/: its spec, groups and filter come from the key rows (keys/which_key.lua)
require("keys").feature("which-key")({
  "<leader>?",
  function() require("which-key").show({ global = false }) end,
  "Buffer Local Keymaps (which-key)",
})

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  config = function() require("keys.which_key").setup() end,
}
