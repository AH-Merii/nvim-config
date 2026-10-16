-- @desc     Compose and Bake files, by Docker's file names, are yaml.docker-compose and hcl.docker-bake and get the servers that accept those (docker_language_server, plus yamlls on Compose) and their base's treesitter highlighting; other yaml and hcl files stay yaml and hcl
-- @areas    tools lsp treesitter
-- @budget   40
-- @needs    docker-language-server yaml-language-server

-- Docker's file names: https://docs.docker.com/compose/intro/compose-application-model/#the-compose-file,
-- https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/ (compose.override.yaml, compose.prod.yaml)
-- and https://docs.docker.com/build/bake/reference/#file-format
local cases = {
  { "compose.yaml", "yaml.docker-compose" },
  { "compose.yml", "yaml.docker-compose" },
  { "docker-compose.yaml", "yaml.docker-compose" },
  { "docker-compose.yml", "yaml.docker-compose" },
  { "compose.override.yaml", "yaml.docker-compose" },
  { "compose.prod.yml", "yaml.docker-compose" },
  { "docker-compose.override.yml", "yaml.docker-compose" },
  { "docker-compose.dev.yaml", "yaml.docker-compose" },
  { "deploy/compose.yaml", "yaml.docker-compose" },
  { "docker-bake.hcl", "hcl.docker-bake" },
  { "docker-bake.override.hcl", "hcl.docker-bake" },
  { "infra/docker-bake.hcl", "hcl.docker-bake" },
  { "config.yml", "yaml" },
  { "composer.yaml", "yaml" },
  { "my-compose.yaml", "yaml" },
  { "other.hcl", "hcl" },
  { ".github/workflows/compose.yml", "yaml.github-actions" }, -- GitHub runs it as a workflow whatever its name
}
for _, c in ipairs(cases) do
  local ft = vim.filetype.match({ filename = FIX .. "/" .. c[1] })
  check(c[1] .. " is " .. c[2], ft == c[2], tostring(ft))
end

local function open(path, lines)
  vim.fn.mkdir(vim.fs.dirname(vim.fs.joinpath(FIX, path)), "p")
  vim.fn.writefile(lines, path)
  vim.cmd.edit(path)
  return vim.api.nvim_get_current_buf()
end

local files = {
  { "compose.yaml", { "services:", "  web:", "    image: nginx:1.27" }, { "docker_language_server", "yamlls" }, "yaml" },
  { "docker-bake.hcl", { 'target "default" {', '  dockerfile = "Dockerfile"', "}" }, { "docker_language_server" }, "hcl" },
  { "config.yml", { "key: value" }, { "yamlls" }, "yaml" },
}
for _, f in ipairs(files) do
  local buf = open(f[1], f[2])
  local missing, why = wait_attach(buf, f[3], 20000)
  check(("%s (%s) gets %s"):format(f[1], vim.bo[buf].filetype, table.concat(f[3], " and ")), #missing == 0, table.concat(why, "; "))
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  check(f[1] .. " is highlighted with the " .. f[4] .. " parser",
    ok and parser ~= nil and parser:lang() == f[4] and vim.treesitter.highlighter.active[buf] ~= nil,
    ok and parser and parser:lang() or tostring(parser))
end
local plain = vim.fn.bufnr("config.yml")
check("config.yml does not get docker_language_server", #vim.lsp.get_clients({ bufnr = plain, name = "docker_language_server" }) == 0)
