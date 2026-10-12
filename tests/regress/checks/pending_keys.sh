#!/usr/bin/env bash
# @desc     in the TUI the last line shows pending keys (count, operator, register) and never a mapping's internal key (~@<fd>), also after <Esc>
# @areas    ui keys which-key
# @budget   25
# @version-sensitive
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
pass() { out "PASS $1"; }
fail() { out "FAIL $1  -- $2"; }
finish() { out DONE; exit 0; }

# a private tmux server, killed on exit so no tagged process outlives the check
SOCK=$FIX/.tmux.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-pending-keys-$$.sock
T=(tmux -S "$SOCK" -f /dev/null)
cleanup() { "${T[@]}" kill-server >/dev/null 2>&1; rm -f "$SOCK"; }
trap cleanup EXIT
trap 'exit 143' TERM INT HUP
unset TMUX TMUX_PANE

now_ms() { echo $(($(date +%s%N) / 1000000)); }
# wait_for <ms> <command...>: poll the command every 50ms until it succeeds or the time is up
wait_for() {
  local deadline=$(($(now_ms) + $1))
  shift
  until "$@"; do
    [ "$(now_ms)" -ge "$deadline" ] && return 1
    sleep 0.05
  done
}
screen() { "${T[@]}" capture-pane -p -t nvr 2>/dev/null; }
last_row() { screen | tail -n 1; }
body() { screen | sed '$d'; }
send() { "${T[@]}" send-keys -t nvr "$@"; }
has_last() { [[ $(last_row) == *"$1"* ]]; }
junk() { [[ $(last_row) == *"~@"* ]]; }
body_differs() { [ "$(body)" != "$1" ]; }
body_is() { [ "$(body)" = "$1" ]; }
settled() {
  local a
  a=$(screen)
  sleep 0.15
  [ -n "$(last_row | tr -d ' ')" ] && [ "$(screen)" = "$a" ]
}
reset() {
  send Escape
  send Escape
  wait_for 3000 settled
}

# app.conf has no server or linter, so nothing redraws the screen on its own
READY=$FIX/.nvr-ready
LUA="vim.schedule(function() vim.fn.writefile({}, '$READY') end)"
printf 'exec %q %q -c %q app.conf\n' "$NV" "$V" "autocmd User VeryLazy ++once lua $LUA" >"$FIX/.nvr-launch.sh"
if ! "${T[@]}" new-session -d -s nvr -x 160 -y 40 -c "$FIX" "bash $(printf %q "$FIX/.nvr-launch.sh")" 2>/dev/null; then
  fail "nvim starts under tmux" "tmux new-session failed"
  finish
fi
if ! wait_for 20000 test -e "$READY"; then
  fail "nvim starts under tmux and runs VeryLazy" "no VeryLazy within 20s; last line: $(last_row)"
  finish
fi
wait_for 3000 settled

for c in "44|4 4" "2d|2 d" '"a|" a'; do
  want=${c%%|*} keys=${c#*|}
  reset
  if has_last "$want"; then
    fail "pending $want shows on the last line" "already there before typing: $(last_row)"
    continue
  fi
  # shellcheck disable=SC2086
  send $keys
  if wait_for 3000 has_last "$want"; then
    pass "pending $want shows on the last line"
  else
    fail "pending $want shows on the last line" "last line: $(last_row)"
  fi
done

# which-key's triggers are Lua mappings that stay open while the popup waits; 0.12 puts their key in %S
reset
b0=$(body)
send Space
if wait_for 3000 body_differs "$b0"; then
  pass "<leader> opens a key-hint window"
else
  fail "<leader> opens a key-hint window" "screen unchanged 3s after <leader>"
fi
if junk; then fail "<leader> pending: no mapping key on the last line" "$(last_row)"; else pass "<leader> pending: no mapping key on the last line"; fi

reset
b0=$(body)
if has_last 3; then
  fail "3<leader> pending: the count shows, the mapping key does not" "a 3 is on the last line before typing: $(last_row)"
else
  # typed apart, as a person types; nightly does not show a count that arrives in one read with <leader>
  send 3
  wait_for 3000 has_last 3
  send Space
  wait_for 3000 body_differs "$b0"
  row=$(last_row)
  if [[ $row == *"~@"* || $row != *3* ]]; then
    fail "3<leader> pending: the count shows, the mapping key does not" "$row"
  else
    pass "3<leader> pending: the count shows, the mapping key does not"
  fi
fi

reset
b0=$(body)
send g
wait_for 3000 body_differs "$b0"
if junk; then fail "g pending: no mapping key on the last line" "$(last_row)"; else pass "g pending: no mapping key on the last line"; fi
send Escape
wait_for 3000 body_is "$b0"
if junk; then fail "after <Esc>: no mapping key left on the last line" "$(last_row)"; else pass "after <Esc>: no mapping key left on the last line"; fi
finish
