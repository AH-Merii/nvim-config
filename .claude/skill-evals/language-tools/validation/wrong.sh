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
e1 docs-missing           docs/languages.md is regenerated with a Zig row
e1 docs-stale             docs/languages.md is regenerated with a Zig row
e1 unformatted-lua        changed Lua passes stylua --check
e2 bare-spec              a catalog entry provides linter selene with a spec mise knows
e2 custom-selene          lua buffers lint with nvim-lint's built-in selene
e2 selene-on-yaml         lua buffers lint with nvim-lint's built-in selene
e2 covered-by-lua_ls      live: selene reports unused_variable
e2 docs-missing           docs/languages.md is regenerated with selene
e3 jactionlint-all-yaml   jactionlint runs on the Dependabot file but not on plain YAML
e3 linters-as-list        .github/dependabot.yml gets a yaml sub-filetype linted by jactionlint and still by yamllint
e3 contributing-missing   docs/languages.md is regenerated with the Dependabot sub-filetype
e3 no-regression-check    a regression check expects the Dependabot sub-filetype
LIST
  exit 0
fi
# No variant drops yamlls from the Dependabot file: a variant gets its base's servers whatever it declares
# (nvim/lua/lang/init.lua), so check 3 of e3 has no one-edit wrong implementation in lang/.
id=$1 variant=$2
cd "$3"
# new files count too: intent-to-add puts their content in git diff (the clone is throwaway)
snap() { git add -A -N && git diff | md5sum; }
before=$(snap)
case "$id/$variant" in
  e1/custom-zig_fmt)
    sed -i 's/zig = { spec = "zig", formatters = { "zigfmt" } }/zig = { spec = "zig", formatters = { "zig_fmt" } }/' nvim/lua/tools/catalog.lua
    sed -i 's/  formatters = { "zigfmt" },/  formatters = { "zig_fmt" },/' nvim/lua/lang/zig.lua
    perl -0pi -e 's/(    formatters = \{\n)/$1      zig_fmt = { command = "zig", args = { "fmt", "--stdin" }, stdin = true },\n/' nvim/lua/format/conform.lua
    ;;
  e1/zls-not-enabled) sed -i '/^  servers = { zls = {} },$/d' nvim/lua/lang/zig.lua ;;
  e1/unknown-spec) sed -i 's/zls = { spec = "zls"/zls = { spec = "github:zigtools\/zlss"/' nvim/lua/tools/catalog.lua ;;
  e1/no-regression-check)
    rm tests/regress/checks/format_zigfmt.lua tests/regress/fixtures/default/main.zig
    git checkout -q -- tests/regress/checks/lsp_attach.lua
    ;;
  e1/docs-missing) git checkout -q -- docs ;;
  # the decisions doc is right, but docs/languages.md was not regenerated
  e1/docs-stale) git checkout -q -- docs/languages.md ;;
  e1/unformatted-lua) sed -i 's/zls = { spec = "zls", servers = { zls = {} } },/zls = {spec="zls", servers = { zls = {} } },/' nvim/lua/tools/catalog.lua ;;
  e2/bare-spec) sed -i 's/selene = { spec = "aqua:Kampfkarren\/selene"/selene = { spec = "selene"/' nvim/lua/tools/catalog.lua ;;
  e2/custom-selene)
    perl -0pi -e 's/(    -- Auto-lint on save and text changes\n)/    lint.linters.selene = { cmd = "selene", stdin = true, args = { "--display-style", "json", "-" }, ignore_exitcode = true, parser = require("lint.linters.selene").parser }\n\n$1/' nvim/lua/linting/nvim_lint.lua
    ;;
  e2/selene-on-yaml) sed -i 's/^  linters = { yamllint = {} },$/  linters = { yamllint = {}, selene = {} },/' nvim/lua/lang/yaml.lua ;;
  e2/covered-by-lua_ls) sed -i 's/^  linters = { selene = {} },$/  linters = { selene = { covered_by = "lua_ls" } },/' nvim/lua/lang/lua.lua ;;
  e2/docs-missing) git checkout -q -- docs ;;
  e3/jactionlint-all-yaml) sed -i 's/^  linters = { yamllint = {} },$/  linters = { yamllint = {}, jactionlint = {} },/' nvim/lua/lang/yaml.lua ;;
  # a variant's linters are a map of name -> options, not a list of names like its formatters
  e3/linters-as-list) sed -i 's/^      linters = { jactionlint = {} },$/      linters = { "jactionlint" },/' nvim/lua/lang/yaml.lua ;;
  e3/contributing-missing) git checkout -q -- CONTRIBUTING.md ;;
  e3/no-regression-check)
    rm tests/regress/checks/lint_dependabot.lua
    git checkout -q -- tests/regress/checks/tools_subfiletypes.lua
    ;;
  *) echo "unknown variant $id/$variant" >&2; exit 2 ;;
esac
# the bug must have changed something
[ "$(snap)" != "$before" ] || { echo "wrong.sh: $id/$variant changed nothing; its edit no longer matches" >&2; exit 1; }
# keep each variant to its one bug: formatting stays clean except in the variant about formatting
if [ "$variant" != unformatted-lua ]; then
  git diff --name-only -- 'nvim/*.lua' | xargs -r tests/regress/data/mise/data/installs/stylua/latest/stylua
fi
