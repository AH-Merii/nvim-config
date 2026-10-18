#!/usr/bin/env bash
# @desc     no linter run outlives Neovim: :wq with a linter still running exits at once and leaves none of its processes, nor of the runs nvim-lint cancelled; while Neovim runs, closing a window, unloading or deleting a buffer kills no run, and the other buffer's findings still arrive
# @areas    lint
# @budget   60
# A stand-in yamllint in the project's .venv/bin ignores SIGTERM and SIGINT, as a linter busy in a child may. On a
# buffer holding "slow" it logs its pid and its child's and sleeps; on any other it logs its start and reports one
# finding after 2 s.
# nvim runs headless and is driven over its socket, not through the harness: the harness waits up to 15 s for
# nvim-lint's runs before it quits (harness.lua), so a run would end before the quit and no orphan would show.
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
pass() { out "PASS $1"; }
fail() { out "FAIL $1  -- $2"; }

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

LOG=$FIX/standin-pids.log FASTLOG=$FIX/standin-fast.log
mkdir -p "$FIX/.venv/bin"
cat >"$FIX/.venv/bin/yamllint" <<EOF
#!/bin/sh
trap '' TERM INT
input=\$(cat)
case "\$input" in
  *slow*) echo \$\$ >>'$LOG'; sleep 600 & echo \$! >>'$LOG'; wait ;;
  *) echo \$\$ >>'$FASTLOG'; sleep 2; echo 'stdin:1:1: [error] stand-in finding (standin)' ;;
esac
EOF
chmod +x "$FIX/.venv/bin/yamllint"
printf 'slow: 1\n' >"$FIX/slow.yaml"
printf 'fast: 1\n' >"$FIX/fast.yaml"

SOCK=$FIX/.nvim.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-lint-quit-$$.sock
R() { timeout 5 "$NV" "$V" --clean --headless --server "$SOCK" "$@" </dev/null 2>/dev/null; }
pids() { cat "$LOG" 2>/dev/null; }
alive() { local s; s=$(cut -d' ' -f3 "/proc/$1/stat" 2>/dev/null) && [ "$s" != Z ]; }
none_alive() { local p; for p in $(pids); do alive "$p" && return 1; done; return 0; }
# the newest run's pids (a run logs its own and its child's): the one not cancelled, which nvim-lint leaves running
latest() { pids | tail -n 2; }
latest_alive() { local p; for p in $(latest); do alive "$p" || return 1; done; return 0; }
latest_dead() { ! latest_alive; }
dead() { ! alive "$1"; }
logged() { [ "$(pids | wc -l)" -ge "$1" ]; }
started=
start() { # start <file>: nvim on file, its socket up
  rm -f "$SOCK" "$LOG" "$FASTLOG"
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
# runs. The cursor goes to an empty window, not fast.yaml's: entering that one after a write would lint it again (D72),
# cancelling the run. Then slow.yaml, whose newest run still goes, is unloaded and deleted
if ! start slow.yaml; then
  fail "nvim listens on its socket (two windows)" "no socket within 15s"
elif ! wait_for 15000 logged 2; then
  fail "precondition: the stand-in runs on opening slow.yaml (two windows)" "pids logged: $(pids | tr '\n' ' ')"
else
  # fast.yaml opens and lints in a split, and an empty window splits slow.yaml's, to take its space; while fast.yaml's
  # run sleeps, slow.yaml's window is written and closed
  R --remote-send ":vsplit fast.yaml<CR>:call win_gotoid(bufwinid('slow.yaml'))<CR>:new<CR>:call win_gotoid(bufwinid('slow.yaml'))<CR>:wq<CR>"
  diags='vim.diagnostic.get(vim.fn.bufnr(\"fast.yaml\"), { namespace = require(\"lint\").get_namespace(\"yamllint\") })'
  findings() { [ "$(R --remote-expr "luaeval(\"#$diags\")")" = 1 ]; }
  closed() { [ "$(R --remote-expr 'bufwinid("slow.yaml")')" = -1 ] && [ "$(R --remote-expr 'bufwinid("fast.yaml")')" != -1 ]; }
  if wait_for 5000 closed; then
    pass ":wq closed slow.yaml's window and left fast.yaml's"
  else
    fail ":wq closed slow.yaml's window and left fast.yaml's" "windows: $(R --remote-expr 'winnr("$")'), current: $(R --remote-expr 'bufname()')"
  fi
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
    # a kill reaches the run within ms of the event; a second is plenty to see one
    if latest_alive && ! wait_for 1000 latest_dead; then
      pass "closing a window kills no run"
    else
      fail "closing a window kills no run" "slow.yaml's newest run, $(latest | tr '\n' ' '), is gone"
    fi
    R --remote-send ':bunload slow.yaml<CR>'
    unloaded() { [ "$(R --remote-expr 'bufloaded("slow.yaml")')" = 0 ]; }
    if ! wait_for 5000 unloaded; then
      fail "precondition: :bunload unloads slow.yaml" "still loaded"
    elif latest_alive && ! wait_for 1000 latest_dead; then
      pass "unloading a buffer kills no run"
    else
      fail "unloading a buffer kills no run" "slow.yaml's newest run, $(latest | tr '\n' ' '), is gone"
    fi
    R --remote-send ':bdelete slow.yaml<CR>'
    unlisted() { [ "$(R --remote-expr 'buflisted("slow.yaml")')" = 0 ]; }
    if ! wait_for 5000 unlisted; then
      fail "precondition: :bdelete deletes slow.yaml" "still listed"
    elif latest_alive && ! wait_for 1000 latest_dead; then
      pass "deleting a buffer kills no run"
    else
      fail "deleting a buffer kills no run" "slow.yaml's newest run, $(latest | tr '\n' ' '), is gone"
    fi
  fi
fi
finish
reap

# 3. Runs nvim-lint cancelled for a newer one: it sends SIGINT, which the stand-in ignores, and SIGKILLs the run's own
# pid 10 s later (lint.lua, LintProc:cancel), which leaves its child. Two writes cancel the run opening the file started
# and the first write's; once nvim-lint has killed both, the quit leaves none of the runs
if ! start slow.yaml; then
  fail "nvim listens on its socket (cancelled runs)" "no socket within 15s"
elif ! wait_for 15000 logged 2; then
  fail "precondition: the stand-in runs on opening slow.yaml (cancelled runs)" "pids logged: $(pids | tr '\n' ' ')"
else
  R --remote-send ':w<CR>'
  wait_for 5000 logged 4
  R --remote-send ':w<CR>'
  first=$(pids | sed -n 1p) second=$(pids | sed -n 3p)
  if ! wait_for 5000 logged 6; then
    fail "precondition: each write started a run" "pids logged: $(pids | tr '\n' ' ')"
  elif ! wait_for 15000 dead "$first" || ! wait_for 5000 dead "$second"; then
    fail "precondition: nvim-lint killed the cancelled runs' own pids" "pids logged: $(pids | tr '\n' ' ')"
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
