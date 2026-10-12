-- JS / TS / JSON only. nvim-lspconfig also lists HTML, CSS and others, but its root_dir starts biome only in a
-- Biome project; those filetypes have their own servers, and the install offer would otherwise name biome there
return {
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
}
