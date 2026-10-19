#!/usr/bin/env bash
# usage: suite.sh [-v] [--refresh] [--refresh-only] [--refresh-dry-run] [--list] [--selftest] [--area a,b] [--changed <git-range>] [--work <feature>]
#                 [--shard <i>/<n>] [name-filter]
# See README.md.
set -u
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export S
# no check reaches the user's clipboard: wl-copy/xclip need a display, the tmux provider the user's tmux
unset WAYLAND_DISPLAY DISPLAY TMUX
# shellcheck source=lib.sh
. "$S/lib.sh"
export CFG

FILTER= AREAS= RANGE= WORK= SHARD= REFRESH=0 ONLY=0 DRY=0 LIST=0 SELFTEST=0 VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --refresh) REFRESH=1 ;;
    --refresh-only) REFRESH=1 ONLY=1 ;;
    --refresh-dry-run) REFRESH=1 DRY=1 ;;
    --list) LIST=1 ;;
    --selftest) SELFTEST=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    --area) AREAS=${2//,/ }; shift ;;
    --changed) RANGE=$2; shift ;;
    --work) WORK=$2; shift ;;
    --shard) SHARD=$2; shift ;;
    -h|--help) sed -n '2,4p' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) FILTER=$1 ;;
  esac
  shift
done
[ -f "$CFG/init.lua" ] || { echo "CFG=$CFG has no init.lua" >&2; exit 2; }

# ---- select checks -----------------------------------------------------------------------------
if [ $SELFTEST = 1 ]; then
  CDIR=$S/selftest
elif [ -n "$WORK" ]; then
  CDIR=$S/work/$WORK
  [ -d "$CDIR" ] || { echo "no work dir $CDIR" >&2; exit 2; }
else
  CDIR=$S/checks
fi
if [ -n "$RANGE" ]; then
  changed=$(git -c core.fsmonitor=false -C "$CFG" diff --name-only --relative "$RANGE" -- . 2>&1) ||
    { echo "git diff $RANGE failed: $changed" >&2; exit 2; }
  AREAS="startup smoke"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    hit=
    while read -r glob areas; do
      case "$glob" in ''|'#'*) continue ;; esac
      # shellcheck disable=SC2053
      if [[ $f == $glob ]]; then hit=1; AREAS="$AREAS $areas"; fi
    done <"$S/areas.map"
    [ -n "$hit" ] || { echo "unmapped change $f: running every area" >&2; AREAS=ALL; break; }
  done <<<"$changed"
  echo "changed since $RANGE: $(echo "$changed" | wc -w) files -> areas: $AREAS"
fi

# plan lines: <version> <file>
PLAN=()
shopt -s nullglob
for f in "$CDIR"/*.lua "$CDIR"/*.sh; do
  name=$(basename "$f"); name=${name%.*}
  [ -n "$FILTER" ] && ! [[ $name =~ $FILTER ]] && continue
  fareas=" $(header "$f" areas) "
  if [ -n "$AREAS" ] && [ "$AREAS" != ALL ]; then
    match=
    for a in $AREAS; do [[ $fareas == *" $a "* ]] && match=1; done
    [ -n "$match" ] || continue
  fi
  PLAN+=("nightly $f")
done
if [ ${#PLAN[@]} = 0 ]; then echo "no checks selected" >&2; exit 2; fi

# --shard i/n: keep the selected checks that shard i of n runs, in the plan's order. Longest first, each check goes to
# the shard with the least time so far (ties: the lower shard), by the times in durations.tsv; a check without a time
# counts as 1s. The n shards split the selection exactly: each selected check is in one shard (shard-cover.sh).
if [ -n "$SHARD" ]; then
  [[ $SHARD =~ ^([0-9]+)/([0-9]+)$ ]] && [ "${BASH_REMATCH[1]}" -ge 1 ] &&
    [ "${BASH_REMATCH[1]}" -le "${BASH_REMATCH[2]}" ] ||
    { echo "--shard wants <i>/<n> with 1 <= i <= n, got $SHARD" >&2; exit 2; }
  mine=" $(for p in "${PLAN[@]}"; do n=$(basename "${p#* }"); echo "${p%% *}:${n%.*}"; done |
    awk -v i="${BASH_REMATCH[1]}" -v n="${BASH_REMATCH[2]}" -F'\t' '
      FNR == NR { if ($0 !~ /^#/ && NF >= 2) t[$1] = $2; next }
      { k = $0; sub(/^[^:]*:/, "", k); printf "%s\t%s\n", $0, (k in t ? t[k] : 1) }' "$S/durations.tsv" - |
    LC_ALL=C sort -t$'\t' -k2,2gr -k1,1 |
    awk -v i="${BASH_REMATCH[1]}" -v n="${BASH_REMATCH[2]}" -F'\t' '
      { b = 1; for (s = 2; s <= n; s++) if (load[s] < load[b]) b = s; load[b] += $2; if (b == i) print $1 }' |
    tr '\n' ' ')"
  kept=()
  for p in "${PLAN[@]}"; do n=$(basename "${p#* }"); [[ $mine == *" ${p%% *}:${n%.*} "* ]] && kept+=("$p"); done
  PLAN=("${kept[@]}")
  # more shards than checks: this shard has nothing to run, which is not a failure
  if [ ${#PLAN[@]} = 0 ]; then echo "shard $SHARD: no checks"; exit 0; fi
fi
if [ $LIST = 1 ]; then
  for p in "${PLAN[@]}"; do
    f=${p#* }
    printf '%-8s %-28s %4ss  %s\n' "${p%% *}" "$(basename "$f")" "$(header "$f" budget)" "$(header "$f" areas)"
  done
  exit 0
fi

# ---- run setup ---------------------------------------------------------------------------------
RUNID=$(date +%Y%m%d-%H%M%S)-$$
RUNROOT=$RUNS/$RUNID
mkdir -p "$RUNROOT" "$S/last"
touch "$RUNROOT/stamp"
T0=$EPOCHREALTIME
cleanup() {
  local pids
  pids=$(tagged_pids "$RUNID/")
  # shellcheck disable=SC2086
  [ -n "$pids" ] && kill_pids KILL $pids
  rm -rf "$RUNROOT"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

base_inotify=$(inotify_holders | sort -u | tr '\n' ' ')
base_inotify_n=$(inotify_holders | wc -l)
base_fsmon=" $(pgrep -f 'fsmonitor--daemon' | tr '\n' ' ') "

if [ $REFRESH = 1 ]; then
  H=$RUNROOT/refresh; make_home "$H"
  data=$S/data log=$S/last/refresh.log
  if [ $DRY = 1 ]; then
    echo "refresh dry run: the tools every check needs and what is missing, for $S/data and $CFG, nothing changed"
    data=$H/data log=$S/last/refresh-dry-run.log
    mkdir -p "$data"; cp -a --reflink=auto "$S/data/nvim" "$data/nvim"
  else
    steps=${NVR_REFRESH_STEPS:-"plugins, tools (the suite's mise and rustup) and parsers"}
    echo "refresh: $steps in $S/data for $CFG"
  fi
  ( cd "$H" && exec env NVR_HOME="$H" NVR_DATA="$data" NVR_REFRESH_DRY=$DRY NVIM_REGRESS_TAG="$RUNID/refresh/" \
      timeout 1200 setsid "$S/nv.sh" nightly --headless -c "luafile $S/refresh.lua" ) >"$log" 2>&1
  rc=$?
  sed "s/\x1b\[[0-9;]*m//g" "$log" | grep -E "^(plugins|tools|parsers):|FAIL|REFRESH"
  pids=$(tagged_pids "$RUNID/refresh/")
  # shellcheck disable=SC2086
  [ -n "$pids" ] && { echo "refresh left: $(describe_pids $pids)"; kill_pids KILL $pids; }
  [ $DRY = 1 ] && exit $rc
  repoint_data
  [ $rc = 0 ] || { echo "refresh failed (exit $rc), see last/refresh.log" >&2; exit 1; }
  [ $ONLY = 1 ] && exit 0
fi

refs=$(foreign_refs)
if [ -n "$refs" ]; then
  echo "ABORT: files or symlinks in data/ reach outside the sandbox (run --refresh to repoint):" >&2
  echo "$refs" | head >&2
  exit 1
fi

# ---- one check ---------------------------------------------------------------------------------
# run_check <version> <file>: appends "<ver>\t<name>\t<PASS|FAIL>\t<secs>\t<budget>\t<areas>\t<reasons>" to results
run_check() {
  local v=$1 f=$2 name budget fixture args fdir fix st data out err tag pid t0 secs over=0 rc reasons=() pids leftover allow details=() d lpid lppid lage largs
  name=$(basename "$f"); name=${name%.*}
  budget=$(header "$f" budget)
  local areas; areas=$(header "$f" areas)
  out=$H/out-$name.txt; err=$H/err-$name.txt
  # per check, not per version dir: parallel runs of other checks keep their results
  rm -f "$S/last/$v/$name.out" "$S/last/$v/$name.err"
  : >"$out"
  if ! [[ $budget =~ ^[0-9]+$ ]]; then
    printf '%s\t%s\tFAIL\t0\t-\t%s\t%s\n' "$v" "$name" "$areas" "no @budget" >>"$H/results"
    return
  fi
  fixture=$(header "$f" fixture); fixture=${fixture:-default}
  fdir=$(dirname "$f")/fixtures/$fixture; [ -d "$fdir" ] || fdir=$S/fixtures/$fixture
  fix=$H/fix-$name; st=$H/state-$name
  rm -rf "$fix" "$st"; cp -a --reflink=auto "$fdir" "$fix"; mkdir -p "$st"
  # git cannot track a nested .git, so fixtures store it as dot-git
  [ -d "$fix/dot-git" ] && mv "$fix/dot-git" "$fix/.git"
  data=$H/data
  if has_header "$f" fresh; then data=$H/data-$name; rm -rf "$data"; mkdir -p "$data"; fi
  args=$(header "$f" args)
  tag="$RUNID/$v/$name/"
  local -a cmd
  if [[ $f == *.lua ]]; then
    # shellcheck disable=SC2206
    cmd=("$S/nv.sh" "$v" --headless -c "luafile $S/harness.lua" $args)
  else
    cmd=(bash "$f")
  fi
  t0=$EPOCHREALTIME
  ( cd "$fix" && exec env NVR_HOME="$H" NVR_STATE="$st" NVR_DATA="$data" NVR_VERSION="$v" \
      NVIM_REGRESS_TAG="$tag" CHECK="$f" CHECK_OUT="$out" NV="$S/nv.sh" V="$v" FIX="$fix" \
      setsid "${cmd[@]}" ) </dev/null >"$err" 2>&1 &
  pid=$!
  local stat deadline=$(( ${t0/./} + budget * 1000000 ))
  while :; do
    stat=
    { read -r _ _ stat _ <"/proc/$pid/stat"; } 2>/dev/null
    [ -z "$stat" ] || [ "$stat" = Z ] && break
    if [ "${EPOCHREALTIME/./}" -gt "$deadline" ]; then
      over=1
      kill -TERM -- "-$pid" 2>/dev/null
      read -rt 1 -u "$TICK"
      kill -KILL -- "-$pid" 2>/dev/null
      break
    fi
    read -rt 0.05 -u "$TICK"
  done
  wait "$pid"; rc=$?
  secs=$(awk -v a="$t0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.1f", b-a}')

  # leaks: tagged processes that outlive the check by 3s
  local i
  for i in $(seq 60); do
    pids=$(tagged_pids "$tag")
    [ -z "$pids" ] && break
    read -rt 0.05 -u "$TICK"
  done
  if [ -n "$pids" ]; then
    leftover=
    for p in $pids; do
      local comm; comm=$(cat "/proc/$p/comm" 2>/dev/null) || continue
      allow=
      while read -r re _; do [ -n "$re" ] && [[ $comm =~ ^($re)$ ]] && allow=1; done < <(header_all "$f" allow-leak)
      if [ -n "$allow" ]; then
        echo "allowed leak: $comm($p)" >>"$out"
      else
        leftover="$leftover $comm($p)"
        # who started it and when, kept in the output and in last/: the parent is often gone, its pid then names a reaper
        read -r lpid lppid lage largs < <(ps -o pid=,ppid=,etimes=,args= -p "$p") &&
          details+=("pid $lpid ppid $lppid age ${lage}s: $largs")
      fi
    done
    [ -n "$leftover" ] && reasons+=("leaked:$leftover")
    for d in "${details[@]}"; do
      reasons+=("$d")
      echo "LEAK $d" >>"$out"
    done
    kill -TERM -- "-$pid" 2>/dev/null
    # shellcheck disable=SC2086
    kill_pids TERM $pids
    read -rt 0.5 -u "$TICK"
    # shellcheck disable=SC2086
    kill_pids KILL $(tagged_pids "$tag")
  fi

  [ $over = 1 ] && reasons+=("over budget: killed at ${budget}s")
  if ! grep -q '^DONE' "$out"; then
    reasons+=("did not finish (exit $rc)$(tail -n 2 "$err" | tr '\n' ' ' | sed 's/^/: /;s/ *$//' | cut -c1-200)")
  fi
  grep -q '^PASS' "$out" || reasons+=("no PASS recorded")
  while IFS= read -r l; do reasons+=("$l"); done < <(grep -E '^(FAIL|MSG|NOTIFY) ' "$out" | cut -c1-400)
  while IFS= read -r l; do reasons+=("stderr: $l"); done < <(grep -aE 'E[0-9]+:|Error|stack traceback' "$err" | head -3 | cut -c1-300)

  local status=PASS
  [ ${#reasons[@]} -gt 0 ] && status=FAIL
  local joined; joined=$(printf '%s\x1f' "${reasons[@]}")
  if [ $SELFTEST = 1 ]; then
    local expect; expect=$(header "$f" expect-fail)
    if [ $status = FAIL ] && [[ $joined =~ $expect ]]; then status=PASS; reasons=("failed as expected: /$expect/")
    else status=FAIL; reasons=("expected a failure matching /$expect/, got: ${reasons[*]:-PASS}"); fi
    joined=$(printf '%s\x1f' "${reasons[@]}")
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$v" "$name" "$status" "$secs" "$budget" "$areas" "$joined" >>"$H/results"
  printf '%-4s %-7s %-28s %6ss / %ss\n' "$status" "$v" "$name" "$secs" "$budget"
  for r in "${reasons[@]}"; do printf '       %s\n' "$r"; done
  [ $VERBOSE = 1 ] && grep -vE '^(FAIL|MSG|NOTIFY|DONE)' "$out" | cut -c1-300 | sed 's/^/       /'
  if [ $status = FAIL ]; then cp "$out" "$S/last/$v/$name.out"; cp "$err" "$S/last/$v/$name.err"; fi
  rm -rf "$fix" "$st"
  has_header "$f" fresh && rm -rf "$data"
}

# header_all <file> <key>: every value of a repeatable header
header_all() { sed -n -E "s/^(--|#) @$2 +(.*)$/\2/p" "$1"; }

# run_version <version>: the version's checks, one after another
run_version() {
  local v=$1
  H=$RUNROOT/$v
  make_home "$H"
  # the seed's contents: cache-seed/ may be a symlink (a worktree's, to the main checkout's), which cp -a would copy as
  # one, so every run would write into the shared seed
  cp -a --reflink=auto "$S/cache-seed/." "$H/cache/"
  # each version gets its own reflink copy of the nvim data; the suite's mise and rustup are used in place
  mkdir -p "$H/data"; cp -a --reflink=auto "$S/data/nvim" "$H/data/nvim"
  mkdir -p "$S/last/$v"
  mkfifo "$H/tick"; exec {TICK}<>"$H/tick"
  : >"$H/results"
  local t; t=$EPOCHREALTIME
  for p in "${PLAN[@]}"; do
    [ "${p%% *}" = "$v" ] && run_check "$v" "${p#* }"
  done
  # shellcheck disable=SC2046
  kill_pids KILL $(tagged_pids "$RUNID/$v/")
  awk -v a="$t" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.1f", b-a}' >"$H/wall"
}

VERSIONS=$(for p in "${PLAN[@]}"; do echo "${p%% *}"; done | sort -u | tr '\n' ' ')
echo "run $RUNID: $(printf '%s\n' "${PLAN[@]}" | wc -l) check runs on $VERSIONS${SHARD:+(shard $SHARD) }(CFG=$CFG)"
for v in $VERSIONS; do run_version "$v" & done
wait

# ---- report ------------------------------------------------------------------------------------
fail=0
echo
echo "== results"
cat "$RUNROOT"/*/results 2>/dev/null >"$RUNROOT/all"
# every check's result line, for shard-cover.sh and for timing: replaced by each run
cp "$RUNROOT/all" "$S/last/results.tsv"
sort -t$'\t' -k2,2 "$RUNROOT/all" | awk -F'\t' 'BEGIN { printf "%-28s %s\n", "check", "result" } { printf "%-28s %s %6.1fs\n", $2, $3, $4 }'
grep -q $'\tFAIL\t' "$RUNROOT/all" && fail=1

echo
echo "== per-area time (sum of check times; a check counts in each of its areas)"
awk -F'\t' '{ n=split($6, a, " "); for (i=1;i<=n;i++) { t[a[i]]+=$4; c[a[i]]++ } }
  END { printf "%-12s %16s\n", "area", "time (checks)";
        n=asorti(t, s); for (i=1;i<=n;i++) printf "%-12s %10.1fs (%2d)\n", s[i], t[s[i]], c[s[i]] }' "$RUNROOT/all"

echo
echo "== wall time"
for v in $VERSIONS; do echo "$v: $(cat "$RUNROOT/$v/wall" 2>/dev/null)s"; done
echo "total: $(awk -v a="$T0" -v b="$EPOCHREALTIME" 'BEGIN{printf "%.1f", b-a}')s"

echo
echo "== hygiene"
changed=$(find "$HOME/.config/nvim/" "$HOME/.local/share/nvim/" "$HOME/.local/state/nvim/" "$HOME/.cache/nvim/" \
  -newer "$RUNROOT/stamp" 2>/dev/null | head -20)
if [ -n "$changed" ]; then
  fail=1; echo "FAIL live nvim dirs changed during the run:"; echo "$changed" | sed 's/^/       /'
  live=$(pgrep -a -x nvim | grep -v -F "$S" | cut -c1-120)
  [ -n "$live" ] && echo "       (nvim processes outside the sandbox were running: $(echo "$live" | wc -l))"
else echo "PASS live nvim dirs unchanged"; fi

# the suite's tools come from data/mise and data/rustup only; the user's mise config, installs and toolchains stay as they were
mise_changed=$(find "$HOME/.config/mise" "$HOME/.local/share/mise/installs" "$HOME/.rustup/toolchains" "$HOME/.rustup/settings.toml" \
  -maxdepth 2 -newer "$RUNROOT/stamp" 2>/dev/null | head -20)
if [ -n "$mise_changed" ]; then
  fail=1; echo "FAIL the user's mise or rustup changed during the run (an install outside the suite's own, or the user's):"
  echo "$mise_changed" | sed 's/^/       /'
else echo "PASS the user's mise config, mise installs and rustup toolchains unchanged"; fi

left=$(tagged_pids "$RUNID/")
# shellcheck disable=SC2086
if [ -n "$left" ]; then fail=1; echo "FAIL sandbox processes still alive: $(describe_pids $left)"; kill_pids KILL $left
else echo "PASS no sandbox process left"; fi

# any suite run's tag counts; a clipboard server whose environ has the live XDG dirs is the user's own
clip_bad=
for p in $(pgrep -x 'wl-copy|wl-paste|xclip|xsel'); do
  /usr/bin/grep -qz '^NVIM_REGRESS_TAG=' "/proc/$p/environ" 2>/dev/null || continue
  /usr/bin/grep -qzxF "XDG_CONFIG_HOME=$HOME/.config" "/proc/$p/environ" 2>/dev/null && continue
  clip_bad="$clip_bad $p"
done
# shellcheck disable=SC2086
if [ -n "$clip_bad" ]; then fail=1; echo "FAIL clipboard servers from the suite: $(describe_pids $clip_bad)"; kill_pids KILL $clip_bad
else echo "PASS no suite clipboard server (wl-copy, xclip, xsel) left"; fi

end_inotify_n=$(inotify_holders | wc -l)
new_holders=
for p in $(inotify_holders | sort -u); do [[ " $base_inotify " == *" $p "* ]] || new_holders="$new_holders $p"; done
sbx_holders=
for p in $new_holders; do grep -qaF "NVIM_REGRESS_TAG=$RUNID/" "/proc/$p/environ" 2>/dev/null && sbx_holders="$sbx_holders $p"; done
# shellcheck disable=SC2086
if [ -n "$sbx_holders" ]; then fail=1; echo "FAIL inotify held by sandbox processes: $(describe_pids $sbx_holders)"
elif [ "$end_inotify_n" -le "$base_inotify_n" ]; then echo "PASS inotify instances back to baseline ($base_inotify_n -> $end_inotify_n)"
else echo "PASS inotify: none held by the sandbox; $base_inotify_n -> $end_inotify_n from outside: $(describe_pids $new_holders)"; fi

fsm_bad=
for p in $(pgrep -f 'fsmonitor--daemon'); do
  [[ $base_fsmon == *" $p "* ]] && continue
  if grep -qaF "NVIM_REGRESS_TAG=$RUNID/" "/proc/$p/environ" 2>/dev/null || readlink "/proc/$p/cwd" | grep -qF "$S"; then fsm_bad="$fsm_bad $p"; fi
done
ipc=$(find "$S/data" "$S/fixtures" "$RUNROOT" -name 'fsmonitor--daemon.ipc' -newer "$RUNROOT/stamp" 2>/dev/null | head -3)
if [ -n "$fsm_bad$ipc" ]; then fail=1; echo "FAIL fsmonitor daemon from the sandbox:$fsm_bad $ipc"
else echo "PASS no fsmonitor daemon from the sandbox"; fi

echo
[ $fail = 0 ] && echo "SUITE PASS" || echo "SUITE FAIL"
exit $fail
