local NXO = { "n", "x", "o" }

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
  -- Labels for the runtime ftplugin's motions, which it maps without a desc, so the popup would show their rhs
  keys = {
    { "]]", label = "Next heading", mode = NXO },
    { "[[", label = "Previous heading", mode = NXO },
    filetypes = { "markdown" },
  },
}
