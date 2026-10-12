#!/usr/bin/env bash
# usage: validate.sh [untouched|reference|wrong] [eval id]
# Validates the check scripts on seeded clones under ~/.cache/skill-eval/fix-*:
#   untouched  every check FAILs on a clone with no change (the gate line is the only guard)
#   reference  every check PASSes on the reference solution (ref-<id>.sh)
#   wrong      each sibling wrong implementation (wrong.sh list) turns its matching check FAIL
# Runs one clone at a time and deletes each clone after its check.
set -uo pipefail
V=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
EV=$(dirname "$V")
export TMPDIR=$HOME/.cache/skill-eval/tmp
mkdir -p "$TMPDIR"
mode=${1:-all} only=${2:-}
script() { ls "$EV"/check-"$1"-*.sh; }
ids=(e1 e2 e3)
[ -n "$only" ] && ids=("$only")

if [ "$mode" = untouched ] || [ "$mode" = all ]; then
  c=$HOME/.cache/skill-eval/fix-untouched
  "$EV/seed.sh" "$c" 0 >/dev/null
  for id in "${ids[@]}"; do
    out=$("$(script "$id")" "$c")
    echo "$out"
    n=$(grep -c '^PASS ' <<<"$out")
    echo "== untouched $id: $(grep -c '^FAIL ' <<<"$out") FAIL, $n PASS -> $([ "$n" = 0 ] && echo OK || echo BAD)"
  done
  rm -rf "$c"
fi

if [ "$mode" = reference ] || [ "$mode" = all ]; then
  for id in "${ids[@]}"; do
    c=$HOME/.cache/skill-eval/fix-ref-$id
    "$EV/seed.sh" "$c" 0 >/dev/null && "$V/ref-$id.sh" "$c"
    out=$("$(script "$id")" "$c")
    echo "$out"
    n=$(grep -c '^FAIL ' <<<"$out")
    echo "== reference $id: $(grep -c '^PASS ' <<<"$out") PASS, $n FAIL -> $([ "$n" = 0 ] && grep -q '^GATE env OK' <<<"$out" && echo OK || echo BAD)"
    rm -rf "$c"
  done
fi

if [ "$mode" = wrong ] || [ "$mode" = all ]; then
  "$V/wrong.sh" list | while read -r id variant expect; do
    [ -n "$only" ] && [ "$id" != "$only" ] && continue
    c=$HOME/.cache/skill-eval/fix-wrong-$id-$variant
    "$EV/seed.sh" "$c" 0 >/dev/null && "$V/ref-$id.sh" "$c" && "$V/wrong.sh" "$id" "$variant" "$c" ||
      { echo "== wrong $id/$variant: could not build the variant -> BAD"; continue; }
    out=$("$(script "$id")" "$c")
    hit=$(grep "^FAIL $id " <<<"$out" | grep -F "$expect" | head -1)
    echo "== wrong $id/$variant: expected FAIL on \"$expect\" -> $([ -n "$hit" ] && echo OK || echo BAD)"
    echo "   ${hit:-$(grep -E '^(PASS|FAIL)' <<<"$out" | cut -c1-200 | paste -sd'|')}"
    echo "   also failing: $(grep '^FAIL ' <<<"$out" | grep -vF "$expect" | cut -d' ' -f3-9 | paste -sd';')"
    rm -rf "$c"
  done
fi
