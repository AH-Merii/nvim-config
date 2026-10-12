#!/usr/bin/env bash
# usage: seed.sh <clone dir> <with-skill 0|1>
# Makes a fresh clone of the nvimt2/mise-tooling branch for one eval run:
#   - the committed files of the branch (git clone of the main repo; pushing from the clone is disabled);
#   - the regression suite's data and cache seed from the nvimt2 worktree (reflink copies, cheap on btrfs), so the
#     suite runs without a 15-minute --refresh;
#   - with 1: the language-tools skill, copied from the worktree, so uncommitted edits are what gets tested.
# The clone dir must be under $SEED_ROOT (default ~/.cache/skill-eval), because it is deleted first.
set -euo pipefail
[ $# -eq 2 ] && [[ $2 == [01] ]] || { echo "usage: seed.sh <clone dir> <with-skill 0|1>" >&2; exit 2; }
SRC=/home/a_merii/Projects/nvim-config-t2
REPO=/home/a_merii/Projects/nvim-config
BRANCH=nvimt2/mise-tooling
ROOT=$(realpath -m "${SEED_ROOT:-$HOME/.cache/skill-eval}")
DIR=$(realpath -m "$1")
case "$DIR/" in
  "$ROOT"/?*/) ;;
  *) echo "seed.sh: refusing $DIR: it must be inside $ROOT (set SEED_ROOT to change)" >&2; exit 2 ;;
esac
export TMPDIR=${TMPDIR:-$HOME/.cache/skill-eval/tmp}
mkdir -p "$TMPDIR"

rm -rf "$DIR"
mkdir -p "$(dirname "$DIR")"
git clone -q --branch "$BRANCH" "$REPO" "$DIR"
# an agent in the clone must never reach the user's repo
git -C "$DIR" remote set-url --push origin "file:///nonexistent/push-disabled"
mkdir -p "$DIR/tests/regress"
cp -a --reflink=auto "$SRC/tests/regress/data" "$DIR/tests/regress/"
cp -a --reflink=auto "$SRC/tests/regress/cache-seed" "$DIR/tests/regress/"
# parser query symlinks point into the worktree's data; point them at the clone's own copy
find "$DIR/tests/regress/data" -type l -lname "$SRC/*" -printf '%p\t%l\n' | while IFS=$'\t' read -r link target; do
  ln -sfn "$DIR${target#"$SRC"}" "$link"
done
if [ "$2" = 1 ]; then
  mkdir -p "$DIR/.claude/skills"
  cp -a "$SRC/.claude/skills/language-tools" "$DIR/.claude/skills/"
fi
# the user's real mise before the run; lib.sh's gate compares against it (keep in sync with lib.sh mise_state)
echo "$(sha256sum "$(readlink -f "$HOME/.config/mise/config.toml")" | cut -d' ' -f1)" \
  "$(ls "$HOME/.local/share/mise/installs" | sort | md5sum | cut -d' ' -f1)" >"$DIR/.git/eval-mise-state"
echo "seeded $DIR (with skill: $2) at $(git -C "$DIR" rev-parse --short HEAD)"
