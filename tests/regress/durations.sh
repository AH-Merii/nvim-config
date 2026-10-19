#!/usr/bin/env bash
# usage: durations.sh <results.tsv...>
# Rewrites durations.tsv, which suite.sh --shard balances by, from the results.tsv of suite runs: each check's time
# is its median over the files that ran it. Use CI's times, not a local run's: download the shards' results of a few
# green runs of main with `gh run download <run-id> -n regress-results -D <dir>`, then pass every results.tsv.
# A check in no file is dropped, and counts as 1s until the next refresh.
set -euo pipefail
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ $# -gt 0 ] || { sed -n '2,6p' "$0" >&2; exit 2; }
for f in "$@"; do [ -s "$f" ] || { echo "no results in $f" >&2; exit 2; }; done
runs=$#
body=$(awk -F'\t' '$3 == "PASS" || $3 == "FAIL" { print $2 "\t" $4 }' "$@" | LC_ALL=C sort -t$'\t' -k1,1 -k2,2g |
  awk -F'\t' '
    function flush() { if (n) printf "%s\t%.1f\n", k, (n % 2 ? v[(n + 1) / 2] : (v[n / 2] + v[n / 2 + 1]) / 2) }
    $1 != k { flush(); k = $1; n = 0 }
    { v[++n] = $2 }
    END { flush() }')
{
  printf '# name<TAB>seconds: each check'"'"'s time in CI, the median over %s results.tsv (durations.sh, %s). suite.sh\n' "$runs" "$(date +%F)"
  printf '# --shard balances shards by it; a check missing here counts as 1s. Stale times only unbalance the shards: a\n'
  printf '# shard never drops a check (shard-cover.sh).\n'
  echo "$body"
} >"$S/durations.tsv.new"
mv "$S/durations.tsv.new" "$S/durations.tsv"
echo "durations.tsv: $(echo "$body" | grep -c .) checks, $(echo "$body" | awk -F'\t' '{ s += $2 } END { printf "%.1f", s }')s in all"
