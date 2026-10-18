#!/usr/bin/env bash
# usage: ref-e3.sh <clone dir>: the reference solution for e3 (jactionlint on .github/dependabot.yml only)
set -euo pipefail
cd "$1"
perl -0pi -e 's/(    -- In nvim-lspconfig.s yamlls list)/    ["yaml.dependabot"] = {\n      about = "Dependabot config: jactionlint",\n      match = { pattern = { [".*\/%.github\/dependabot%.ya?ml"] = {} } },\n      example = ".github\/dependabot.yml",\n      linters = { jactionlint = {} },\n    },\n$1/' nvim/lua/lang/yaml.lua
sed -i 's|  { ".github/dependabot.yml", "yaml" },|  { ".github/dependabot.yml", "yaml.dependabot" },\n  { ".github/dependabot.yaml", "yaml.dependabot" },\n  { "dependabot.yml", "yaml" },\n  { ".github/other.yml", "yaml" },|' tests/regress/checks/tools_subfiletypes.lua
cat > tests/regress/checks/lint_dependabot.lua <<'LUA'
-- @desc     .github/dependabot.yml is yaml.dependabot and gets jactionlint findings; plain YAML with the same text gets none
-- @areas    lint tools
-- @budget   20
-- @needs    jactionlint
local ns = require("lint").get_namespace("jactionlint")
local bad = { "version: 2", "updates:", '  - package-ecosystem: "npmm"', '    directory: "/"', "    schedule:", '      interval: "weekly"' }
vim.fn.mkdir(".github", "p")
vim.fn.writefile(bad, ".github/dependabot.yml")
vim.fn.writefile(bad, "plain.yml")
vim.cmd.edit(".github/dependabot.yml")
local buf = vim.api.nvim_get_current_buf()
check("dependabot.yml is yaml.dependabot", vim.bo[buf].filetype == "yaml.dependabot", vim.bo[buf].filetype)
wait_diagnostics(buf, function() return #vim.diagnostic.get(buf, { namespace = ns }) > 0 end, 10000)
local codes = vim.tbl_map(function(d) return d.code end, vim.diagnostic.get(buf, { namespace = ns }))
check("jactionlint reports dependabot-syntax", vim.list_contains(codes, "dependabot-syntax"), vim.inspect(codes))
vim.cmd.edit("plain.yml")
local pbuf = vim.api.nvim_get_current_buf()
wait_until(function() return #vim.diagnostic.get(pbuf, { namespace = ns }) > 0 end, 3000)
check("plain YAML gets no jactionlint findings", #vim.diagnostic.get(pbuf, { namespace = ns }) == 0, vim.bo[pbuf].filetype)
LUA
D=docs/mise-tooling-decisions.md
"${NVIM:-nvim}" --clean --headless -l docs/languages.lua >/dev/null
perl -0pi -e 's/(Decided since:\n\n)/$1- **jactionlint on Dependabot config** (2026-10-12). `.github\/dependabot.yml` is `yaml.dependabot`; jactionlint checks\n  Dependabot files (`jactionlint --help`), and reported `dependabot-syntax` on a bad sample with the current args.\n/' $D
sed -i 's/Workflow YAML is `yaml.github-actions`, `pyproject.toml` is `toml.pyproject`/Workflow YAML is `yaml.github-actions`, `.github\/dependabot.yml` is `yaml.dependabot`, `pyproject.toml` is `toml.pyproject`/' CONTRIBUTING.md
