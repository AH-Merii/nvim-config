-- JavaScript, TypeScript and JSON: biome formats and lints, tsc (TS 7's --lsp) serves the scripts
local scripts = { "javascript", "javascriptreact", "typescript", "typescriptreact" }

---@type lang.Spec
return {
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
  parsers = { "javascript", "typescript", "tsx", "json" },
  servers = {
    tsc = { filetypes = scripts },
    -- nvim-lspconfig also lists HTML, CSS and others, but its root_dir starts biome only in a Biome project; those
    -- filetypes have their own servers, and the install offer would otherwise name biome there
    biome = {},
  },
  formatters = { "biome" },
  linters = { biomejs = { covered_by = "biome" } },
}
