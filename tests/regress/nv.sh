#!/usr/bin/env bash
# usage: nv.sh nightly [nvim args...]
# Runs the sandboxed nvim. NVR_HOME holds config/ state/ cache/, NVR_DATA the data dir (default: the
# suite's data/). Without NVR_HOME a scratch home is built from $CFG and removed on exit.
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
. "$S/lib.sh"
case "$1" in
  # NVR_NVIM: another build, e.g. the test image's pinned nightly (tests/image/Dockerfile). Exported, so an nv.sh
  # a check starts runs the same build without asking mise, which can't answer inside the sandbox's XDG dirs
  nightly)
    BIN=${NVR_NVIM:-}
    [ -n "$BIN" ] || BIN=$(nvim_build nightly)/bin/nvim || { echo "or set NVR_NVIM to an nvim binary" >&2; exit 2; }
    export NVR_NVIM=$BIN ;;
  *) echo "usage: nv.sh nightly [nvim args...]" >&2; exit 2 ;;
esac
shift

# Live nvim dirs on the login PATH (an old Mason bin among them) would hide sandbox tools, and mise shims
# would answer from the sandbox's mise config, so both go. Tools reach Neovim through the resolver
# (lua/tools), which ignores PATH entries inside mise installs anyway; those stay, as in the user's own nvim.
PATH=$(printf %s "$PATH" | tr ':' '\n' | grep -v -E "^$HOME/(\.local/share/nvim|\.local/state/nvim|\.config/nvim|\.cache/nvim)(/|$)|/mason/bin/?$|/mise/shims/?$" | paste -sd:)
# nvim-treesitter builds parsers with the tree-sitter CLI
export PATH=$HOME/.local/share/mise/installs/tree-sitter/0.27.0:$PATH
# the user's git config sets core.fsmonitor=true; every git run in a plugin dir would leave a daemon
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
export NVIM_REGRESS_TAG=${NVIM_REGRESS_TAG:-manual-$$/}
unset NVIM NVIM_LISTEN_ADDRESS NVIM_APPNAME NVIM_LOG_FILE VIMINIT MYVIMRC
# clipboard=unnamedplus would run wl-copy/xclip against the user's real clipboard, and leak them
unset WAYLAND_DISPLAY DISPLAY

if [ -z "${NVR_HOME:-}" ]; then
  mkdir -p "$RUNS"; NVR_HOME=$(mktemp -d "$RUNS/manual.XXXXXX")
  trap 'rm -rf "$NVR_HOME"' EXIT
  make_home "$NVR_HOME"
  export NVR_HOME
  sandbox_env "$NVR_HOME"
  mise_env "$NVR_HOME"
  XDG_CONFIG_HOME=$NVR_HOME/config XDG_DATA_HOME=${NVR_DATA:-$S/data} XDG_STATE_HOME=$NVR_HOME/state \
    XDG_CACHE_HOME=$NVR_HOME/cache "$BIN" "$@"
  exit
fi
export XDG_CONFIG_HOME=$NVR_HOME/config XDG_DATA_HOME=${NVR_DATA:-$S/data} XDG_STATE_HOME=${NVR_STATE:-$NVR_HOME/state} XDG_CACHE_HOME=$NVR_HOME/cache
sandbox_env "$NVR_HOME"
mise_env "$NVR_HOME"
exec "$BIN" "$@"
