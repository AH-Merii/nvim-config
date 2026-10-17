---@type lang.Spec
return {
  filetypes = { "toml" },
  servers = { tombi = {} },
  formatters = { "tombi" },
  linters = { tombi = { covered_by = "tombi" } },
  variants = {
    ["toml.pyproject"] = {
      about = "pyproject.toml: pyproject-fmt formats it instead of tombi",
      match = { filename = { "pyproject.toml" } },
      example = "sub/pyproject.toml",
      formatters = { "pyproject-fmt" },
    },
  },
}
