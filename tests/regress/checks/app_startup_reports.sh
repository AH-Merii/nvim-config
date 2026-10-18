#!/usr/bin/env bash
# @desc     in the TUI, what startup reports before neoblocks hooks ui2 (a plugin that fails to install, a phase that raises, a mistake in a language file) shows as a toast and is listed in the message history (<leader>n)
# @areas    startup installer ui
# @budget   60
# A child on its own home and data dir, as checks/app_install_fails.lua builds them: gitsigns.nvim missing from the
# data dir and its source pointing nowhere, so vim.pack's install fails offline in the plugins phase; options.lua
# raising at its end, so the options phase fails; and a second language file claiming lua, a mistake lang reports in
# the tools phase. All three are reported before the startup plugins load (lua/app/), and the install turns the event
# loop before them, so a report merely scheduled would run too early.
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

# beside the suite's home rather than under the fixture: vim.loader names its cache files after the module's full
# path, and under the fixture that name passed 255 bytes (ENAMETOOLONG from vim/loader:138)
ROOT=$NVR_HOME/sr$$
SOCK=$FIX/.tmux.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-startup-reports-$$.sock
NSOCK=${TMPDIR:-/tmp}/nvr-startup-reports-$V-$$.nvim.sock
T=(tmux -S "$SOCK" -f /dev/null)
cleanup() {
  "${T[@]}" kill-server >/dev/null 2>&1
  rm -rf "$SOCK" "$NSOCK" "$ROOT"
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
send() { "${T[@]}" send-keys -t nvr "$@"; }
P() { timeout 5 "$NV" "$V" --clean --headless --server "$NSOCK" --remote-expr "luaeval('P.$1')" </dev/null 2>/dev/null; }
is() { [ "$(P "$1")" = "$2" ]; }

# ---- the child's home and data: the suite's, less gitsigns, whose source points nowhere -------------------------
NAME=gitsigns.nvim
HOME_=$ROOT/home DATA=$ROOT/data CFG_=$ROOT/home/config/nvim
mkdir -p "$HOME_/config" "$HOME_/state" "$HOME_/cache" "$DATA/nvim"
cp -a --reflink=auto "$NVR_HOME/config/nvim" "$CFG_" && cp -a --reflink=auto "$NVR_DATA/nvim/site" "$DATA/nvim/site" ||
  { fail "precondition: the config and data copied" "cp failed"; finish; }
rm -rf "$DATA/nvim/site/pack/core/opt/$NAME"
NOWHERE=file://$ROOT/nowhere/$NAME
sed -i "s#\"https://github.com/lewis6991/$NAME\"#\"$NOWHERE\"#" "$CFG_/nvim-pack-lock.json"
sed -i "s#\"lewis6991/$NAME\"#\"$NOWHERE\"#" "$CFG_/lua/features/git.lua"
if ! grep -qF "$NOWHERE" "$CFG_/nvim-pack-lock.json" || ! grep -qF "$NOWHERE" "$CFG_/lua/features/git.lua"; then
  fail "precondition: the lockfile and the spec point $NAME nowhere" \
    "$(grep -n "$NAME" "$CFG_/nvim-pack-lock.json" "$CFG_/lua/features/git.lua")"
  finish
fi
echo 'error("nvr: injected options failure")' >>"$CFG_/lua/options.lua"
echo 'return { filetypes = { "lua" } }' >"$CFG_/lua/lang/zz_nvr_twice.lua"

cat >"$ROOT/probe.lua" <<'EOF'
P = {}
local api = vim.api
function P.mode() return api.nvim_get_mode().mode end
-- a float other than ui2's own showing text: a snacks.notifier toast
function P.toast(text)
  local ok, ui = pcall(require, "vim._core.ui2")
  local own = ok and ui.wins and vim.tbl_values(ui.wins) or {}
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(w).relative ~= "" and not vim.tbl_contains(own, w) then
      if table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(w), 0, -1, false), "\n"):find(text, 1, true) then
        return true
      end
    end
  end
  return false
end
-- the open picker's list (snacks' list window) shows text
function P.listed(text)
  for _, w in ipairs(api.nvim_list_wins()) do
    local b = api.nvim_win_get_buf(w)
    if vim.bo[b].filetype == "snacks_picker_list" then
      if table.concat(api.nvim_buf_get_lines(b, 0, -1, false), "\n"):find(text, 1, true) then
        return true
      end
    end
  end
  return false
end
EOF

READY=$ROOT/ready
LUA="vim.schedule(function() vim.fn.writefile({}, '$READY') end)"
printf 'exec env NVR_HOME=%q NVR_STATE=%q NVR_DATA=%q %q %q --listen %q -c %q -c %q app.conf\n' \
  "$HOME_" "$HOME_/state" "$DATA" "$NV" "$V" "$NSOCK" "luafile $ROOT/probe.lua" \
  "autocmd User VeryLazy ++once lua $LUA" >"$ROOT/launch.sh"
if ! "${T[@]}" new-session -d -s nvr -x 160 -y 40 -c "$FIX" "bash $(printf %q "$ROOT/launch.sh")" 2>/dev/null; then
  fail "nvim starts under tmux" "tmux new-session failed"
  finish
fi
if ! wait_for 30000 test -e "$READY"; then
  fail "nvim starts under tmux and runs VeryLazy" "no VeryLazy within 30s; screen: $(screen | head -n 8)"
  finish
fi
wait_for 3000 is "mode()" n

# Each report reaches the user: as a toast once the startup plugins (snacks, neoblocks) are up, and in the history
ok "the failed install shows a toast naming the plugin" 'screen | head -n 12' wait_for 5000 is "toast(\"$NAME\")" true
ok "the failed options phase shows a toast" 'screen | head -n 12' wait_for 5000 is 'toast("options phase failed")' true
ok "the language file's mistake shows a toast" 'screen | head -n 12' wait_for 5000 is 'toast("zz_nvr_twice")' true

# <leader>n opens the message history
send Space n
ok "the history lists the failed install" 'screen' wait_for 5000 is "listed(\"$NAME\")" true
ok "the history lists the failed options phase" 'screen' wait_for 3000 is 'listed("options phase failed")' true
ok "the history lists the language file's mistake" 'screen' wait_for 3000 is 'listed("zz_nvr_twice")' true
finish
