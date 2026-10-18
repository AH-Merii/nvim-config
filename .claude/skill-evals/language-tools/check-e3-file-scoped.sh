#!/usr/bin/env bash
# usage: check-e3-file-scoped.sh <clone dir>
# Eval e3: "Lint GitHub Dependabot config (.github/dependabot.yml) with jactionlint, only on that file."
# The jactionlint --profile choice for Dependabot files is the user's to make, so nothing here depends on it: the
# live sample gets a finding under the current args (--profile correctness).
# Outcome checks, one PASS/FAIL line each, then the gate on the user's real mise.
set -uo pipefail
C=${1:-} ID=e3
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

P=$(probe .github/dependabot.yml config.yml .github/other.yml .github/workflows/ci.yml)
if ! grep -q '^PROBE DONE' <<<"$P"; then
  result 0 "the clone's config loads headless" "$(tail -n 5 <<<"$P")"
fi
dep=$(grep -P '^file\t\.github/dependabot\.yml\t' <<<"$P")
plain=$(grep -P '^file\tconfig\.yml\t' <<<"$P")
other=$(grep -P '^file\t\.github/other\.yml\t' <<<"$P")
wf=$(grep -P '^file\t\.github/workflows/ci\.yml\t' <<<"$P")
ft=$(field "$dep" ft)

# 1. the Dependabot file gets a yaml sub-filetype with jactionlint plus yaml's own linters and formatter
ok=0
[[ $ft == yaml.* ]] && has "$(field "$dep" linters)" jactionlint && has "$(field "$dep" linters)" yamllint &&
  has "$(field "$dep" formatters)" prettierd && ok=1
result $ok ".github/dependabot.yml gets a yaml sub-filetype linted by jactionlint and still by yamllint" \
  "ft=$ft linters=$(field "$dep" linters) formatters=$(field "$dep" formatters)"

# 2. only there: plain YAML and other .github files stay yaml without jactionlint; workflows keep theirs
ok=0
[ "$(field "$plain" ft)" = yaml ] && ! has "$(field "$plain" linters)" jactionlint &&
  [ "$(field "$other" ft)" = yaml ] && ! has "$(field "$other" linters)" jactionlint &&
  [ "$(field "$wf" ft)" = yaml.github-actions ] && has "$(field "$wf" linters)" jactionlint && has "$(field "$wf" linters)" zizmor &&
  has "$(field "$dep" linters)" jactionlint && ok=1
result $ok "jactionlint runs on the Dependabot file but not on plain YAML or other .github files; workflows keep jactionlint and zizmor" \
  "dependabot linters=$(field "$dep" linters); config.yml ft=$(field "$plain" ft) linters=$(field "$plain" linters); .github/other.yml ft=$(field "$other" ft) linters=$(field "$other" linters); workflow ft=$(field "$wf" ft) linters=$(field "$wf" linters)"

# 3. yamlls is still planned for the Dependabot file (its filetypes list the sub-filetype)
ok=0
[[ $ft == yaml.* ]] && has "$(field "$dep" servers)" yamlls && ok=1
result $ok "yamlls still serves the Dependabot sub-filetype" "ft=$ft servers=$(field "$dep" servers); yamlls filetypes=$(grep -P '^lspft\tyamlls\t' <<<"$P" | cut -f3)"

# 4. live: jactionlint reports on .github/dependabot.yml, yamlls attaches there, plain YAML gets nothing from jactionlint
L=$(live "$EV/live/e3/eval_dependabot.lua")
st=$(suite_status "$L" eval_dependabot)
[ "$st" = PASS ]
result $((! $?)) "live: jactionlint reports dependabot-syntax on a bad .github/dependabot.yml, yamlls attaches there, and config.yml with the same text gets no jactionlint finding" \
  "suite --work eval-e3: eval_dependabot $st $(suite_reasons "$L" eval_dependabot | paste -sd' ')"

# 5. a regression check expects the new filetype for the Dependabot file, and it passes with the sub-filetype checks
cks=""
[[ $ft == yaml.* ]] && cks=$(grep -lF "$ft" "$C"/tests/regress/checks/*.lua 2>/dev/null | xargs -r grep -l 'dependabot' | xargs -r -n1 basename | sed 's/\.lua$//')
if [ -z "$cks" ]; then
  result 0 "a regression check expects the Dependabot sub-filetype, and it passes with tools_subfiletypes, lint_jactionlint and startup" \
    "no check in tests/regress/checks names both dependabot and the sub-filetype (ft=$ft)"
else
  names=$(printf '%s\n' startup tools_subfiletypes lint_jactionlint $cks | sort -u | paste -sd'|')
  S=$(suite "^($names)\$")
  fails=$(awk '$1 == "FAIL" && $2 == "nightly" { print $3 }' <<<"$S" | paste -sd' ')
  ok=0
  # shellcheck disable=SC2046
  suite_ok "$S" $(tr '|' ' ' <<<"$names") && ok=1
  result $ok "a regression check expects the Dependabot sub-filetype, and it passes with tools_subfiletypes, lint_jactionlint and startup" \
    "checks naming $ft and dependabot: $(paste -sd' ' <<<"$cks"); suite '^($names)\$': $(grep -E '^SUITE (PASS|FAIL)' <<<"$S")${fails:+; failed: $fails $(suite_reasons "$S" "${fails%% *}" | paste -sd' ')}"
fi

# 6. docs: docs/languages.md is regenerated with the Dependabot variant; the decision list and CONTRIBUTING.md name it
D=$C/docs/mise-tooling-decisions.md
U=$(languages_doc)
row=$([ -n "$ft" ] && grep -F "| \`$ft\` |" "$C/docs/languages.md")
decided=$(sed -n '/^Decided since:/,/^## /p' "$D")
contributing=$(grep -n -i 'dependabot' "$C/CONTRIBUTING.md" | head -2)
ok=0
[[ $ft == yaml.* ]] && grep -q '^UNIT PASS' <<<"$U" && grep -qF '`jactionlint`' <<<"$row" && grep -qi dependabot <<<"$decided" &&
  grep -qF "$ft" "$C/CONTRIBUTING.md" && ok=1
result $ok "docs/languages.md is regenerated with the Dependabot sub-filetype, and the decision list and CONTRIBUTING.md name it" \
  "languages_doc: $(grep -E '^(PASS|FAIL|UNIT)' <<<"$U" | paste -sd' '); variant row: ${row:-none}; decided-since mentions: $(grep -ci dependabot <<<"$decided"); CONTRIBUTING.md lines naming ${ft}: $(grep -cF "$ft" "$C/CONTRIBUTING.md") (${contributing:-no dependabot line})"

# 7. formatting
check_stylua

gate
