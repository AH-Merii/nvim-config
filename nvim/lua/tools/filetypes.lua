-- Dotted sub-filetypes for files that need extra tools, so a tool runs and is offered only where it applies.
-- Treesitter uses the first part and nvim-lint and conform fall back to the parts; servers match exactly,
-- so a server that should still attach lists the dotted name in after/lsp/.

local M = {}

M.filetypes = {
  ["yaml.github-actions"] = "GitHub workflows: jactionlint, zizmor",
  ["toml.pyproject"] = "pyproject.toml: pyproject-fmt",
  ["yaml.docker-compose"] = "Compose files: docker-language-server",
  ["hcl.docker-bake"] = "Bake files: docker-language-server",
}

function M.setup()
  vim.filetype.add({
    filename = {
      ["pyproject.toml"] = "toml.pyproject",
      -- Bake's own file names (https://docs.docker.com/build/bake/reference/#file-format)
      ["docker-bake.hcl"] = "hcl.docker-bake",
      ["docker-bake.override.hcl"] = "hcl.docker-bake",
    },
    pattern = {
      -- Ahead of the Compose names, so a workflow named compose.yml is still a workflow
      [".*/%.github/workflows/[^/]*%.ya?ml"] = { "yaml.github-actions", { priority = 1 } },
      -- Compose's file names and their override variants, compose.override.yaml, compose.prod.yaml
      -- (https://docs.docker.com/compose/intro/compose-application-model/#the-compose-file,
      -- https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/)
      ["compose%.ya?ml"] = "yaml.docker-compose",
      ["compose%..+%.ya?ml"] = "yaml.docker-compose",
      ["docker%-compose%.ya?ml"] = "yaml.docker-compose",
      ["docker%-compose%..+%.ya?ml"] = "yaml.docker-compose",
    },
  })
end

return M
