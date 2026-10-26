#!/usr/bin/env bash
# GUI check, in the cachyos QEMU VM only: the config in ghostty in the VM's niri session, captured over VNC.
# Nothing runs on the host desktop: no window, no niri msg, no clipboard. Every GUI step is in the guest.
# usage: gui.sh up                     lease cachyos, restore after-pr140, boot headless, log in, push builds, config, fixtures
#        gui.sh scenes <ver> [dir]     fresh start, then the six scenes -> <dir>/<ver>-<n>-<scene>.png (default last/gui)
#        gui.sh start <ver> [file]     empty data, state and cache, ghostty + nvim in the VM; then keys/expr/shot/stop
#        gui.sh keys <keys> | expr <expr> | shot <out.png> | stop
#        gui.sh down                   release the lease (powers the VM off)
# <ver>: a Neovim build in the user's mise, github:neovim/neovim@<ver>, e.g. nightly. `up` pushes nightly.
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export S
# shellcheck source=lib.sh
. "$S/lib.sh"
VMS=$HOME/VMs VM=cachyos SNAP=after-pr140
usage() { sed -n '3,9p' "$0"; exit 2; }
vssh() { ssh -F "$VMS/ssh_config" -o ConnectTimeout=20 "testing@$VM" "$@"; }
# guest <script>: bash in the guest with the niri session's socket exported
guest() { vssh bash -s <<<"export NIRI_SOCKET=\$(ls /run/user/\$(id -u)/niri.*.sock 2>/dev/null | head -1); $1"; }
rexpr() { printf %s "$1" | vssh nvr/rx; }
rkeys() { printf %s "$1" | vssh nvr/rs; }
# the guest powers its monitor off when idle; wake it first
shot() { guest 'niri msg action power-on-monitors' && sleep 1 && "$VMS/shot.sh" "$VM" "$1" && echo "$1"; }
# rmode: nvim_get_mode, a fast call answered even at a hit-enter or -- More -- prompt; "none" without a server
rmode() { vssh nvr/mode 2>/dev/null || echo none; }
lease_check() { "$VMS/lease.sh" check "$VM" || exit 1; }
# ping: a lease heartbeat; short ssh calls alone do not count, and the lease powers the VM off after 10 idle minutes
ping() { "$VMS/lease.sh" ping >/dev/null 2>&1; }
ver_of() {
  case "$1" in
    "") usage ;;
    *) nvim_build "$1" >/dev/null || exit 2; echo "$1" ;;
  esac
}
# wait_for <secs> <expr>: poll the expression until it evaluates to 1
wait_for() {
  local end=$((SECONDS + $1))
  while [ $SECONDS -lt $end ]; do [ "$(rexpr "$2" 2>/dev/null)" = 1 ] && return 0; ping; sleep 2; done
  return 1
}

up() {
  "$VMS/lease.sh" acquire "$VM" -p "${PURPOSE:-nvim GUI check}" || exit 1
  "$VMS/lease.sh" restore "$VM" "$SNAP" || exit 1
  GL=headless "$VMS/test-ready.sh" "$VM" >/dev/null || exit 1
  local i
  # the greeter: type the password until niri runs for testing
  for i in $(seq 20); do
    vssh pgrep -u testing -x niri >/dev/null && break
    [ "$i" = 3 ] && python3 "$VMS/qmp.py" "$VMS/$VM/qmp.sock" type 'testing123\n' >/dev/null
    sleep 3
  done
  vssh pgrep -u testing -x niri >/dev/null || { echo "no niri session in the guest" >&2; exit 1; }
  push
}

push() {
  local e="ssh -F $VMS/ssh_config" v b
  vssh mkdir -p nvr/builds nvr/src .local/bin
  for v in nightly; do b=$(nvim_build "$v") || exit 2; rsync -a --delete -e "$e" "$b/" "testing@$VM:nvr/builds/$v/"; done
  rsync -a --delete -e "$e" "$CFG/" "testing@$VM:nvr/src/nvim/"
  rsync -a --delete -e "$e" "$S/fixtures/default/" "testing@$VM:nvr/src/fix/"
  # the config gets the tree-sitter CLI from mise, which the snapshot has not installed
  rsync -aL -e "$e" "$HOME/.local/share/mise/installs/tree-sitter/0.27.0/tree-sitter" "testing@$VM:.local/bin/tree-sitter"
  guest '
[ -e ~/.config/nvim.hm ] || mv ~/.config/nvim ~/.config/nvim.hm
printf "%s\n" "#!/bin/bash" "v=\$1; shift; export PATH=\$HOME/nvr/builds/\$v/bin:\$PATH" "exec nvim --listen /tmp/nvr.sock \"\$@\"" >~/nvr/nv
printf "%s\n" "#!/bin/bash" "exec timeout 10 nvim --clean --server /tmp/nvr.sock --remote-expr \"\$(cat)\"" >~/nvr/rx
printf "%s\n" "#!/bin/bash" "exec timeout 10 nvim --clean --server /tmp/nvr.sock --remote-send \"\$(cat)\"" >~/nvr/rs
printf "%s\n" "local ok, ch = pcall(vim.fn.sockconnect, \"pipe\", \"/tmp/nvr.sock\", { rpc = true })" \
  "if not ok or ch == 0 then io.stdout:write(\"none\\n\") os.exit(0) end" \
  "local m = vim.rpcrequest(ch, \"nvim_get_mode\")" "io.stdout:write(m.mode .. (m.blocking and \" blocking\" or \"\") .. \"\\n\")" >~/nvr/mode.lua
printf "%s\n" "#!/bin/bash" "exec timeout 10 nvim --clean --headless -l \$HOME/nvr/mode.lua" >~/nvr/mode
chmod +x ~/nvr/nv ~/nvr/rx ~/nvr/rs ~/nvr/mode'
}

stop() {
  rkeys '<C-\><C-n>:qa!<CR>' 2>/dev/null
  guest 'w() { niri msg -j windows | jq -r ".[] | select(.app_id==\"dev.nvr.check\") | .id" | head -1; }
for i in $(seq 20); do [ -z "$(w)" ] && break; sleep 0.5; done
id=$(w); [ -n "$id" ] && niri msg action close-window --id "$id"
pkill -f "nvim --listen /tmp/nvr.sock"; rm -f /tmp/nvr.sock; true'
}

# launch <ver> [file]: ghostty + nvim in the guest's session, on whatever data, state and cache are there
launch() {
  stop >/dev/null 2>&1
  guest "niri msg action spawn -- ghostty --class=dev.nvr.check --gtk-single-instance=false --working-directory=\$HOME/nvr/fix -e \$HOME/nvr/nv $1 ${2:-}
w() { niri msg -j windows | jq -r '.[] | select(.app_id==\"dev.nvr.check\") | .id' | head -1; }
for i in \$(seq 50); do id=\$(w); [ -n \"\$id\" ] && break; sleep 0.2; done
[ -n \"\$id\" ] || { echo 'no ghostty window in the guest' >&2; exit 1; }
niri msg action focus-window --id \$id; niri msg action maximize-column
for i in \$(seq 100); do [ -S /tmp/nvr.sock ] && break; sleep 0.2; done
[ -S /tmp/nvr.sock ] || { echo 'nvim did not listen' >&2; exit 1; }" || return 1
  # the pointer to the bottom-right corner, off the popups
  python3 "$VMS/qmp.py" "$VMS/$VM/qmp.sock" raw '{"execute": "input-send-event", "arguments": {"events": [{"type": "abs", "data": {"axis": "x", "value": 32767}}, {"type": "abs", "data": {"axis": "y", "value": 32767}}]}}' >/dev/null
}

# start <ver> [file]: empty data, state and cache; a fresh copy of the config and of the fixture repo
start() {
  stop >/dev/null 2>&1
  guest "rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim ~/.config/nvim ~/nvr/fix
cp -a ~/nvr/src/nvim ~/.config/nvim && cp -a ~/nvr/src/fix ~/nvr/fix" || return 1
  launch "$@"
}

# settle <png>: wait for startup and the parser installs to finish, however long they take; give up only
# after SETTLE_STALL seconds (default 180) without progress: a prompt, a new parser, or an install process
# (vim.pack's git, a parser build) starting or ending. The first hit-enter or -- More -- prompt is captured to
# <png>; a -- More -- is paged to its end with G, a hit-enter prompt is dismissed with <CR> and counted.
# Sets PROMPTS and PARSERS.
settle() {
  local parsers='luaeval("(function() local ok, ts = pcall(require, \"nvim-treesitter\"); return ok and #ts.get_installed() or 0 end)()")'
  local m c last=-1 same=0 idle=0 procs seen= moved=$SECONDS stall=${SETTLE_STALL:-180}
  PROMPTS=0 PARSERS=0
  while :; do
    ping
    if [ $((SECONDS - moved)) -ge "$stall" ]; then
      echo "settle: no progress for ${stall}s, giving up" | tee -a "$LOG" >&2
      break
    fi
    m=$(rmode)
    case "$m" in
      r*)
        [ $PROMPTS = 0 ] && [ ! -e "$1" ] && shot "$1" >/dev/null
        case "$m" in
          rm*) rkeys 'G' ;;
          # nothing but fast calls at a prompt: --remote-expr waits until the prompt is gone
          *) PROMPTS=$((PROMPTS + 1)); echo "prompt $PROMPTS: mode '$m' at ${SECONDS}s" >>"$LOG"; rkeys '<CR>' ;;
        esac
        moved=$SECONDS
        sleep 1
        continue ;;
    esac
    procs=$(vssh "pgrep -u testing -x 'git|tree-sitter|cc|gcc|clang|curl|tar'" 2>/dev/null)
    [ "$procs" != "$seen" ] && moved=$SECONDS
    seen=$procs
    if [ "$(rexpr 'v:vim_did_enter' 2>/dev/null)" = 1 ]; then
      c=$(rexpr "$parsers" 2>/dev/null)
      c=${c:-0}
      [ "$c" != "$last" ] && moved=$SECONDS
      if [ "$c" = "$last" ] && ! vssh "pgrep -u testing -x tree-sitter" >/dev/null; then
        same=$((same + 1))
      else
        same=0
      fi
      last=$c
      # done when the count holds for 9s, or nothing installs for a minute (the parser install never started)
      [ "$c" -gt 0 ] && [ $same -ge 3 ] && break
      [ "$c" = 0 ] && idle=$((idle + 1)) && [ $idle -ge 20 ] && break
    fi
    sleep 3
  done
  PARSERS=$last
  echo "settled: $PROMPTS prompts, $PARSERS parsers, mode '$(rmode)'" >>"$LOG"
}

# messages <title>: append :messages and the last error to the log, as a session ends. execute() captures
# the history without opening ui2's pager, which would stay in every later shot
messages() { { echo "== $1"; rexpr 'execute("messages")'; echo; echo "errmsg: $(rexpr 'v:errmsg')"; echo "ui2: $(rexpr "$UI2")"; } >>"$LOG" 2>&1; }
# the suite runs headless, where ui2 never attaches, so only here would a broken ui2 show: "ui2: attached"
# needs its cmd and msg windows open, and no ui_attach error in :messages
UI2='luaeval("(function() local u = require([[vim._core.ui2]]); local ok = u.cmd ~= nil and vim.iter({ u.wins.cmd, u.wins.msg }):all(function(w) return vim.api.nvim_win_is_valid(w) end); local err = vim.fn.execute([[messages]]):find([[ui_attach]]); return (ok and not err) and [[attached]] or ([[NOT OK: windows ]] .. tostring(ok) .. [[, ui_attach error ]] .. tostring(err ~= nil)) end)()")'

scenes() {
  local ver=$1 out=${2:-$S/last/gui}
  mkdir -p "$out"
  LOG=$out/$ver-messages.txt
  : >"$LOG"

  # 1. first start: vim.pack installs the plugins, the parsers install on VimEnter, no hit-enter prompt
  echo "== 1 first start" >>"$LOG"
  start "$ver" || return 1
  settle "$out/$ver-1-first-start-prompt.png"
  shot "$out/$ver-1-first-start.png"
  if [ $PROMPTS -gt 0 ] || [ "$PARSERS" = 0 ]; then
    messages "1 first start"
    # the first start did not finish cleanly: start again on the same data so the other scenes can run
    echo "== 1 second start, same data" >>"$LOG"
    launch "$ver"
    settle "$out/$ver-1-second-start-prompt.png"
    shot "$out/$ver-1-second-start.png"
    fi

  # 2. a filetype whose tools are missing asks first (lua/tools/ux.lua): Install / Later / Not for this project
  rkeys '<C-\><C-n>:e main.lua<CR>'
  sleep 4
  shot "$out/$ver-2-ask-install.png"
  rkeys '<CR>' # Install, the first choice; it runs `mise use` in the guest
  wait_for 300 'luaeval("#vim.lsp.get_clients({ bufnr = 0, name = \"lua_ls\" })") > 0' ||
    echo "$ver: lua_ls did not attach" >>"$LOG"
  sleep 3

  # 3. which-key for <leader> in a Lua buffer with lua_ls attached
  rkeys '<C-\><C-n> '
  sleep 2
  shot "$out/$ver-3-which-key.png"
  rkeys '<Esc>'

  # 4. the completion menu with kind icons
  rkeys '<C-\><C-n>Govim.'
  sleep 3
  shot "$out/$ver-4-completion.png"
  rkeys '<Esc>u'

  # 5. pending keys mid-sequence: register, count, operator
  rkeys '<C-\><C-n>"a2d'
  sleep 1
  shot "$out/$ver-5-pending-keys.png"
  rkeys '<Esc>'

  # 6. a diff view where ]c jumps to the next change
  rkeys '<C-\><C-n>ggOlocal added = true<Esc>Gofunction M.bye() end<Esc>:w<CR>'
  sleep 2
  rkeys '<C-\><C-n>:Gitsigns diffthis<CR>'
  sleep 3
  rkeys '<C-\><C-n>gg]c'
  sleep 1
  local l1
  l1=$(rexpr 'line(".")')
  rkeys ']c'
  sleep 1
  echo "$ver: diff ]c from the top -> line $l1, again -> line $(rexpr 'line(".")'); ]c maps to: $(rexpr 'maparg("]c", "n")')" >>"$LOG"
  shot "$out/$ver-6-diff-next-change.png"
  messages "session end"
  stop
}

cmd=${1:-}
case "$cmd" in
  up) up ;;
  down) "$VMS/lease.sh" release ;;
  push) lease_check; push ;;
  scenes) lease_check; scenes "$(ver_of "${2:-}")" "${3:-}" ;;
  start) lease_check; start "$(ver_of "${2:-}")" "${3:-}" ;;
  keys) lease_check; rkeys "$2" ;;
  expr) lease_check; rexpr "$2" ;;
  shot) lease_check; shot "$2" ;;
  stop) lease_check; stop ;;
  *) usage ;;
esac
