#!/usr/bin/env bash
# usage: shard-cover.sh <n> [suite.sh selection args]           check that n shards split the selection exactly
#        shard-cover.sh --results <n> <results.tsv...> [-- args]  check that n shards' results.tsv ran it exactly
# The first form asks suite.sh --list for the whole selection and for each --shard i/n; the second compares the
# selection with the checks that n shard runs recorded (suite.sh writes last/results.tsv), so a shard that crashed
# or skipped checks fails it. Prints each shard's checks and estimated time; exits 1 on a missing or doubled check.
set -u
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mode=list
if [ "${1:-}" = --results ]; then mode=results; shift; fi
n=${1:-}; [[ $n =~ ^[1-9][0-9]*$ ]] || { sed -n '2,3p' "$0" >&2; exit 2; }
shift
files=()
if [ $mode = results ]; then
  while [ $# -gt 0 ] && [ "$1" != -- ]; do files+=("$1"); shift; done
  [ "${1:-}" = -- ] && shift
  [ ${#files[@]} = "$n" ] || { echo "want $n results files, got ${#files[@]}" >&2; exit 2; }
fi
names() { awk '{ sub(/\.(lua|sh)$/, "", $2); print $1 ":" $2 }'; }
all=$("$S/suite.sh" --list "$@" | names | sort) || exit 2
got=
for i in $(seq "$n"); do
  if [ $mode = list ]; then
    mine=$("$S/suite.sh" --list --shard "$i/$n" "$@" | grep -v '^shard ' | names)
  else
    mine=$(awk -F'\t' '{ print $1 ":" $2 }' "${files[$((i - 1))]}")
  fi
  est=$(for c in $mine; do awk -F'\t' -v k="${c#*:}" '$1 == k { print $2; f = 1 } END { if (!f) print 1 }' "$S/durations.tsv"; done |
    awk '{ s += $1 } END { printf "%.1f", s }')
  echo "shard $i/$n: $(echo "$mine" | grep -c .) checks, ~${est}s by durations.tsv"
  got+="$mine"$'\n'
done
got=$(echo "$got" | grep . | sort)
missing=$(comm -23 <(echo "$all") <(echo "$got" | sort -u))
doubled=$(echo "$got" | uniq -d)
extra=$(comm -13 <(echo "$all") <(echo "$got" | sort -u))
rc=0
[ -n "$missing" ] && { echo "MISSING from every shard: $(echo $missing)"; rc=1; }
[ -n "$doubled" ] && { echo "IN MORE THAN ONE SHARD: $(echo $doubled)"; rc=1; }
[ -n "$extra" ] && { echo "NOT IN THE SELECTION: $(echo $extra)"; rc=1; }
[ $rc = 0 ] && echo "COVER PASS: $(echo "$all" | grep -c .) checks, each in exactly one of $n shards" || echo "COVER FAIL"
exit $rc
