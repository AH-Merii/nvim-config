#!/usr/bin/env bash
# @desc     in the TUI the statusline's path follows what changes it without a typed command or a buffer switch: a window widened by :only, a :cd and a rename, each run from a mapping
# @areas    ui
# @budget   30
# @fixture  tobj
# Typed with ':', each of these would also leave the command line, and that rebuilds the line anyway; and a headless
# check's vim.wait never fires WinResized. So nvim runs in a real TUI under tmux, and test mappings run them as <Cmd>
# maps do. notes.txt has no server or tool and tobj is no git repo, so nothing else redraws.
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
pass() { out "PASS $1"; }
fail() { out "FAIL $1  -- $2"; }
finish() { out DONE; exit 0; }

# a private tmux server, killed on exit so no tagged process outlives the check
SOCK=$FIX/.tmux.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-statusline-events-$$.sock
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
last_row() { "${T[@]}" capture-pane -p -t nvr 2>/dev/null | tail -n 1; }
send() { "${T[@]}" send-keys -t nvr "$@"; }
# shows <text>: the path on the last row, starting with <text> (after the mode icon's space)
shows() { [[ $(last_row) == *" $1"* ]]; }
has() { [[ $(last_row) == *"$1"* ]]; }

project=$(basename "$FIX")
mkdir -p "$FIX/a_long_folder/another"
printf 'some notes\n' >"$FIX/a_long_folder/another/notes.txt"
READY=$FIX/.nvr-ready
LUA="vim.schedule(function() vim.fn.writefile({}, '$READY') end)"
SPLIT='nnoremap <F5> <Cmd>vsplit<CR>'
ONLY='nnoremap <F6> <Cmd>only<CR>'
CD='nnoremap <F7> <Cmd>cd a_long_folder<CR>'
# renamed in its own folder, so its tools root and the rest of its facts stay the same
RENAME="nnoremap <F8> <Cmd>lua vim.api.nvim_buf_set_name(0, vim.fn.expand('%:p:h') .. '/renamed.txt')<CR>"
printf 'exec %q %q -c %q -c %q -c %q -c %q -c %q a_long_folder/another/notes.txt\n' "$NV" "$V" \
  "autocmd User VeryLazy ++once lua $LUA" "$SPLIT" "$ONLY" "$CD" "$RENAME" >"$FIX/.nvr-launch.sh"
if ! "${T[@]}" new-session -d -s nvr -x 160 -y 40 -c "$FIX" "bash $(printf %q "$FIX/.nvr-launch.sh")" 2>/dev/null; then
  fail "nvim starts under tmux" "tmux new-session failed"
  finish
fi
if ! wait_for 20000 test -e "$READY"; then
  fail "nvim starts under tmux and runs VeryLazy" "no VeryLazy within 20s; last line: $(last_row)"
  finish
fi
full=$project/a_long_folder/another/notes.txt
if ! wait_for 5000 shows "$full"; then
  fail "set up: the path shows in full at 160 columns" "last line: $(last_row)"
  finish
fi

# A split halves the window, so the path's budget (0.4 of its width) takes the short form; :only gives the width
# back with no WinEnter, only WinResized
send F5
if wait_for 3000 has "/a/a/notes.txt"; then
  send F6
  if wait_for 2000 shows "$full"; then
    pass ":only: the path widens again with its window"
  else
    fail ":only: the path widens again with its window" "last line: $(last_row)"
  fi
else
  fail "set up: a split shortens the path to a/a/notes.txt" "last line: $(last_row)"
fi

# Outside a repo the path starts at the cwd
send F7
if wait_for 2000 shows "a_long_folder/another/notes.txt"; then
  pass "a :cd from a mapping: the path starts at the new cwd"
else
  fail "a :cd from a mapping: the path starts at the new cwd" "last line: $(last_row)"
fi

send F8
if wait_for 2000 shows "a_long_folder/another/renamed.txt"; then
  pass "a rename from a mapping (nvim_buf_set_name): the path shows the new name"
else
  fail "a rename from a mapping (nvim_buf_set_name): the path shows the new name" "last line: $(last_row)"
fi
finish
