-- Server configs (lsp/*.lua) only; core.lsp_servers enables them and runs each from the binary mise resolves
return {
  "neovim/nvim-lspconfig",
  lazy = false,
  config = function() require("core.lsp_servers").setup() end,
}
