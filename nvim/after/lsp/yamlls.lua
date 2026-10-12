return {
  -- nvim-lspconfig's list plus GitHub workflows (tools.filetypes); servers match the filetype exactly
  filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values", "yaml.github-actions" },
  settings = {
    yaml = {
      format = {
        enable = false,
      },
    },
  },
}
