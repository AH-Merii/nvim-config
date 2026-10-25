#!/usr/bin/env bash
# @desc     path completion lists `./` and `../` from the file's folder, any other relative path (`src/`, quoted too) from the project root, an absolute path as typed, a URL not at all; in a buffer that isn't a file, from the cwd's project
# @areas    completion
# @budget   40
# Typed into a headless nvim over its socket: blink completes from insert mode, which a check body can't stay in
# (nvim_feedkeys with "x!" waits for more keys). The fixture's root is the project root (go.mod, pyproject.toml,
# package.json); sub/ is a folder inside it, and both hold a src/ with a different file.
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

mkdir -p "$FIX/src" "$FIX/sub/src"
: >"$FIX/src/root_src_file.txt"
: >"$FIX/sub/src/sub_src_file.txt"
: >"$FIX/sub/sibling.txt"
: >"$FIX/sub/note.txt"

SOCK=$FIX/.nvim.sock
[ ${#SOCK} -gt 100 ] && SOCK=${TMPDIR:-/tmp}/nvr-completion-path-$$.sock
# The client: the binary nv.sh runs, called straight and in the check's own XDG dirs, as nv.sh would run it; in the
# live ones it writes ~/.local/state/nvim/logs/nvim.log, which the suite's hygiene check fails (lint_quit_kill.sh)
BIN=$("$NV" "$V" --clean --headless --cmd 'lua io.stdout:write(vim.v.progpath)' --cmd 'qa!' </dev/null 2>/dev/null)
R() {
  XDG_CONFIG_HOME=$NVR_HOME/config XDG_DATA_HOME=$NVR_DATA XDG_STATE_HOME=$NVR_STATE XDG_CACHE_HOME=$NVR_HOME/cache \
    timeout 5 "$BIN" --clean --headless --server "$SOCK" "$@" </dev/null 2>/dev/null
}
"$NV" "$V" --headless --listen "$SOCK" sub/note.txt </dev/null >/dev/null 2>&1 &
started=$!
trap 'R --remote-send "<C-\\><C-n>:qa!<CR>" >/dev/null; wait_for 5000 eval "! kill -0 $started 2>/dev/null" || kill -KILL $started 2>/dev/null' EXIT
# blink is set up in the startup phase; its path source needs the buffer's FileType done too
ready() { [ "$(R --remote-expr "luaeval(\"package.loaded['blink.cmp'] and 1 or 0\")")" = 1 ]; }
if ! wait_for 20000 ready; then
  fail "nvim starts with blink.cmp" "no blink.cmp within 20s"
  out DONE
  exit 0
fi

# the path source's labels for the current completion, space separated with a space at each end
listed() { printf ' %s ' "$(R --remote-expr 'luaeval("table.concat(vim.tbl_map(function(i) return i.label end, vim.tbl_filter(function(i) return i.source_id == \"path\" end, require(\"blink.cmp\").get_items())), \" \")")')"; }
# listing <name> <typed> <label it lists> [<label it must not list>]: types at the end of an emptied line
listing() {
  local name=$1 typed=$2 want=$3 not=${4:-}
  R --remote-send "<C-\\><C-n>S$typed" >/dev/null
  has() { local l; l=$(listed); [[ $l == *" $want "* ]] && { [ -z "$not" ] || [[ $l != *" $not "* ]]; }; }
  if wait_for 3000 has; then pass "$name"; else fail "$name" "typed '$typed', listed:$(listed)"; fi
}

listing "./ lists the file's folder" "./" sibling.txt app.py
listing "../ lists the folder above the file's" "../" app.py sibling.txt
listing "./src/ is the file's folder's src" "./src/" sub_src_file.txt root_src_file.txt
listing "src/ lists the project root's src, not the file's folder's" "src/" root_src_file.txt sub_src_file.txt
listing "a quoted \"src/ lists the project root's too" '"src/' root_src_file.txt sub_src_file.txt
listing "an absolute path lists that folder" "$FIX/sub/src/" sub_src_file.txt root_src_file.txt
# a URL: a path listing would come within the 3s the cases above wait for theirs
R --remote-send "<C-\\><C-n>Shttps://example.org/" >/dev/null
nothing() { [ "$(listed)" = "  " ]; }
if wait_for 3000 eval '! nothing' ; then fail "a URL lists no files" "listed:$(listed)"; else pass "a URL lists no files"; fi

R --remote-send "<C-\\><C-n>:enew<CR>:setlocal buftype=nofile<CR>" >/dev/null
listing "in a buffer that isn't a file, src/ lists the cwd's project's src" "src/" root_src_file.txt
listing "in a buffer that isn't a file, ./ lists the cwd" "./" app.py

errors=$(R --remote-expr 'luaeval("table.concat(vim.tbl_filter(function(l) return l:match(\"^E%d+\") or l:match(\"rror\") end, vim.split(vim.fn.execute(\"messages\"), \"\\n\")), \" / \")")')
if [ -z "$errors" ]; then pass ":messages holds no error"; else fail ":messages holds no error" "$errors"; fi
out DONE
