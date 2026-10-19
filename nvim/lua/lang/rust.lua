local NXO = { "n", "x", "o" }

---@type lang.Spec
return {
  filetypes = { "rust" },
  servers = {
    rust_analyzer = {
      settings = { ["rust-analyzer"] = { check = { command = "clippy" }, diagnostics = { enable = true } } },
      capabilities = { workspace = { fileOperations = { didRename = true, willRename = true } } },
    },
  },
  formatters = { "rustfmt" },
  linters = { clippy = { covered_by = "rust_analyzer" } },
  -- Labels for the runtime ftplugin's motions, which it maps without a desc, so the popup would show their rhs
  keys = {
    { "]]", label = "Next top-level item", mode = NXO },
    { "[[", label = "Previous top-level item", mode = NXO },
    filetypes = { "rust" },
  },
}
