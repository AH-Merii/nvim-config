#!/usr/bin/env bash
# @desc     in the TUI ui2 behaves like noice did: ':' in a bordered popup with the statusline kept on the last row, '/' over the last row without moving the layout, :echo and errors as titled toasts (errors stay, search and navigation errors time out), undo messages silent, long (also wrapped) output in a split that is not entered (a typed command's output measured as a whole, other messages one at a time), g< opens the pager, and ui2's own cmdline window comes back afterwards
# @areas    ui
# @budget   60
# @args     app.conf
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
pass() { out "PASS $1"; }
fail() { out "FAIL $1  -- $2"; }
finish() { out DONE; exit 0; }
# ok <name> <detail> <command...>: PASS when the command succeeds, else FAIL with the detail, a shell
# expression evaluated after the failure
ok() {
  local name=$1 detail=$2
  shift 2
  if "$@"; then pass "$name"; else fail "$name" "$(eval "$detail")"; fi
}

# a private tmux server, killed on exit so no tagged process outlives the check
SOCK=$FIX/.tmux.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-ui2-noice-$$.sock
NSOCK=${TMPDIR:-/tmp}/nvr-ui2-noice-$V-$$.nvim.sock
T=(tmux -S "$SOCK" -f /dev/null)
cleanup() {
  "${T[@]}" kill-server >/dev/null 2>&1
  rm -f "$SOCK" "$NSOCK"
}
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
send() { "${T[@]}" send-keys -t nvr "$@"; }
# P <probe>: result of a probe.lua function; a pending key or prompt blocks --remote-expr, hence the timeout
P() { timeout 5 "$NV" "$V" --clean --headless --server "$NSOCK" --remote-expr "luaeval('P.$1')" </dev/null 2>/dev/null; }
is() { [ "$(P "$1")" = "$2" ]; }
has_screen() { screen | grep -qE -- "$1"; }
has_last() { [[ $(last_row) == *"$1"* ]]; }
# title_is <text> <title>: the toast showing text has this title after snacks' level icon
title_is() { [[ $(P "toast_title(\"$1\")") == *" $2" ]]; }
reset() {
  send Escape
  send Escape
  wait_for 3000 is "mode()" n
}

# Probes, read over --remote-expr. ui2 is private (vim._core.ui2), the same internals ui/messages hooks.
cat >"$FIX/.nvr-probe.lua" <<'EOF'
P = {}
local api, ui = vim.api, require("vim._core.ui2")
function P.mode() return api.nvim_get_mode().mode end
-- ui.messages's wrappers are installed (they put ui2's handlers back when an internal they use moved)
function P.hooked() return ui.cmd ~= nil and ui.cmd.cmdline_show == require("ui.messages.cmdline").cmdline_show end
-- ui2's cmd window: relative, title and 'cmdheight'
function P.cmd()
  local c = api.nvim_win_get_config(ui.wins.cmd)
  local title = type(c.title) == "table" and c.title[1] and c.title[1][1] or ""
  return ("%s|%s|%d"):format(c.relative, vim.trim(title), vim.o.cmdheight)
end
-- a float other than ui2's own showing text: a snacks.notifier toast
function P.toast(text)
  local ui2wins = vim.tbl_values(ui.wins)
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(w).relative ~= "" and not vim.tbl_contains(ui2wins, w) then
      if table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(w), 0, -1, false), "\n"):find(text, 1, true) then
        return true
      end
    end
  end
  return false
end
-- ui2's msg float shows text
function P.msgwin(text)
  local c = api.nvim_win_get_config(ui.wins.msg)
  return not c.hide and table.concat(api.nvim_buf_get_lines(ui.bufs.msg, 0, -1, false), "\n"):find(text, 1, true) ~= nil
end
-- a split (not a float) that is not the current window and shows text
function P.split(text)
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(w).relative == "" and w ~= api.nvim_get_current_win() then
      if table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(w), 0, -1, false), "\n"):find(text, 1, true) then
        return true
      end
    end
  end
  return false
end
function P.splits() return #vim.tbl_filter(function(w) return api.nvim_win_get_config(w).relative == "" end, api.nvim_tabpage_list_wins(0)) end
function P.height() return api.nvim_win_get_height(0) end
-- the title of the toast showing text
function P.toast_title(text)
  for _, w in ipairs(api.nvim_list_wins()) do
    local c = api.nvim_win_get_config(w)
    if c.relative ~= "" and table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(w), 0, -1, false), "\n"):find(text, 1, true) then
      return type(c.title) == "table" and vim.trim(table.concat(vim.tbl_map(function(t) return t[1] end, c.title))) or ""
    end
  end
  return "none"
end
function P.toasts() return #vim.tbl_filter(function(w) return w.relative ~= "" and not vim.tbl_contains(vim.tbl_values(ui.wins), w.win) end, vim.tbl_map(function(w) return vim.tbl_extend("force", api.nvim_win_get_config(w), { win = w }) end, api.nvim_list_wins())) end
function P.in_pager() return api.nvim_get_current_win() == ui.wins.pager end
-- :messages lines other than the errors caused on purpose, the undo message and the printed lines
function P.bad_messages()
  local function expected(l) return l == "" or l:find("nosuchcmd") or l:find("ui2%-no%-such%-text") or l:find("^E42: No Errors") or l:find("^ui2%-[a-z]+%-") or l:find("^1 line less") or l:find("^%d+x*$") end
  local bad = vim.tbl_filter(function(l) return not expected(l) end, vim.split(vim.fn.execute("messages"), "\n"))
  return table.concat(bad, " / ")
end
EOF

READY=$FIX/.nvr-ready
LUA="vim.schedule(function() vim.fn.writefile({}, '$READY') end)"
printf 'exec %q %q --listen %q -c %q -c %q app.conf\n' "$NV" "$V" "$NSOCK" "luafile $FIX/.nvr-probe.lua" "autocmd User VeryLazy ++once lua $LUA" >"$FIX/.nvr-launch.sh"
if ! "${T[@]}" new-session -d -s nvr -x 120 -y 36 -c "$FIX" "bash $(printf %q "$FIX/.nvr-launch.sh")" 2>/dev/null; then
  fail "nvim starts under tmux" "tmux new-session failed"
  finish
fi
if ! wait_for 20000 test -e "$READY"; then
  fail "nvim starts under tmux and runs VeryLazy" "no VeryLazy within 20s; last line: $(last_row)"
  finish
fi
wait_for 3000 is "mode()" n
if ! is "hooked()" true; then
  fail "ui.messages hooks ui2's cmdline" "ui2.cmd.cmdline_show is not ui.messages.cmdline's wrapper: a ui2 internal it needs moved (see :messages / the WARN toast)"
  finish
fi
pass "ui.messages hooks ui2's cmdline"

# ':' in noice's command palette: a bordered popup titled Cmdline, the last row stays the statusline, cmdheight stays 0
reset
send :
if wait_for 3000 is "cmd()" "editor|Cmdline|0"; then
  pass "':' opens the popup (relative=editor, title Cmdline, cmdheight 0)"
else
  fail "':' opens the popup (relative=editor, title Cmdline, cmdheight 0)" "cmd window: $(P "cmd()")"
fi
ok "the popup has a rounded border with the title on screen" 'screen | head -n 8' wait_for 2000 has_screen "╭─+ Cmdline ─+╮"
ok "the last row is still the statusline while typing ':'" 'echo "last row: $(last_row)"' has_last app.conf
send Escape
ok "<Esc> puts ui2's cmd window back at the bottom" 'echo "cmd window: $(P "cmd()")"' wait_for 3000 is "cmd()" "laststatus||0"

# '/' stays at the bottom over the statusline (noice bottom_search): cmdheight stays 0, the window keeps its height
reset
height=$(P "height()")
send /
send other
ok "'/' types on the last row" 'echo "last row: $(last_row)"' wait_for 3000 has_last "/other"
ok "'/' covers the last row without a popup or 'cmdheight'" 'echo "cmd window: $(P "cmd()")"' is "cmd()" "editor||0"
ok "'/' leaves the window height alone" 'echo "height: $(P "height()"), before: $height"' is "height()" "$height"
send Escape
wait_for 3000 is "mode()" n

# messages: :echo is a toast, not ui2's msg float; an error toast stays
reset
send ':echo "ui2-echo-toast"' Enter
ok ":echo shows a toast" 'screen | head -n 6' wait_for 3000 is 'toast("ui2-echo-toast")' true
ok ":echo is not in ui2's msg float" "ui2's msg window shows it" is 'msgwin("ui2-echo-toast")' false
reset
send ':nosuchcmd' Enter
ok "an error (E492) shows a toast" 'screen | head -n 6' wait_for 3000 is 'toast("E492")' true
ok "the error toast is titled with the typed command" 'echo "title: $(P "toast_title(\"E492\")")"' title_is E492 :nosuchcmd
reset
send /ui2-no-such-text Enter
ok "an error from no typed command is titled Error (noice's title)" 'echo "title: $(P "toast_title(\"E486\")")"' wait_for 3000 title_is E486 Error
reset
send ':cnext' Enter
ok "a routine error from a typed command (E42) shows a toast" 'screen | head -n 6' wait_for 3000 is 'toast("E42")' true
reset
sleep 4.5 # longer than snacks' 3s timeout and ui2's 4s 'messagesopt'
ok "an error (E492) is still there after 4.5s" 'screen | head -n 6' is 'toast("E492")' true
ok "a routine search error (E486, pattern not found) is gone after 4.5s" 'screen | head -n 6' is 'toast("E486")' false
ok "a routine typed error (E42, :cnext with no list) is gone after 4.5s" 'screen | head -n 6' is 'toast("E42")' false

# undo messages stay silent, as under noice
reset
"${T[@]}" send-keys -t nvr Space N # <leader>N dismisses the toasts
wait_for 3000 is "toasts()" 0
send o undo-me Escape
wait_for 3000 is "mode()" n
send u
sleep 0.5
ok "u shows no toast" 'screen | head -n 6' is "toasts()" 0

# long output goes to a split below that is not entered (noice long_message_to_split)
reset
send ':lua print(table.concat(vim.fn.range(1, 60), "\n"))' Enter
ok "60 lines of output open a split that is not the current window" 'echo "splits: $(P "splits()")"' wait_for 3000 is 'split("\n60")' true
ok "the long output is not a toast" "a toast shows it" is 'toast("\n60")' false
send C-w j # the split is below; q closes it
send q
ok "q closes the output split" 'echo "splits: $(P "splits()")"' wait_for 3000 is "splits()" 1
# one typed command's output is measured as a whole: 25 one-line print()s together are too tall for a toast
reset
send ':lua for i = 1, 25 do print("ui2-typed-" .. i) end' Enter
ok "25 short lines from one typed command open the split" 'screen | head -n 24' wait_for 3000 is 'split("ui2-typed-25")' true
ok "the typed command's lines are not a toast" "a toast shows them" is 'toast("ui2-typed-25")' false
send C-w j
send q
wait_for 3000 is "splits()" 1
# messages from no typed command (a timer, like nvim-treesitter's downloads) are measured one at a time
# (noice's min_height is per message): a burst of short ones stays a toast, one tall one still splits
reset
send ':lua vim.defer_fn(function() for i = 1, 25 do vim.api.nvim_echo({ { "ui2-burst-" .. i } }, true, {}) end end, 100)' Enter
ok "25 short echomsg from a timer show a toast" 'screen | head -n 24' wait_for 3000 is 'toast("ui2-burst-25")' true
ok "25 short echomsg from a timer open no split" 'echo "splits: $(P "splits()")"' is "splits()" 1
send ':lua vim.defer_fn(function() print("ui2-async-long\n" .. table.concat(vim.fn.range(1, 30), "\n")) end, 100)' Enter
ok "one 31-line message from a timer opens the split" 'screen | head -n 24' wait_for 3000 is 'split("ui2-async-long")' true
send C-w j
send q
wait_for 3000 is "splits()" 1
# 19 lines of 47 cells wrap to 2 rows each in a 48-cell toast (snacks pads 2 cells): too tall for a toast
reset
send ':lua for i = 10, 28 do print(i .. string.rep("x", 45)) end' Enter
ok "19 wrapping lines open the split, not a cut-off toast" 'screen | head -n 24' wait_for 3000 is 'split("28xxx")' true
send C-w j
send q
wait_for 3000 is "splits()" 1

# g< still opens ui2's pager
reset
send ':echo "ui2-for-pager"' Enter
wait_for 3000 is 'toast("ui2-for-pager")' true
send g '<'
ok "g< opens ui2's pager as the current window" 'echo "last row: $(last_row)"' wait_for 3000 is "in_pager()" true
send q
wait_for 3000 is "in_pager()" false

reset
ok "ui2's cmd window is back at relative=laststatus after the session" 'echo "cmd window: $(P "cmd()")"' is "cmd()" "laststatus||0"
bad=$(P "bad_messages()")
if [ -z "$bad" ]; then pass ":messages holds nothing unexpected"; else fail ":messages holds nothing unexpected" "$bad"; fi
finish
