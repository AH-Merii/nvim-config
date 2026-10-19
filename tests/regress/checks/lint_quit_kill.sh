#!/usr/bin/env bash
# @desc     no linter run outlives Neovim: :wq with a linter still running exits at once and leaves none of its processes, nor of the runs nvim-lint cancelled; while Neovim runs, closing a window, unloading or deleting a buffer kills no run, and the other buffer's findings still arrive
# @areas    lint
# @budget   60
# A stand-in yamllint in the project's .venv/bin ignores SIGTERM and SIGINT, as a linter busy in a child may. On a
# buffer holding "slow" it logs its pid and its child's and sleeps; on one holding "cancel" too, but nvim-lint's SIGINT
# ends it and leaves its child; on any other it logs its start and reports one finding once the check says so.
# nvim runs headless and is driven over its socket, not through the harness: the harness waits up to 15 s for
# nvim-lint's runs before it quits (harness.lua), so a run would end before the quit and no orphan would show.
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
pass() { out "PASS $1"; }
fail() { out "FAIL $1  -- $2"; }

now_ms() { local t=${EPOCHREALTIME/./}; echo $((t / 1000)); }
# wait_for <ms> <command...>: poll the command every 20ms until it succeeds or the time is up
wait_for() {
  local deadline=$(($(now_ms) + $1))
  shift
  until "$@"; do
    [ "$(now_ms)" -ge "$deadline" ] && return 1
    sleep 0.02
  done
}

LOG=$FIX/standin-pids.log FASTLOG=$FIX/standin-fast.log RELEASE=$FIX/standin-release
mkdir -p "$FIX/.venv/bin"
cat >"$FIX/.venv/bin/yamllint" <<EOF
#!/bin/sh
trap '' TERM INT
input=\$(cat)
case "\$input" in
  *slow*) echo \$\$ >>'$LOG'; sleep 600 & echo \$! >>'$LOG'; wait ;;
  *cancel*) trap 'exit 0' INT; echo \$\$ >>'$LOG'; sleep 600 & echo \$! >>'$LOG'; wait ;;
  *)
    echo \$\$ >>'$FASTLOG'
    i=0
    until [ -e '$RELEASE' ] || [ \$i -ge 1000 ]; do i=\$((i + 1)); sleep 0.01; done
    echo 'stdin:1:1: [error] stand-in finding (standin)' ;;
esac
EOF
chmod +x "$FIX/.venv/bin/yamllint"
printf 'slow: 1\n' >"$FIX/slow.yaml"
printf 'fast: 1\n' >"$FIX/fast.yaml"
printf 'cancel: 1\n' >"$FIX/cancel.yaml"

SOCK=$FIX/.nvim.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-lint-quit-$$.sock
# The client that drives it: the binary nv.sh runs, called straight, as nv.sh's setup on every call (a mise lookup when
# NVR_NVIM is unset) costs more than the call; in the check's own XDG dirs, as nv.sh would run it
BIN=$("$NV" "$V" --clean --headless --cmd 'lua io.stdout:write(vim.v.progpath)' --cmd 'qa!' </dev/null 2>/dev/null)
R() {
  XDG_CONFIG_HOME=$NVR_HOME/config XDG_DATA_HOME=$NVR_DATA XDG_STATE_HOME=$NVR_STATE XDG_CACHE_HOME=$NVR_HOME/cache \
    timeout 5 "$BIN" --clean --headless --server "$SOCK" "$@" </dev/null 2>/dev/null
}
# settled: what the last command scheduled has run, two rounds deep (a callback may schedule another), so a kill it
# set off has been sent
settled() {
  [ "$(R --remote-expr 'luaeval("(function() for _ = 1, 2 do local ran = false vim.schedule(function() ran = true end) vim.wait(1000, function() return ran end) end return 1 end)()")')" = 1 ]
}
pids() { cat "$LOG" 2>/dev/null; }
alive() { local s; s=$(cut -d' ' -f3 "/proc/$1/stat" 2>/dev/null) && [ "$s" != Z ]; }
none_alive() { local p; for p in $(pids); do alive "$p" && return 1; done; return 0; }
# the newest run's pids (a run logs its own and its child's): the one not cancelled, which nvim-lint leaves running
latest() { pids | tail -n 2; }
# alive, with no signal waiting to be acted on: a kill sent a moment ago may not have ended it yet
untouched() { alive "$1" && awk '/^(SigPnd|ShdPnd):/ && $2 !~ /^0+$/ { exit 1 }' "/proc/$1/status" 2>/dev/null; }
latest_untouched() { local p; for p in $(latest); do untouched "$p" || return 1; done; return 0; }
dead() { ! alive "$1"; }
logged() { [ "$(pids | wc -l)" -ge "$1" ]; }
started=
start() { # start <file>: nvim on file, its socket up
  rm -f "$SOCK" "$LOG" "$FASTLOG" "$RELEASE"
  "$NV" "$V" --headless --listen "$SOCK" "$1" </dev/null >/dev/null 2>&1 &
  started=$!
  wait_for 15000 test -S "$SOCK"
}
gone() { ! kill -0 "$started" 2>/dev/null; }
# kills what a wrong quit left of the runs; suite.sh would report each as a leak too
reap() { local p; for p in $(pids); do alive "$p" && kill -KILL "$p" 2>/dev/null; done; }
finish() {
  [ -S "$SOCK" ] && R --remote-send '<C-\><C-n>:qa!<CR>' >/dev/null
  wait_for 5000 gone || kill -KILL "$started" 2>/dev/null
  rm -f "$SOCK"
}

# 1. :wq with the run started by opening the file still going, and the one the write starts
if ! start slow.yaml; then
  fail "nvim listens on its socket" "no socket within 15s"
elif ! wait_for 15000 logged 2; then
  fail "precondition: the stand-in runs on opening slow.yaml" "pids logged: $(pids | tr '\n' ' ')"
else
  t0=$(now_ms)
  R --remote-send ':wq<CR>'
  if wait_for 5000 gone; then
    pass ":wq with a linter running exits within 5s ($(($(now_ms) - t0)) ms)"
  else
    fail ":wq with a linter running exits within 5s" "still running"
  fi
  if wait_for 3000 none_alive; then
    pass "no process of the linter runs outlives Neovim"
  else
    left=
    for p in $(pids); do alive "$p" && left="$left $(cat "/proc/$p/comm")($p)"; done
    fail "no process of the linter runs outlives Neovim" "alive 3s after the quit:$left"
  fi
fi
finish
reap

# 2. While Neovim runs, nothing but the quit kills a run. Three windows: :wq closes slow.yaml's while fast.yaml's lint
# runs, which reports only once the :wq is done. The cursor goes to an empty window, not fast.yaml's: entering that one
# after a write would lint it again (D72), cancelling the run. Then slow.yaml, whose newest run still goes, is unloaded
# and deleted. A run is judged once what each of these events set off has run
if ! start slow.yaml; then
  fail "nvim listens on its socket (two windows)" "no socket within 15s"
elif ! wait_for 15000 logged 2; then
  fail "precondition: the stand-in runs on opening slow.yaml (two windows)" "pids logged: $(pids | tr '\n' ' ')"
else
  # fast.yaml opens and lints in a split, and an empty window splits slow.yaml's, to take its space; while fast.yaml's
  # run waits, slow.yaml's window is written and closed
  R --remote-send ":vsplit fast.yaml<CR>:call win_gotoid(bufwinid('slow.yaml'))<CR>:new<CR>:call win_gotoid(bufwinid('slow.yaml'))<CR>:wq<CR>"
  diags='vim.diagnostic.get(vim.fn.bufnr(\"fast.yaml\"), { namespace = require(\"lint\").get_namespace(\"yamllint\") })'
  findings() { [ "$(R --remote-expr "luaeval(\"#$diags\")")" = 1 ]; }
  closed() { [ "$(R --remote-expr 'bufwinid("slow.yaml")')" = -1 ] && [ "$(R --remote-expr 'bufwinid("fast.yaml")')" != -1 ]; }
  if wait_for 5000 closed; then
    pass ":wq closed slow.yaml's window and left fast.yaml's"
  else
    fail ":wq closed slow.yaml's window and left fast.yaml's" "windows: $(R --remote-expr 'winnr("$")'), current: $(R --remote-expr 'bufname()')"
  fi
  touch "$RELEASE"
  if wait_for 10000 findings; then
    if [ "$(wc -l <"$FASTLOG")" = 1 ]; then
      pass "fast.yaml's lint, running at the :wq, still reports its finding"
    else
      fail "precondition: fast.yaml linted once, so its finding comes from the run going at the :wq" "runs: $(wc -l <"$FASTLOG")"
    fi
  else
    fail "fast.yaml's lint, running at the :wq, still reports its finding" "diagnostics: $(R --remote-expr "luaeval(\"vim.inspect($diags)\")" | tr '\n' ' ')"
  fi
  if ! wait_for 5000 logged 4; then
    fail "precondition: the write started a run of slow.yaml" "pids logged: $(pids | tr '\n' ' ')"
  else
    if settled && latest_untouched; then
      pass "closing a window kills no run"
    else
      fail "closing a window kills no run" "slow.yaml's newest run, $(latest | tr '\n' ' '), is gone"
    fi
    R --remote-send ':bunload slow.yaml<CR>'
    unloaded() { [ "$(R --remote-expr 'bufloaded("slow.yaml")')" = 0 ]; }
    if ! wait_for 5000 unloaded; then
      fail "precondition: :bunload unloads slow.yaml" "still loaded"
    elif settled && latest_untouched; then
      pass "unloading a buffer kills no run"
    else
      fail "unloading a buffer kills no run" "slow.yaml's newest run, $(latest | tr '\n' ' '), is gone"
    fi
    R --remote-send ':bdelete slow.yaml<CR>'
    unlisted() { [ "$(R --remote-expr 'buflisted("slow.yaml")')" = 0 ]; }
    if ! wait_for 5000 unlisted; then
      fail "precondition: :bdelete deletes slow.yaml" "still listed"
    elif settled && latest_untouched; then
      pass "deleting a buffer kills no run"
    else
      fail "deleting a buffer kills no run" "slow.yaml's newest run, $(latest | tr '\n' ' '), is gone"
    fi
  fi
fi
finish
reap

# 3. Runs nvim-lint cancelled for a newer one: it sends the run's own pid SIGINT (lint.lua, LintProc:cancel), which ends
# this stand-in and leaves its child. Two writes cancel the run opening the file started and the first write's; once
# both have ended, the quit leaves none of the runs. A run that ignores the SIGINT, nvim-lint SIGKILLs 10 s later, which
# leaves its child the same way; the stand-in ends on the SIGINT so that the check doesn't wait for it
if ! start cancel.yaml; then
  fail "nvim listens on its socket (cancelled runs)" "no socket within 15s"
elif ! wait_for 15000 logged 2; then
  fail "precondition: the stand-in runs on opening cancel.yaml (cancelled runs)" "pids logged: $(pids | tr '\n' ' ')"
else
  R --remote-send ':w<CR>'
  wait_for 5000 logged 4
  R --remote-send ':w<CR>'
  first=$(pids | sed -n 1p) second=$(pids | sed -n 3p)
  if ! wait_for 5000 logged 6; then
    fail "precondition: each write started a run" "pids logged: $(pids | tr '\n' ' ')"
  elif ! wait_for 5000 dead "$first" || ! wait_for 5000 dead "$second"; then
    fail "precondition: nvim-lint's cancel ended the cancelled runs' own pids" "pids logged: $(pids | tr '\n' ' ')"
  else
    R --remote-send ':qa!<CR>'
    wait_for 5000 gone
    if wait_for 3000 none_alive; then
      pass "no process of a cancelled run outlives Neovim"
    else
      left=
      for p in $(pids); do alive "$p" && left="$left $(cat "/proc/$p/comm")($p)"; done
      fail "no process of a cancelled run outlives Neovim" "alive 3s after the quit:$left"
    fi
  fi
fi
finish
reap
out DONE
