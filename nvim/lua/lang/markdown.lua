---@type lang.Spec
return {
  filetypes = { "markdown" },
  parsers = { "markdown", "markdown_inline" },
  servers = { marksman = {} },
  formatters = { "prettierd" },
  linters = { ["markdownlint-cli2"] = {} },
  variants = {
    ["markdown.mdx"] = { about = "MDX, from nvim-lspconfig's marksman filetypes; nothing in Neovim or this config sets it" },
  },
}
