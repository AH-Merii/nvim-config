#!/usr/bin/env bash
# usage: check-e2-existing-language.sh <clone dir>
# Eval e2: "Add selene as a linter for Lua."
# Outcome checks, one PASS/FAIL line each, then the gate on the user's real mise.
set -uo pipefail
C=${1:-} ID=e2
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

P=$(probe init.lua config.yml app.py)
if ! grep -q '^PROBE DONE' <<<"$P"; then
  result 0 "the clone's config loads headless" "$(tail -n 5 <<<"$P")"
fi
lua=$(grep -P '^file\tinit.lua\t' <<<"$P")
yml=$(grep -P '^file\tconfig.yml\t' <<<"$P")
py=$(grep -P '^file\tapp.py\t' <<<"$P")
bin=$(awk -F'\t' '$1 == "catalog" && ("," substr($6, 9) ",") ~ /,selene,/ { print $2 }' <<<"$P" | head -1)
spec=$(grep -P "^catalog\t${bin:-@none@}\t" <<<"$P" | cut -f3 | sed 's/^spec=//')

# 1. selene resolves through the catalog with a spec mise knows
if [ -z "$bin" ] || [ -z "$spec" ]; then
  result 0 "a catalog entry provides linter selene with a spec mise knows" "catalog entry: ${bin:-none}, spec: ${spec:-none}"
else
  v=$(iso_mise latest "$spec" 2>&1 | grep -m1 -E '^v?[0-9]+\.[0-9]|ERROR')
  [[ $v =~ ^[0-9]+\.[0-9] ]]
  result $((! $?)) "a catalog entry provides linter selene with a spec mise knows" "catalog $bin spec=$spec; mise latest $spec -> $v"
fi

# 2. Lua buffers get nvim-lint's built-in selene, keep lua_ls and stylua; other filetypes don't get selene
def=$(grep -P '^linterdef\tselene\t' <<<"$P")
dups=$(awk -F'\t' '$1 == "linterdef" && $3 == "custom=yes" && ($4 == "builtin=yes" || $6 != "dup=") { print $2 " (" $5 ")" }' <<<"$P" | paste -sd';')
ok=0
has "$(field "$lua" linters)" selene && [ "$(field "$def" custom)" = no ] && [ "$(field "$def" builtin)" = yes ] && [ -z "$dups" ] &&
  has "$(field "$lua" servers)" lua_ls && has "$(field "$lua" formatters)" stylua &&
  ! has "$(field "$yml" linters)" selene && ! has "$(field "$py" linters)" selene && ok=1
result $ok "lua buffers lint with nvim-lint's built-in selene (no custom or duplicate definition), keep lua_ls and stylua, and other filetypes don't get selene" \
  "init.lua servers=$(field "$lua" servers) formatters=$(field "$lua" formatters) linters=$(field "$lua" linters); ${def:-no selene definition}; custom linters overriding or duplicating a built-in: ${dups:-none}; config.yml linters=$(field "$yml" linters); app.py linters=$(field "$py" linters)"

# 3. live: with the cataloged spec installed in the clone's suite mise, selene reports on a Lua buffer
inst=$([ -n "$spec" ] && suite_install "$spec")
L=$(live "$EV/live/e2/eval_selene.lua")
st=$(suite_status "$L" eval_selene)
[ "$st" = PASS ]
result $((! $?)) "live: selene reports unused_variable on a Lua buffer while lua_ls is attached, and nothing on a sh buffer" \
  "suite --work eval-e2: eval_selene $st $(suite_reasons "$L" eval_selene | paste -sd' '); install: $(tail -n1 <<<"$inst")"

# 4. the change carries a regression check that needs selene, and it passes with startup
needs=$(grep -lE "^-- @needs .*(^| )${bin:-@none@}( |$)" "$C"/tests/regress/checks/*.lua 2>/dev/null | xargs -r -n1 basename | sed 's/\.lua$//')
if [ -z "$needs" ]; then
  result 0 "a regression check needing selene exists and passes with startup" "no check in tests/regress/checks lists ${bin:-selene} in @needs"
else
  names=$(printf '%s\n' startup $needs | sort -u | paste -sd'|')
  S=$(suite "^($names)\$")
  fails=$(awk '$1 == "FAIL" && $2 == "nightly" { print $3 }' <<<"$S" | paste -sd' ')
  ok=0
  # shellcheck disable=SC2046
  suite_ok "$S" $(tr '|' ' ' <<<"$names") && ok=1
  result $ok "a regression check needing selene exists and passes with startup" \
    "suite '^($names)\$': $(awk '$2 == "nightly" { printf "%s %s; ", $3, $1 }' <<<"$S")$(grep -E '^SUITE (PASS|FAIL)' <<<"$S")${fails:+; failed: $fails $(suite_reasons "$S" "${fails%% *}" | paste -sd' ')}"
fi

# 5. docs: docs/languages.md is regenerated with selene in the Lua row; an install-spec row with the spec, a decision entry
D=$C/docs/mise-tooling-decisions.md
U=$(languages_doc)
row=$(languages_row '`lua`')
specrow=$(section "$D" "Install specs" | grep -F selene)
decided=$(sed -n '/^Decided since:/,/^## /p' "$D")
ok=0
grep -q '^UNIT PASS' <<<"$U" && grep -qF '`selene`' <<<"$row" && grep -qF "${spec:-@none@}" <<<"$specrow" && grep -q selene <<<"$decided" && ok=1
result $ok "docs/languages.md is regenerated with selene in the Lua row, and the decisions doc has an install-spec row with its spec and a decision entry" \
  "languages_doc: $(grep -E '^(PASS|FAIL|UNIT)' <<<"$U" | paste -sd' '); Lua row: ${row:-none}; install-spec row: ${specrow:-none}; decided-since mentions: $(grep -c selene <<<"$decided")"

# 6. formatting
check_stylua

gate
