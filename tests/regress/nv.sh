#!/usr/bin/env bash
# usage: nv.sh nightly [nvim args...]
# Runs the sandboxed nvim. NVR_HOME holds config/ state/ cache/, NVR_DATA the data dir (default: the
# suite's data/). Without NVR_HOME a scratch home is built from $CFG and removed on exit.
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
case "$1" in
  nightly) BIN=$HOME/.local/share/mise/installs/neovim/nightly/bin/nvim ;;
  *) echo "usage: nv.sh nightly [nvim args...]" >&2; exit 2 ;;
esac
shift

# the live Mason bin and any other live nvim dir on the login PATH would hide sandbox tools
PATH=$(printf %s "$PATH" | tr ':' '\n' | grep -v -E "^$HOME/(\.local/share/nvim|\.local/state/nvim|\.config/nvim|\.cache/nvim)(/|$)" | paste -sd:)
export PATH=$HOME/.local/share/mise/installs/tree-sitter/0.27.0:$PATH
# temporary, until the tools branch lands and gopls comes from Mason (then --refresh installs it there)
PATH=$S/bin:$PATH
# mise shims fail under the sandbox state dir (mise's trust state is in the live one); real tool dirs go first
M=$HOME/.local/share/mise/installs
PATH=$M/go/latest/bin:$M/node/lts/bin:$HOME/.cargo/bin:$PATH
export MISE_DATA_DIR=$HOME/.local/share/mise
# the user's git config sets core.fsmonitor=true; every git run in a plugin dir would leave a daemon
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
export NVIM_REGRESS_TAG=${NVIM_REGRESS_TAG:-manual-$$/}
unset NVIM NVIM_LISTEN_ADDRESS NVIM_APPNAME NVIM_LOG_FILE VIMINIT MYVIMRC
# clipboard=unnamedplus would run wl-copy/xclip against the user's real clipboard, and leak them
unset WAYLAND_DISPLAY DISPLAY
# shellcheck source=lib.sh
. "$S/lib.sh"

if [ -z "${NVR_HOME:-}" ]; then
  mkdir -p "$S/run"; NVR_HOME=$(mktemp -d "$S/run/manual.XXXXXX")
  trap 'rm -rf "$NVR_HOME"' EXIT
  make_home "$NVR_HOME"
  export NVR_HOME
  sandbox_env "$NVR_HOME"
  XDG_CONFIG_HOME=$NVR_HOME/config XDG_DATA_HOME=${NVR_DATA:-$S/data} XDG_STATE_HOME=$NVR_HOME/state \
    XDG_CACHE_HOME=$NVR_HOME/cache "$BIN" "$@"
  exit
fi
export XDG_CONFIG_HOME=$NVR_HOME/config XDG_DATA_HOME=${NVR_DATA:-$S/data} XDG_STATE_HOME=${NVR_STATE:-$NVR_HOME/state} XDG_CACHE_HOME=$NVR_HOME/cache
sandbox_env "$NVR_HOME"
exec "$BIN" "$@"
