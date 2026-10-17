---@type lang.Spec
return {
  filetypes = { "rust" },
  parsers = { "rust" },
  servers = {
    rust_analyzer = {
      settings = { ["rust-analyzer"] = { check = { command = "clippy" }, diagnostics = { enable = true } } },
      capabilities = { workspace = { fileOperations = { didRename = true, willRename = true } } },
    },
  },
  formatters = { "rustfmt" },
  linters = { clippy = { covered_by = "rust_analyzer" } },
}
