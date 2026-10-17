#!/usr/bin/env bash
# usage: check.sh <repo root> [FT="<filetypes to show>"] [FILES="<paths to classify>"]
# The language-tools done check, cheap (one headless Neovim, a few seconds; it does not run the suite):
#   - tool-audit.lua: the wiring is consistent, no definition duplicates a plugin's built-in, sub-filetypes (the
#     languages' variants) keep their base's servers and linters;
#   - each binary and sub-filetype the change added (against the base commit) is in the decisions doc (and CONTRIBUTING.md
#     for a sub-filetype) and in a regression check; a MISSING line prints the row to add;
#   - the changed Lua under nvim/ is formatted (the suite's stylua).
# Prints "CHECK OK", or one MISSING line per gap and "CHECK FAILED". BASE=<git ref> overrides the base commit
# (default: the merge-base with the branch's upstream).
set -uo pipefail
R=${1:-}
[ -d "$R/nvim" ] && [ -x "$R/tests/regress/nv.sh" ] || { sed -n '2,10p' "$0" >&2; exit 2; }
R=$(cd "$R" && pwd)
SK=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
W=$(mktemp -d "$R/tests/regress/run/check.XXXXXX" 2>/dev/null || { mkdir -p "$R/tests/regress/run" && mktemp -d "$R/tests/regress/run/check.XXXXXX"; })
trap 'rm -rf "$W"' EXIT
miss=0
missing() { echo "MISSING $*"; miss=$((miss + 1)); }
ok() { echo "ok      $*"; }

base=${BASE:-$(git -C "$R" merge-base HEAD '@{upstream}' 2>/dev/null || git -C "$R" rev-parse HEAD)}
git -C "$R" show "$base:nvim/lua/tools/catalog.lua" >"$W/base_catalog.lua" 2>/dev/null || : >"$W/base_catalog.lua"
mkdir -p "$W/base"; git -C "$R" archive "$base" nvim/lua/lang 2>/dev/null | tar -x -C "$W/base" 2>/dev/null
echo "base: $(git -C "$R" log -1 --format='%h %s' "$base" 2>/dev/null)"

# One headless Neovim, capped when systemd-run is there: other sessions share this machine's memory
cap=()
systemd-run --user --scope -q -p MemoryMax=2G true 2>/dev/null && cap=(systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=512M --)
audit=$(cd "$W" && env -u CFG BASE_CATALOG="$W/base_catalog.lua" BASE_LANG="$W/base/nvim/lua/lang" FT="${FT:-}" FILES="${FILES:-}" \
  timeout 90 "${cap[@]}" "$R/tests/regress/nv.sh" nightly --headless -c "luafile $SK/tool-audit.lua" 2>&1)
grep -E '^(file |ft )' <<<"$audit"
if grep -q '^AUDIT OK' <<<"$audit"; then ok "tool-audit.lua: AUDIT OK"
else
  grep -E '^FAIL' <<<"$audit" | sed 's/^FAIL /MISSING /'
  grep -qE '^FAIL' <<<"$audit" || { tail -n 5 <<<"$audit"; missing "tool-audit.lua did not finish (output above)"; }
  miss=$((miss + $(grep -cE '^FAIL' <<<"$audit")))
fi

D=$R/docs/mise-tooling-decisions.md
section() { awk -v h="## $1" 'index($0, h) == 1 { on=1; next } on && /^## / { exit } on' "$D"; }
decided=$(sed -n '/^Decided since:/,/^## /p' "$D")
needs() { grep -lE "^(--|#) @needs .*(^| )$1( |\$)" "$R"/tests/regress/checks/*.lua "$R"/tests/regress/checks/*.sh 2>/dev/null | xargs -r -n1 basename | paste -sd' '; }

while IFS=$'\t' read -r kind name spec roles fts; do
  case $kind in
  new)
    # role names: "server tombi, formatter tombi" -> tombi tombi
    rnames=$(sed 's/[a-z]* \([^,]*\)/\1/g; s/,//g' <<<"$roles")
    echo "new binary $name (spec ${spec:-none}; $roles; filetypes: ${fts:-none})"
    words="$name $rnames"
    hit() { for w in $words; do grep -qiF -- "$w" <<<"$1" && return 0; done; return 1; }
    if hit "$(section 'Per-language tools' | grep '^|')"; then ok "the Per-language tools table names $name"
    else
      missing "docs/mise-tooling-decisions.md \"Per-language tools\" table does not name $name. Edit the row of its language (filetypes: $fts), or add one; bold the new tool:"
      for ft in $fts; do
        sed -n "s/^ft $ft: servers={\(.*\)} formatters={\(.*\)} linters={\(.*\)} tools=.*/        | <language> | \1 | \2 | \3 |/p" <<<"$audit"
      done
    fi
    if [ -z "$spec" ]; then ok "$name has no spec (the system provides it)"
    elif v=$("$SK/iso-mise.sh" "$W/mise" mise latest "$spec" 2>&1 | grep -m1 -E "^v?[0-9]+\.[0-9]|ERROR") && [[ $v =~ ^v?[0-9]+\.[0-9] ]]; then ok "mise knows the spec $spec: mise latest printed $v"
    else missing "mise does not know the spec $spec of $name: mise latest printed: $v (references/choose-tool.md, \"Find the mise spec\")"; fi
    if section 'Install specs' | grep '^|' | grep -iF -- "$name" | grep -qF -- "$spec"; then ok "the Install specs table has $name with its spec $spec"
    else missing "docs/mise-tooling-decisions.md \"Install specs\" table has no row naming $name and its spec. Add: | $name | \`$spec\` (<registry or backend, and how you found it>) | yes |"; fi
    if hit "$decided"; then ok "a \"Decided since\" entry names $name"
    else missing "docs/mise-tooling-decisions.md \"Decided since:\" list does not name $name. Add a bullet at its top: - **<what changed>** ($(date +%F)). <why>. Evidence: <the mise query and run output>"; fi
    n=$(needs "$name")
    if [ -n "$n" ]; then ok "checks that need $name: $n"
    else missing "no check in tests/regress/checks/ lists $name in @needs, so the suite never installs or runs it (references/tests.md)"; fi
    ;;
  newft)
    echo "new sub-filetype $name ($spec; tools: $roles)"
    if section 'File-scoped tools' | grep '^|' | grep -qF -- "$name"; then ok "the File-scoped tools table names $name"
    else missing "docs/mise-tooling-decisions.md \"File-scoped tools\" table has no row for $name. Add: | \`<files>\` | \`$name\` | <its own tools> (lint/format) |"; fi
    if grep -qF -- "$name" "$R/CONTRIBUTING.md"; then ok "CONTRIBUTING.md names $name"
    else missing "CONTRIBUTING.md does not name $name: add it to the sentence that lists the sub-filetypes (grep -n 'toml.pyproject' CONTRIBUTING.md)"; fi
    if grep -qF -- "${name#*.}" <<<"$decided"; then ok "a \"Decided since\" entry names ${name#*.}"
    else missing "docs/mise-tooling-decisions.md \"Decided since:\" list does not mention ${name#*.}. Add a bullet at its top with the files, the tools and the evidence"; fi
    others=$(grep -lF -- "$name" "$R"/tests/regress/checks/*.lua 2>/dev/null | grep -v '/tools_subfiletypes.lua$' | xargs -r -n1 basename | paste -sd' ')
    if [ -n "$others" ]; then ok "checks besides tools_subfiletypes name $name: $others"
    else missing "no check runs $name's own tools on a matching file (a lint or format check that opens one; references/tests.md, \"Sub-filetype\")"; fi
    if grep -qF "\"$name\"" "$R/tests/regress/checks/tools_subfiletypes.lua"; then ok "tools_subfiletypes.lua has cases for $name"
    else missing "tests/regress/checks/tools_subfiletypes.lua has no case expecting \"$name\": add matching paths and near misses, and fix any old case for the same file"; fi
    ;;
  removed)
    echo "removed binary $name"
    n=$(needs "$name")
    if [ -z "$n" ]; then ok "no check needs $name"; else missing "$name left the catalog, but these checks still list it in @needs: $n"; fi
    if grep -qF -- "~~$name" "$D"; then ok "the decisions doc strikes $name"; else missing "docs/mise-tooling-decisions.md does not strike $name (~~$name~~) in the Per-language tools table"; fi
    ;;
  esac
done < <(grep -E $'^(new|newft|removed)\t' <<<"$audit")

st=$R/tests/regress/data/mise/data/installs/stylua/latest/stylua
mapfile -t lua < <({ git -C "$R" diff --name-only "$base" -- 'nvim/*.lua'; git -C "$R" ls-files --others --exclude-standard -- 'nvim/*.lua'; } | sort -u | while read -r f; do [ -f "$R/$f" ] && echo "$f"; done)
if [ ${#lua[@]} = 0 ]; then ok "no Lua under nvim/ changed"
elif [ ! -x "$st" ]; then missing "the suite's stylua is not installed (tests/regress/suite.sh --refresh installs it)"
elif (cd "$R" && "$st" --check "${lua[@]}" >/dev/null 2>&1); then ok "stylua --check passes on ${lua[*]}"
else missing "stylua --check fails; run: (cd $R && $st ${lua[*]})"; fi

echo
if [ $miss = 0 ]; then echo "CHECK OK"; else echo "CHECK FAILED: $miss missing"; exit 1; fi
