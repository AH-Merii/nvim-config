#!/usr/bin/env bash
# usage: ref-e3.sh <clone dir>: the reference solution for e3 (jactionlint on .github/dependabot.yml only)
set -euo pipefail
cd "$1"
perl -0pi -e 's/(  \["toml.pyproject"\] = "pyproject.toml: pyproject-fmt",\n)/$1  ["yaml.dependabot"] = "Dependabot config: jactionlint",\n/' nvim/lua/tools/filetypes.lua
perl -0pi -e 's/(      \[".\*\/%.github\/workflows\/\[\^\/\]\*%.ya\?ml"\] = "yaml.github-actions",\n)/$1      [".*\/%.github\/dependabot%.ya?ml"] = "yaml.dependabot",\n/' nvim/lua/tools/filetypes.lua
perl -0pi -e 's/(      \["github-actions"\] = \{ "jactionlint", "zizmor" \},\n)/$1      -- .github\/dependabot.yml is yaml.dependabot\n      dependabot = { "jactionlint" },\n/' nvim/lua/plugins/nvim-lint.lua
sed -i 's/"yaml.github-actions" }/"yaml.github-actions", "yaml.dependabot" }/' nvim/after/lsp/yamlls.lua
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
perl -0pi -e 's/(\| `pyproject.toml` \| `toml.pyproject` \| pyproject-fmt \(format\) \|\n)/$1| `.github\/dependabot.y{a,}ml` | `yaml.dependabot` | jactionlint (lint) |\n/' $D
perl -0pi -e 's/(Decided since:\n\n)/$1- **jactionlint on Dependabot config** (2026-10-12). `.github\/dependabot.yml` is `yaml.dependabot`; jactionlint checks\n  Dependabot files (`jactionlint --help`), and reported `dependabot-syntax` on a bad sample with the current args.\n/' $D
sed -i 's/Workflow YAML is `yaml.github-actions` and `pyproject.toml` is `toml.pyproject` (`lua\/tools\/filetypes.lua`), so jactionlint, zizmor and pyproject-fmt are offered only there/Workflow YAML is `yaml.github-actions`, `.github\/dependabot.yml` is `yaml.dependabot` and `pyproject.toml` is `toml.pyproject` (`lua\/tools\/filetypes.lua`), so jactionlint, zizmor and pyproject-fmt are offered only there/' README.md
