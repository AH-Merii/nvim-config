---@type lang.Spec
return {
  filetypes = { "css", "scss" },
  -- nvim-lspconfig's list, which has less too
  servers = { cssls = { filetypes = { "css", "scss", "less" } } },
  formatters = { "prettierd" },
}
