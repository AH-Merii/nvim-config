#!/usr/bin/env bash
# usage: wrong.sh <eval id> <variant> <clone dir>
# Sibling wrong implementations: each starts from the reference solution (ref-<id>.sh, already applied to the clone)
# and adds exactly one plausible bug. `wrong.sh list` prints "<id> <variant> <check that must FAIL>" lines.
set -euo pipefail
if [ "${1:-}" = list ]; then
  cat <<'LIST'
e1 custom-zig_fmt         zig buffers format with conform's built-in zigfmt
e1 zls-not-enabled        zls is enabled with an nvim-lspconfig config
e1 unknown-spec           a catalog entry provides server zls with a spec mise knows
e1 no-regression-check    regression checks needing zls and the zig formatter
e1 docs-missing           the decisions doc has a Zig per-language row
e1 unformatted-lua        changed Lua passes stylua --check
e2 bare-spec              a catalog entry provides linter selene with a spec mise knows
e2 custom-selene          lua buffers lint with nvim-lint's built-in selene
e2 selene-on-yaml         lua buffers lint with nvim-lint's built-in selene
e2 covered-by-lua_ls      live: selene reports unused_variable
e2 docs-missing           the decisions doc names selene
e3 jactionlint-all-yaml   jactionlint runs on the Dependabot file but not on plain YAML
e3 yamlls-row-missing     yamlls still serves the Dependabot sub-filetype
e3 full-dotted-key        .github/dependabot.yml gets a yaml sub-filetype linted by jactionlint and still by yamllint
e3 readme-missing         the decisions doc's File-scoped tools table and decision list, and the README
e3 no-regression-check    a regression check expects the Dependabot sub-filetype
LIST
  exit 0
fi
id=$1 variant=$2
cd "$3"
case "$id/$variant" in
  e1/custom-zig_fmt)
    sed -i 's/zig = { spec = "zig", formatters = { "zigfmt" } }/zig = { spec = "zig", formatters = { "zig_fmt" } }/' nvim/lua/tools/catalog.lua
    sed -i 's/      zig = { "zigfmt" },/      zig = { "zig_fmt" },/' nvim/lua/plugins/conform.lua
    perl -0pi -e 's/(    formatters = \{\n)/$1      zig_fmt = { command = "zig", args = { "fmt", "--stdin" }, stdin = true },\n/' nvim/lua/plugins/conform.lua
    ;;
  e1/zls-not-enabled) sed -i '/^  "zls",$/d' nvim/lua/core/lsp_servers.lua ;;
  e1/unknown-spec) sed -i 's/zls = { spec = "zls"/zls = { spec = "github:zigtools\/zlss"/' nvim/lua/tools/catalog.lua ;;
  e1/no-regression-check)
    rm tests/regress/checks/format_zigfmt.lua tests/regress/fixtures/default/main.zig
    git checkout -q -- tests/regress/checks/lsp_attach.lua
    ;;
  e1/docs-missing) git checkout -q -- docs ;;
  e1/unformatted-lua) sed -i 's/zls = { spec = "zls", servers = { zls = {} } },/zls = {spec="zls", servers = { zls = {} } },/' nvim/lua/tools/catalog.lua ;;
  e2/bare-spec) sed -i 's/selene = { spec = "aqua:Kampfkarren\/selene"/selene = { spec = "selene"/' nvim/lua/tools/catalog.lua ;;
  e2/custom-selene)
    perl -0pi -e 's/(    -- Auto-lint on save and text changes\n)/    lint.linters.selene = { cmd = "selene", stdin = true, args = { "--display-style", "json", "-" }, ignore_exitcode = true, parser = require("lint.linters.selene").parser }\n\n$1/' nvim/lua/plugins/nvim-lint.lua
    ;;
  e2/selene-on-yaml) sed -i 's/      yaml = { "yamllint" },/      yaml = { "yamllint", "selene" },/' nvim/lua/plugins/nvim-lint.lua ;;
  e2/covered-by-lua_ls) sed -i 's/local covering_server = { ruff = "ruff",/local covering_server = { selene = "lua_ls", ruff = "ruff",/' nvim/lua/plugins/nvim-lint.lua ;;
  e2/docs-missing) git checkout -q -- docs ;;
  e3/jactionlint-all-yaml) sed -i 's/      yaml = { "yamllint" },/      yaml = { "yamllint", "jactionlint" },/' nvim/lua/plugins/nvim-lint.lua ;;
  e3/yamlls-row-missing) git checkout -q -- nvim/after/lsp/yamlls.lua ;;
  e3/full-dotted-key) sed -i 's/      dependabot = { "jactionlint" },/      ["yaml.dependabot"] = { "jactionlint" },/' nvim/lua/plugins/nvim-lint.lua ;;
  e3/readme-missing) git checkout -q -- README.md ;;
  e3/no-regression-check)
    rm tests/regress/checks/lint_dependabot.lua
    git checkout -q -- tests/regress/checks/tools_subfiletypes.lua
    ;;
  *) echo "unknown variant $id/$variant" >&2; exit 2 ;;
esac
# the bug must have changed something
[ -n "$(git status --porcelain)" ]
# keep each variant to its one bug: formatting stays clean except in the variant about formatting
if [ "$variant" != unformatted-lua ]; then
  git diff --name-only -- 'nvim/*.lua' | xargs -r tests/regress/data/mise/data/installs/stylua/latest/stylua
fi
