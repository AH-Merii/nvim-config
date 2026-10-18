#!/usr/bin/env bash
# usage: nvr-test [all | unit [run.sh args] | suite [suite.sh args] | <command...>]
# The test image's entrypoint. Copies the checkout mounted at /src (read-only is fine) into /work, beside the
# image's tests/regress/data, then runs: `unit` tests/unit/run.sh, `suite` tests/regress/suite.sh, `all` (the
# default) both, anything else as a command. When /out is mounted, the suite's last/ is copied there at the end.
set -u
SRC=/src W=/work
[ -f "$SRC/nvim/init.lua" ] || { echo "nvr-test: no checkout at $SRC; run with -v \"\$PWD:$SRC:ro\"" >&2; exit 2; }

# only the config, the tests and docs/ (languages_doc_test renders docs/languages.md); the checkout's own sandbox, results and run state stay out
tar -C "$SRC" -cf - --exclude=tests/regress/data --exclude=tests/regress/run --exclude=tests/regress/last \
  --exclude=tests/regress/state --exclude=tests/regress/bin --exclude=tests/regress/cache-seed \
  --exclude=tests/regress/shared-cache nvim tests docs | tar -C "$W" -xf - || exit 2

# data/ holds the plugins and parsers of the config the image was built from
sum=$(cd "$W" && find nvim -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
[ "$sum" = "$(cat "$W/.image-config.sum" 2>/dev/null)" ] ||
  echo "nvr-test: WARNING: nvim/ differs from the config this image was built from; rebuild it (mise run test:image:build)" >&2

cd "$W" || exit 2
case "${1:-all}" in
  unit) shift; tests/unit/run.sh "$@"; rc=$? ;;
  suite) shift; tests/regress/suite.sh "$@"; rc=$? ;;
  all) tests/unit/run.sh; rc=$?; tests/regress/suite.sh || rc=1 ;;
  *) exec "$@" ;;
esac
if [ -d /out ] && [ -d tests/regress/last ]; then cp -a tests/regress/last/. /out/ || echo "nvr-test: could not copy last/ to /out" >&2; fi
exit "$rc"
