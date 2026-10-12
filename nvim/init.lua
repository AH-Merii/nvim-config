-- Tool resolver and sub-filetypes, before plugins: conform (BufWritePre) and nvim-lint (BufReadPre) look tools up through it
require("tools").setup()
-- Install prompts, :Tools and the statusline indicator; prompts need a UI and vim.g.install_tools ~= "off"
require("tools.ux").setup()
require("core.lsp")
require("config.options")
require("config.keymaps")
require("config.autocmds").setup()

require("core.lazy")

-- Late-load overrides after plugins are ready
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function() require("config.helpers") end,
})
