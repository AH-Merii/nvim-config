#!/usr/bin/env bash
# usage: tests/unit/run.sh [-v] [name-regex]
# Runs every tests/unit/*_test.lua, each in its own `nvim --clean --headless -l` from the repo root, with throwaway
# XDG and temp dirs. Prints PASS/FAIL per file with its time, and a failing file's output; exits non-zero on any
# failure. -v prints every file's output. $NVIM picks the binary (default: the regress suite's nightly, else nvim).
set -u
U=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$U/../.." && pwd)
NIGHTLY=$HOME/.local/share/mise/installs/neovim/nightly/bin/nvim
if [ -z "${NVIM:-}" ]; then [ -x "$NIGHTLY" ] && NVIM=$NIGHTLY || NVIM=nvim; fi
# nothing reaches the user's clipboard: wl-copy/xclip need a display, the tmux provider the user's tmux
unset WAYLAND_DISPLAY DISPLAY TMUX

VERBOSE=0 FILTER=
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) FILTER=$1 ;;
  esac
  shift
done

TMP=$(mktemp -d "${TMPDIR:-/tmp}/nvim-unit.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

ran=0 failed=0
shopt -s nullglob
for f in "$U"/*_test.lua; do
  name=$(basename "$f" .lua)
  [ -n "$FILTER" ] && ! [[ $name =~ $FILTER ]] && continue
  home=$TMP/$name
  mkdir -p "$home"/{config,data,state,cache,tmp}
  start=$(date +%s%N)
  out=$(cd "$ROOT" && XDG_CONFIG_HOME=$home/config XDG_DATA_HOME=$home/data XDG_STATE_HOME=$home/state \
    XDG_CACHE_HOME=$home/cache TMPDIR=$home/tmp timeout 60 "$NVIM" --clean --headless -l "tests/unit/$name.lua" 2>&1)
  code=$?
  ms=$(( ($(date +%s%N) - start) / 1000000 ))
  ran=$((ran + 1))
  if [ $code = 0 ]; then
    printf 'PASS %-28s %6d ms\n' "$name" "$ms"
    [ $VERBOSE = 1 ] && [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/  /'
  else
    failed=$((failed + 1))
    printf 'FAIL %-28s %6d ms  (exit %d)\n' "$name" "$ms" "$code"
    printf '%s\n' "${out:-(no output)}" | sed 's/^/  /'
  fi
done
if [ $ran = 0 ]; then echo "no unit tests selected" >&2; exit 2; fi
if [ $failed = 0 ]; then echo "UNIT PASS ($ran files)"; else echo "UNIT FAIL ($failed of $ran files)"; exit 1; fi
