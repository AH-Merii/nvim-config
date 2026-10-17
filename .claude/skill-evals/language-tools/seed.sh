#!/usr/bin/env bash
# usage: seed.sh <clone dir> <with-skill 0|1>
# Makes a fresh clone for one eval run, from the checkout these scripts live in (SRC):
#   - the committed files of SRC's branch, or of $EVAL_BRANCH (git clone; pushing from the clone is disabled);
#   - the regression suite's data and cache seed from SRC (reflink copies, cheap on btrfs), so the suite runs without
#     a 15-minute --refresh;
#   - with 1: the language-tools skill, copied from SRC, so uncommitted edits are what gets tested.
# The clone dir must be under $SEED_ROOT (default ~/.cache/skill-eval), because it is deleted first.
set -euo pipefail
[ $# -eq 2 ] && [[ $2 == [01] ]] || { echo "usage: seed.sh <clone dir> <with-skill 0|1>" >&2; exit 2; }
SRC=$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)
BRANCH=${EVAL_BRANCH:-$(git -C "$SRC" branch --show-current)}
[ -n "$BRANCH" ] || { echo "seed.sh: $SRC has no branch checked out; set EVAL_BRANCH" >&2; exit 2; }
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
git clone -q --branch "$BRANCH" "$SRC" "$DIR"
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
# the branch the clone starts from; lib.sh's base() diffs against it
echo "$BRANCH" >"$DIR/.git/eval-branch"
echo "seeded $DIR (with skill: $2) at $(git -C "$DIR" rev-parse --short HEAD)"
