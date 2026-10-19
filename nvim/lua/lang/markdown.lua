local NXO = { "n", "x", "o" }

---@type lang.Spec
return {
  filetypes = { "markdown" },
  servers = { marksman = {} },
  formatters = { "prettierd" },
  linters = { ["markdownlint-cli2"] = {} },
  -- Carried over from the config's first treesitter setup, whose history gives no reason for either (D128). Markdown
  -- has no runtime indent plugin, so no indent means autoindent's
  treesitter = { indent = false, syntax = true },
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
