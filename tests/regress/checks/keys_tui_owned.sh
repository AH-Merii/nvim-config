#!/usr/bin/env bash
# @desc     in the TUI, after the plugins that only set up with a UI have run, every textobject key is still the textobjects dispatcher, and snacks maps no key of its own beyond the ones the config gives it
# @areas    keys treesitter ui which-key
# @budget   30
# @fixture  tobj
# snacks sets some modules up on UIEnter (snacks/init.lua, UIEnter = { ..., "scope", ... }), which a headless check
# never reaches; its scope module mapped [i ]i ii ai over the conditional textobjects while the popup still labelled
# them as ours (D146). So nvim runs in a real TUI under tmux.
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
pass() { out "PASS $1"; }
fail() { out "FAIL $1  -- $2"; }
finish() { out DONE; exit 0; }

SOCK=$FIX/.tmux.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-tui-owned-$$.sock
T=(tmux -S "$SOCK" -f /dev/null)
cleanup() { "${T[@]}" kill-server >/dev/null 2>&1; rm -f "$SOCK"; }
trap cleanup EXIT
trap 'exit 143' TERM INT HUP
unset TMUX TMUX_PANE

now_ms() { echo $(($(date +%s%N) / 1000000)); }
wait_for() {
  local deadline=$(($(now_ms) + $1))
  shift
  until "$@"; do
    [ "$(now_ms)" -ge "$deadline" ] && return 1
    sleep 0.05
  done
}

# The probe runs from VeryLazy, which start() fires once the UI is up, scheduled so UIEnter's setups ran before it
RESULT=$FIX/.nvr-owned
cat >"$FIX/.nvr-owned.lua" <<EOF
local lines = {}
local function source(map) return map and map.callback and debug.getinfo(map.callback, "S").source or "" end
local ours = 0
for _, row in ipairs(require("keys").list()) do
  if row.owner == "textobjects" then
    ours = ours + 1
    local map = vim.fn.maparg(row.lhs, row.mode, false, true)
    if not source(map):find("/lua/textobjects/init.lua", 1, true) then
      lines[#lines + 1] = ("taken %s %s: %s (%s)"):format(row.mode, row.lhs, map.desc or "?", source(map))
    end
  end
end
lines[#lines + 1] = "textobject rows " .. ours
for _, mode in ipairs({ "n", "x", "o", "i", "t", "c" }) do
  for _, map in ipairs(vim.list_extend(vim.api.nvim_get_keymap(mode), vim.api.nvim_buf_get_keymap(0, mode))) do
    if source(map):find("/lua/snacks/", 1, true) then
      lines[#lines + 1] = ("snacks %s %s: %s (%s)"):format(mode, map.lhs, map.desc or "?", source(map))
    end
  end
end
vim.fn.writefile(lines, "$RESULT")
EOF
LUA="vim.schedule(function() vim.defer_fn(function() dofile('$FIX/.nvr-owned.lua') end, 200) end)"
printf 'exec %q %q -c %q a.py\n' "$NV" "$V" "autocmd User VeryLazy ++once lua $LUA" >"$FIX/.nvr-launch.sh"
if ! "${T[@]}" new-session -d -s nvr -x 160 -y 40 -c "$FIX" "bash $(printf %q "$FIX/.nvr-launch.sh")" 2>/dev/null; then
  fail "nvim starts under tmux" "tmux new-session failed"
  finish
fi
if ! wait_for 20000 test -s "$RESULT"; then
  fail "nvim starts under tmux and runs the probe" "no result within 20s"
  finish
fi

rows=$(sed -n 's/^textobject rows //p' "$RESULT")
if [ "${rows:-0}" -gt 0 ]; then pass "the textobjects feature declares keys ($rows rows)"; else fail "the textobjects feature declares keys" "none listed"; fi
taken=$(grep '^taken ' "$RESULT")
if [ -z "$taken" ]; then pass "every textobject key is the textobjects dispatcher in the TUI"; else fail "every textobject key is the textobjects dispatcher in the TUI" "$(echo "$taken" | tr '\n' ';')"; fi
leftover=$(grep '^snacks ' "$RESULT")
if [ -z "$leftover" ]; then pass "snacks maps no key of its own in the TUI"; else fail "snacks maps no key of its own in the TUI" "$(echo "$leftover" | tr '\n' ';')"; fi
finish
