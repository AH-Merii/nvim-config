---@type lang.Spec
return {
  filetypes = { "yaml" },
  servers = { yamlls = { settings = { yaml = { format = { enable = false } } } } },
  formatters = { "prettierd" },
  linters = { yamllint = {} },
  variants = {
    ["yaml.github-actions"] = {
      about = "GitHub workflows: jactionlint, zizmor",
      -- Ahead of the Compose names (lang/docker.lua), so a workflow named compose.yml is still a workflow. GitHub
      -- reads only the top level of .github/workflows
      match = { pattern = { [".*/%.github/workflows/[^/]*%.ya?ml"] = { priority = 1 } } },
      example = ".github/workflows/compose.yml",
      linters = { jactionlint = {}, zizmor = {} },
    },
    -- In nvim-lspconfig's yamlls list; nothing in Neovim or this config sets them
    ["yaml.gitlab"] = { about = "GitLab CI files, from nvim-lspconfig's yamlls filetypes" },
    ["yaml.helm-values"] = { about = "Helm values files, from nvim-lspconfig's yamlls filetypes" },
  },
}
