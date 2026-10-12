#!/usr/bin/env bash
# usage: check-e1-new-language.sh <clone dir>
# Eval e1: "Add Zig support: zls as the language server and zig fmt as the formatter."
# Outcome checks, one PASS/FAIL line each, then the gate on the user's real mise.
set -uo pipefail
C=${1:-} ID=e1
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

P=$(probe main.zig init.lua)
if ! grep -q '^PROBE DONE' <<<"$P"; then
  result 0 "the clone's config loads headless" "$(tail -n 5 <<<"$P")"
fi
zig=$(grep -P '^file\tmain.zig\t' <<<"$P")
lua=$(grep -P '^file\tinit.lua\t' <<<"$P")
zls_bin=$(awk -F'\t' '$1 == "catalog" && ("," substr($4, 9) ",") ~ /,zls,/ { print $2 }' <<<"$P" | head -1)
zls_spec=$(grep -P "^catalog\t$zls_bin\t" <<<"$P" | cut -f3 | sed 's/^spec=//')

# 1. zls resolves through the catalog with a spec mise knows
if [ -z "$zls_bin" ]; then
  result 0 "a catalog entry provides server zls with a spec mise knows" "no catalog entry has servers.zls"
elif [ -z "$zls_spec" ]; then
  result 0 "a catalog entry provides server zls with a spec mise knows" "catalog $zls_bin has no spec"
else
  v=$(iso_mise latest "$zls_spec" 2>&1 | grep -m1 -E '^v?[0-9]+\.[0-9]|ERROR')
  [[ $v =~ ^[0-9]+\.[0-9] ]]
  result $((! $?)) "a catalog entry provides server zls with a spec mise knows" "catalog $zls_bin spec=$zls_spec; mise latest $zls_spec -> $v"
fi

# 2. zls is enabled under its nvim-lspconfig name, and a Zig buffer gets it while a Lua buffer does not
en=$(grep -P '^enabled\tzls\t' <<<"$P")
ok=0
[ "$(field "$en" lspconfig)" = yes ] && has "$(field "$zig" servers)" zls && ! has "$(field "$lua" servers)" zls && ok=1
result $ok "zls is enabled with an nvim-lspconfig config and planned for zig buffers only" "${en:-zls not in M.servers}; main.zig ft=$(field "$zig" ft) servers=$(field "$zig" servers); init.lua servers=$(field "$lua" servers)"

# 3. the zig formatter is conform's built-in zigfmt (zig fmt), with no duplicate custom definition, and only on zig
fmts=$(field "$zig" formatters)
bad_defs=$(awk -F'\t' '$1 == "fmtdef" && $3 == "builtin=no" { print $2 " (" $4 ", same command as built-in " substr($5, 5) ")" }' <<<"$P" | paste -sd';')
# the catalog binary of the zig buffer's first formatter (zig, for conform's zigfmt)
first_fmt=${fmts%%,*}
fmt_bin=$([ -n "$first_fmt" ] && awk -F'\t' -v f="$first_fmt" '$1 == "catalog" && ("," substr($5, 12) ",") ~ ("," f ",") { print $2 }' <<<"$P" | head -1)
fmt_spec=$(grep -P "^catalog\t$fmt_bin\t" <<<"$P" | cut -f3 | sed 's/^spec=//')
ok=0
if has "$fmts" zigfmt && [ "$first_fmt" = zigfmt ] && [ -z "$(awk -F'\t' '$1 == "fmtdef" && $3 == "builtin=no" && $5 != "dup=" { print }' <<<"$P")" ] &&
  ! has "$(field "$lua" formatters)" zigfmt && [ -n "$fmt_spec" ]; then
  v=$(iso_mise latest "$fmt_spec" 2>&1 | grep -m1 -E '^v?[0-9]+\.[0-9]|ERROR')
  [[ $v =~ ^[0-9]+\.[0-9] ]] && ok=1
fi
result $ok "zig buffers format with conform's built-in zigfmt, cataloged with a spec mise knows, and no custom formatter duplicates a built-in" \
  "main.zig formatters=$fmts; init.lua formatters=$(field "$lua" formatters); catalog ${fmt_bin:-none} spec=${fmt_spec:-none} (mise latest: ${v:-not queried}); custom duplicates: ${bad_defs:-none}"

# 4. live: with the cataloged specs installed in the clone's suite mise, zls attaches and conform formats with zig fmt
specs=()
[ -n "$zls_spec" ] && specs+=("$zls_spec")
[ -n "${fmt_spec:-}" ] && [ "$fmt_spec" != "$zls_spec" ] && specs+=("$fmt_spec")
inst=$([ ${#specs[@]} -gt 0 ] && suite_install "${specs[@]}")
L=$(live "$EV/live/e1/eval_zig.lua")
st=$(suite_status "$L" eval_zig)
[ "$st" = PASS ]
result $((! $?)) "live: zls attaches to a Zig buffer and conform reformats it through zig fmt" \
  "suite --work eval-e1: eval_zig $st $(suite_reasons "$L" eval_zig | paste -sd' '); install: $(tail -n1 <<<"$inst")"

# 5. the change carries regression checks that need zls and the formatter binary, and they pass with startup
needs_zls=$(grep -lE "^-- @needs .*(^| )${zls_bin:-@none@}( |$)" "$C"/tests/regress/checks/*.lua 2>/dev/null | xargs -r -n1 basename | sed 's/\.lua$//')
needs_fmt=$(grep -lE "^-- @needs .*(^| )${fmt_bin:-@none@}( |$)" "$C"/tests/regress/checks/*.lua 2>/dev/null | xargs -r -n1 basename | sed 's/\.lua$//')
names=$(printf '%s\n' startup $needs_zls $needs_fmt | sort -u | paste -sd'|')
if [ -z "$needs_zls" ] || [ -z "$needs_fmt" ]; then
  result 0 "regression checks needing zls and the zig formatter exist and pass with startup" "checks needing ${zls_bin:-zls}: ${needs_zls:-none}; needing ${fmt_bin:-zig}: ${needs_fmt:-none}"
else
  S=$(suite "^($names)\$")
  fails=$(awk '$1 == "FAIL" && $2 == "nightly" { print $3 }' <<<"$S" | paste -sd' ')
  ok=0
  # shellcheck disable=SC2046
  suite_ok "$S" $(tr '|' ' ' <<<"$names") && ok=1
  result $ok "regression checks needing zls and the zig formatter exist and pass with startup" \
    "suite '^($names)\$': $(awk '$2 == "nightly" { printf "%s %s; ", $3, $1 }' <<<"$S")$(grep -E '^SUITE (PASS|FAIL)' <<<"$S")${fails:+; failed: $fails $(suite_reasons "$S" "${fails%% *}" | paste -sd' ')}"
fi

# 6. the decisions doc records Zig: a per-language row, install-spec rows and a decision entry
D=$C/docs/mise-tooling-decisions.md
row=$(section "$D" "Per-language tools" | grep -iE '^\|[^|]*zig[^|]*\|')
specs_txt=$(section "$D" "Install specs")
decided=$(sed -n '/^Decided since:/,/^## /p' "$D")
ok=0
if [[ -n $row ]] && grep -q 'zls' <<<"$row" && grep -qiE 'zig ?fmt' <<<"$row" &&
  grep -F 'zls' <<<"$specs_txt" | grep -qF "${zls_spec:-@none@}" && grep -iE '(^|[^a-z_])zig([^a-z_]|$)' <<<"$specs_txt" | grep -qF "${fmt_spec:-@none@}" &&
  grep -qiE 'zls|zig' <<<"$decided"; then ok=1; fi
result $ok "the decisions doc has a Zig per-language row, install-spec rows with the catalog specs, and a decision entry" \
  "row: ${row:-none}; install-spec lines: $(grep -iE 'zls|zig' <<<"$specs_txt" | paste -sd' ' | cut -c1-160); decided-since mentions: $(grep -ciE 'zls|zig' <<<"$decided")"

# 7. formatting
check_stylua

gate
