#!/usr/bin/env bash
# usage: test-inputs.sh <event> [<before>]
# Whether a run of .github/workflows/test.yml has anything to test: prints the changed files and writes
# tests=true or tests=false to $GITHUB_OUTPUT (stdout when unset). tests=false only when every changed file is
# one the image build and the tests never read (docs/test-image-decisions.md, D148); anything else, a new path
# included, and any doubt (an unknown event, a base it can't fetch, a failed diff) runs the tests.
#   pull_request  the checked-out merge commit against its first parent, the base branch's tip
#   push          HEAD against <before>, the commit the push moved the branch from
set -uo pipefail
out=${GITHUB_OUTPUT:-/dev/stdout}
decide() { echo "tests=$1" >>"$out"; echo "$2"; exit 0; }

# The build context is nvim/ and tests/ (/.dockerignore); the entrypoint also copies docs/, whose languages.md
# and languages.lua the unit tier reads (tests/unit/languages_doc_test.lua). CI runs mise-tasks/test/image/_default
# and the workflows in .github/.
not_input() {
  case $1 in
    docs/languages.md | docs/languages.lua) return 1 ;;
    docs/* | .claude/* | .githooks/*) return 0 ;;
    CHANGELOG.md | .release-please-manifest.json | release-please-config.json | version.txt) return 0 ;;
    README.md | CONTRIBUTING.md | AGENTS.md | CLAUDE.md | LICENSE | .gitignore) return 0 ;;
    *) return 1 ;;
  esac
}

case ${1:-} in
  pull_request) base=HEAD^1 ;;
  push)
    before=${2:-}
    [[ $before =~ ^[0-9a-f]{40}$ && ! $before =~ ^0+$ ]] || decide true "no previous commit to compare with: run"
    git cat-file -e "$before^{commit}" 2>/dev/null || git fetch -q --no-tags --depth=1 origin "$before" ||
      decide true "can't fetch $before: run"
    base=$before
    ;;
  *) decide true "event ${1:-none}: run" ;;
esac

files=$(git diff --name-only --no-renames "$base" HEAD) || decide true "git diff $base HEAD failed: run"
echo "changed files against $base:"
echo "${files:-(none)}"
while IFS= read -r f; do
  [ -z "$f" ] || not_input "$f" || decide true "$f is a test input: run"
done <<<"$files"
decide false "no test input changed: skip"
