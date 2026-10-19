local NXO = { "n", "x", "o" }

---@type lang.Spec
return {
  filetypes = { "markdown" },
  servers = { marksman = {} },
  formatters = { "prettierd" },
  linters = { ["markdownlint-cli2"] = {} },
  -- Autoindent's (D135), as markdown has no runtime indent plugin: nvim-treesitter's (only `(list_item) @indent.auto`)
  -- indents no better and costs ~36 ms per `o` on a 2050-line file, against ~1.3 ms. No regex syntax beside
  -- treesitter: it drew `_` inside words as errors and made a page scroll take 7 to 12 ms, against about 2; spelling
  -- in table cells, which only it gave, is queries/markdown/highlights.scm
  treesitter = { indent = false },
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
