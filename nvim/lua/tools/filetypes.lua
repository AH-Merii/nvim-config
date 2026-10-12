-- Dotted sub-filetypes for files that need extra tools, so a tool runs and is offered only where it applies.
-- Treesitter uses the first part and nvim-lint and conform fall back to the parts; servers match exactly,
-- so a server that should still attach lists the dotted name in after/lsp/.

local M = {}

M.filetypes = {
  ["yaml.github-actions"] = "GitHub workflows: jactionlint, zizmor",
  ["toml.pyproject"] = "pyproject.toml: pyproject-fmt",
}

function M.setup()
  vim.filetype.add({
    filename = {
      ["pyproject.toml"] = "toml.pyproject",
    },
    pattern = {
      [".*/%.github/workflows/[^/]*%.ya?ml"] = "yaml.github-actions",
    },
  })
end

return M
