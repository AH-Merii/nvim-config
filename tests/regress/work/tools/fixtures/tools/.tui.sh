# Sourced by the install_*.sh checks: a real TUI in a private tmux, state read over --listen RPC.
# Data: the suite's seed data without Mason, so every tool installs for real. State persists across
# launches within one check. Everything started here is reaped on exit.
SOCK=./nvim-$V-$$.sock TMS=nvr-tools-$V-$$ SESSION=tools
TM="tmux -L $TMS"
NVR_DATA_SEED=${NVR_DATA_SEED:-$NVR_DATA} DATA=$FIX/.data
export NVR_STATE=$FIX/.state NVR_DATA=$DATA
mkdir -p "$NVR_STATE"
if [ ! -d "$DATA/nvim/lazy" ]; then cp -a --reflink=auto "$NVR_DATA_SEED" "$DATA"; rm -rf "$DATA/nvim/mason"; fi

pass() { echo "PASS $1" >> "$CHECK_OUT"; }
fail() { echo "FAIL $1 -- $2" >> "$CHECK_OUT"; }
check() { if eval "$2"; then pass "$1"; else fail "$1" "${3:-condition false}"; fi; }
screen() { $TM capture-pane -p -t "$SESSION" 2>/dev/null; }
wait_screen() { local end=$((SECONDS + $2)); while [ $SECONDS -lt $end ]; do screen | grep -qE -- "$1" && return 0; sleep 0.3; done; return 1; }
state() { timeout 10 "$NV" "$V" --clean --headless --server "$SOCK" --remote-expr 'luaeval("NVR_TOOLS_STATE()")' 2>/dev/null; }
q() { state | jq -r "$1" 2>/dev/null; }
wait_q() { local end=$((SECONDS + $2)); while [ $SECONDS -lt $end ]; do [ "$(q "$1")" = true ] && return 0; sleep 0.5; done; return 1; }
send() { timeout 10 "$NV" "$V" --clean --headless --server "$SOCK" --remote-send "$1" 2>/dev/null; }
answer() { $TM send-keys -t "$SESSION" -l "$1"; sleep 0.3; $TM send-keys -t "$SESSION" Enter; }
cancel() { $TM send-keys -t "$SESSION" Escape; sleep 0.3; $TM send-keys -t "$SESSION" Escape; }
nothing_for() { local p; for p in "$@"; do [ "$(q "(.installed + .installing) | index(\"$p\") != null")" = false ] || return 1; done; }
attached() { wait_q "[.bufs[] | select(.name == \"$1\") | .clients[]] | index(\"$2\") != null" "$3"; }
info() { echo "INFO $1" >> "$CHECK_OUT"; }
hq() { timeout 10 "$NV" "$V" --clean --headless --server "$SOCK" --remote-expr 'luaeval("NVR_TOOLS_HOST()")' 2>/dev/null; }
# offered <ft>: the packages the open prompt for ft offers, one per line
offered() { screen | grep -oE "Install [^?]+ for ${1//./\\.}\?" | head -1 | sed -E 's/^Install (.*) for [^ ]+\?$/\1/; s/, /\n/g'; }
# all_installed <secs> <pkg...>
all_installed() {
  local secs=$1; shift
  wait_q "($(printf '%s\n' "$@" | jq -R . | jq -sc .) - .installed) | length == 0" "$secs"
}
# complete <file> <secs>: nothing installing, every server Mason installed for the file's filetype attached, and every
# formatter and linter whose command a Mason package provides installed and on PATH (NVR_TOOLS_HOST in .state.lua)
complete() {
  local end=$((SECONDS + $2))
  while [ $SECONDS -lt $end ]; do
    [ "$(hq | jq -r --arg f "$1" '(.installing | length) == 0 and ([.bufs[] | select(.name == $f) | (.missing | length) + (.tools_bad | length)] == [0])')" = true ] && return 0
    sleep 1
  done
  return 1
}
# incomplete <file>: why complete failed
incomplete() { hq | jq -r --arg f "$1" '"installing: \([.installing[]] | join(",")); " + ([.bufs[] | select(.name == $f) | "missing servers: \([.missing[]] | join(",")); lacking tools: \([.tools_bad[]] | join(", "))"] | join(""))'; }
# pkgs: how many packages Mason has installed, on disk
pkgs() { find "$DATA/nvim/mason/packages" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l; }
reap() {
  pkill -TERM -f -- "--listen $SOCK" 2>/dev/null; pkill -TERM -f -- "$DATA/" 2>/dev/null; sleep 1
  pkill -KILL -f -- "--listen $SOCK" 2>/dev/null; pkill -KILL -f -- "$DATA/" 2>/dev/null
  $TM kill-server 2>/dev/null; rm -f "$SOCK"
}
trap 'reap; echo DONE >> "$CHECK_OUT"' EXIT
trap 'exit 130' INT TERM HUP
# start [env assignments...] -- [nvim args...]
start() {
  reap
  local envs=() a
  while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
  [ "$1" = -- ] && shift
  local cmd="cd $(printf %q "$FIX") && env ${envs[*]} $(printf %q "$NV") $V --listen $SOCK --cmd 'luafile .state.lua'"
  for a in "$@"; do cmd+=" $(printf %q "$a")"; done
  $TM -f /dev/null new-session -d -s "$SESSION" -x 200 -y 50 "$cmd; sleep 1"
  local end=$((SECONDS + 30)); until [ -S "$SOCK" ] || [ $SECONDS -ge $end ]; do sleep 0.2; done
  [ -S "$SOCK" ] || fail "nvim started" "no socket after 30s: $(screen | tr -s ' ' | tail -3)"
}
stop() { send '<C-\><C-n>:qa!<CR>'; sleep 1; reap; }
prompt_re='Install .* for [a-z.-]+\?'
