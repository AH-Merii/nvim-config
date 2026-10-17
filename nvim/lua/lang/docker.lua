---@type lang.Spec
return {
  filetypes = { "dockerfile" },
  servers = { docker_language_server = {} },
  linters = { hadolint = {} },
  variants = {
    ["yaml.docker-compose"] = {
      about = "Compose files: docker-language-server",
      -- Compose's file names and their override variants, compose.override.yaml, compose.prod.yaml
      -- (https://docs.docker.com/compose/intro/compose-application-model/#the-compose-file,
      -- https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/)
      match = {
        pattern = { ["compose%.ya?ml"] = {}, ["compose%..+%.ya?ml"] = {}, ["docker%-compose%.ya?ml"] = {}, ["docker%-compose%..+%.ya?ml"] = {} },
      },
      example = "compose.override.yaml",
      servers = { "docker_language_server" },
    },
    ["hcl.docker-bake"] = {
      about = "Bake files: docker-language-server",
      -- Bake's own file names (https://docs.docker.com/build/bake/reference/#file-format)
      match = { filename = { "docker-bake.hcl", "docker-bake.override.hcl" } },
      example = "docker-bake.hcl",
      servers = { "docker_language_server" },
    },
  },
}
