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
  # mise's config dir stays empty: the global config is the suite's own (see mise_env)
  mkdir -p "$h/config/mise"
  seed_state "$h/state"
}

# sandbox_env <home>: Go and npm ignore XDG; their download caches are shared by every run (both lock)
sandbox_env() { export GOPATH=$1/go GOMODCACHE=$S/shared-cache/gomod GOFLAGS=-modcacherw npm_config_cache=$S/shared-cache/npm; }

# The suite's own mise and rustup: every tool a check needs comes from here, never from the user's mise.
# suite.sh --refresh fills them (`mise use -g` into MISE_GLOBAL_CONFIG_FILE, `rustup component add` into RUSTUP_HOME).
# Used in place, not copied per run: checks never install (headless, so tools.can_install() is false).
SUITE_MISE=${NVR_MISE:-$S/data/mise}
SUITE_RUSTUP=$S/data/rustup
# mise_env <home>: every MISE_* var points into the sandbox. The user's shell exports its own (MISE_SHELL,
# __MISE_DIFF, __MISE_ORIG_PATH...), which describe the live mise session; none may reach a check.
mise_env() {
  local v
  for v in $(compgen -e); do [[ $v =~ ^_*MISE_ ]] && unset "$v"; done
  export MISE_DATA_DIR=$SUITE_MISE/data MISE_GLOBAL_CONFIG_FILE=$SUITE_MISE/config.toml MISE_CONFIG_DIR=$1/config/mise \
    MISE_STATE_DIR=${NVR_STATE:-$1/state}/mise MISE_CACHE_DIR=$1/cache/mise
  # With MISE_CONFIG_DIR moved, mise takes the user's ~/.config/mise/config.toml for a project config of $HOME,
  # found walking up from any fixture, and refuses every call there as untrusted; $HOME is not a project
  export MISE_CEILING_PATHS=$HOME
  # a query must never install behind the check's back
  export MISE_AUTO_INSTALL=0 MISE_EXEC_AUTO_INSTALL=0 MISE_NOT_FOUND_AUTO_INSTALL=0 MISE_TASK_RUN_AUTO_INSTALL=0
  if [ -d "$SUITE_RUSTUP" ]; then export RUSTUP_HOME=$SUITE_RUSTUP; fi
}

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

# Copied trees keep absolute paths to their old install: tool shebangs and venvs, and
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
