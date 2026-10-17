-- Server configs (lsp/*.lua) only; the lsp module enables them and runs each from the binary mise resolves
return {
  "neovim/nvim-lspconfig",
  lazy = false,
  config = function() require("lsp").setup() end,
}
