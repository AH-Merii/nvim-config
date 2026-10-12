# shellcheck shell=bash
# Shared by suite.sh, nv.sh and gui.sh.
S=${S:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
DEFAULT_CFG=$(cd "$S/../../nvim" && pwd)
CFG=${CFG:-$DEFAULT_CFG}

# make_home <dir>: a copy of $CFG plus state and cache dirs. Data is shared: $S/data, see nv.sh.
make_home() {
  local h=$1
  mkdir -p "$h/config/nvim" "$h/state" "$h/cache"
  cp -a --reflink=auto "$CFG/." "$h/config/nvim/"
  ln -s "$HOME/.config/git" "$h/config/git"
  ln -s "$HOME/.config/mise" "$h/config/mise"
  seed_state "$h/state"
}

# sandbox_env <home>: Go and npm ignore XDG; their download caches are shared by every run (both lock)
sandbox_env() { export GOPATH=$1/go GOMODCACHE=$S/shared-cache/gomod GOFLAGS=-modcacherw npm_config_cache=$S/shared-cache/npm; }

# seed_state <dir>: lazy's checker would git-fetch every plugin when state has no recent check
seed_state() {
  mkdir -p "$1/lazy"
  printf '{"checker":{"last_check":%s}}' "$(date +%s)" >"$1/lazy/state.json"
}

# header <file> <key>: value of a "-- @key value" / "# @key value" line
header() { sed -n -E "s/^(--|#) @$2( +(.*))?$/\3/p" "$1" | head -1; }
has_header() { grep -q -E "^(--|#) @$2( |$)" "$1"; }

# tagged_pids <tag-prefix>: processes whose environment carries NVIM_REGRESS_TAG=<tag-prefix>...
# Tags end in "/", so a full tag never matches another check's tag as a prefix.
tagged_pids() {
  /usr/bin/grep -laF -- "NVIM_REGRESS_TAG=$1" /proc/[0-9]*/environ 2>/dev/null | sed -E 's#^/proc/([0-9]+)/environ$#\1#' | while read -r p; do
    [ "$p" = "$$" ] || [ "$p" = "${BASHPID:-}" ] || echo "$p"
  done
}
# describe_pids <pid...>: "comm(pid)" list
describe_pids() {
  local p c
  for p in "$@"; do c=$(cat "/proc/$p/comm" 2>/dev/null) && printf '%s(%s) ' "$c" "$p"; done
}
# kill_pids <signal> <pid...>
kill_pids() { local sig=$1; shift; [ $# -gt 0 ] && kill "-$sig" "$@" 2>/dev/null; true; }

# inotify_holders: one pid per inotify instance held by this user's processes
inotify_holders() { find /proc/[0-9]*/fd -lname 'anon_inode:inotify' 2>/dev/null | cut -d/ -f3; }

# Copied trees keep absolute paths to their old install: Mason wrappers, shebangs and venvs, and
# nvim-treesitter's query symlinks into lazy/. Any live nvim dir or old sandbox counts.
FOREIGN_RE="$HOME/(\\.local/(share|state)/nvim|\\.config/nvim|\\.cache/nvim|\\.cache/nvim-sbx[^/]*)(/|\$)|/tmp/nvim-sbx"
# the old data dirs that map onto $S/data/nvim/
REPOINT_RE="$HOME/(\\.local/share/nvim|\\.cache/nvim-sbx[^/]*/data/nvim)/"
# foreign_refs: text files and symlinks under data/ that reach outside the sandbox (grep -r skips symlinks)
foreign_refs() {
  find "$S/data" -type f -not -name '*.pyc' -exec /usr/bin/grep -lIE "$FOREIGN_RE" {} + 2>/dev/null
  find "$S/data" -type l -printf '%p\t%l\n' | RE=$FOREIGN_RE awk -F'\t' '$2 ~ ENVIRON["RE"] { print $1 }'
}
repoint_data() {
  foreign_refs | while IFS= read -r f; do
    if [ -L "$f" ]; then ln -sfn "$(readlink "$f" | sed -E "s#$REPOINT_RE#$S/data/nvim/#")" "$f"
    else sed -i -E "s#$REPOINT_RE#$S/data/nvim/#g" "$f"; fi
  done
}
