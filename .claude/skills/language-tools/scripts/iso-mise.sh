#!/usr/bin/env bash
# usage: iso-mise.sh <dir> <command...>
# Runs <command> with a mise that is fully isolated in <dir>: its own data, cache, state and global config.
# The user's ~/.config/mise and ~/.local/share/mise are never read or written. Reuse the same <dir> across calls
# (install, then exec); delete it with `rm -rf <dir>` when done. The command runs with <dir> as its cwd.
set -euo pipefail
if [ $# -lt 2 ]; then
  echo "usage: iso-mise.sh <dir> <command...>   (make the dir with: mkdir -p ~/.cache/language-tools && mktemp -d -p ~/.cache/language-tools)" >&2
  exit 2
fi
T=$1
shift
# Scratch goes on disk: /tmp is a RAM-backed tmpfs on this machine, and tool installs fill it fast.
# Any absolute dir works except the user's own mise dirs, which this script exists to protect.
case "$T" in
  /?*) ;;
  *) echo "iso-mise.sh: refusing $T: give an absolute path (mktemp -d -p ~/.cache/language-tools)" >&2; exit 2 ;;
esac
T=$(realpath -m "$T")
for real in "$HOME/.config/mise" "$HOME/.local/share/mise" "$HOME/.local/state/mise" "$HOME/.cache/mise"; do
  case "$T/" in "$real"/*) echo "iso-mise.sh: refusing $T: it is inside the user's mise ($real)" >&2; exit 2 ;; esac
done
mkdir -p "$T/config" "$T/tmp"
# tools' own temp files stay in <dir> too
export TMPDIR=$T/tmp
# The caller's shell may be mise-activated (MISE_SHELL, __MISE_DIFF, ...); none of that may leak in
for v in $(compgen -e); do [[ $v =~ ^_*MISE_ ]] && unset "$v"; done
# The nightly nvim, asked of the user's mise before it is isolated below
if NVIM_DIR=$(cd "$HOME" && mise where github:neovim/neovim@nightly 2>/dev/null) && [ -x "$NVIM_DIR/bin/nvim" ]; then
  export NVIM_BIN=$NVIM_DIR/bin/nvim
else
  echo "iso-mise.sh: NVIM_BIN is unset: mise has no github:neovim/neovim@nightly (mise install github:neovim/neovim@nightly)" >&2
fi
export MISE_DATA_DIR=$T/data MISE_CACHE_DIR=$T/cache MISE_STATE_DIR=$T/state \
  MISE_CONFIG_DIR=$T/config MISE_GLOBAL_CONFIG_FILE=$T/config/config.toml
# Without this, mise reads ~/.config/mise/config.toml as a project config of $HOME
export MISE_CEILING_PATHS=$HOME
export MISE_YES=1
# Drop the user's mise installs and shims and the old Mason bin dir, so nothing answers from the real setup
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '/mise/' -e '/mason/bin' | paste -sd:)
export PATH
# mise itself must stay reachable
command -v mise >/dev/null || { echo "iso-mise.sh: mise is not on PATH after stripping" >&2; exit 2; }
# nvim lives in the user's mise installs, which were stripped above; NVIM_BIN gives it back by absolute path
cd "$T"
exec "$@"
