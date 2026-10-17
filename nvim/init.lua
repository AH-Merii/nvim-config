-- The languages' variant filetypes and buffer options, then the tool resolver, before plugins: conform (BufWritePre) and
-- nvim-lint (BufReadPre) look tools up through it
require("lang").setup()
require("tools").setup()
-- Install prompts, :Tools and the statusline indicator; prompts need a UI and vim.g.install_tools ~= "off"
require("tools.ux").setup()
-- Options first: the key rows below read mapleader. Neovim's keys before lsp.buffer, whose grr replaces Neovim's
require("config.options")
require("keys.neovim")
require("lsp.buffer")
require("config.keymaps")
require("config.autocmds").setup()

require("core.lazy")

-- Late-load overrides after plugins are ready
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = function() require("config.helpers") end,
})
