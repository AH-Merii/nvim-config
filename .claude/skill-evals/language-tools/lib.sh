# shellcheck shell=bash
# Shared by the check-*.sh scripts. Sourced with C (the clone dir) and ID (the eval id) set.
EV=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export TMPDIR=$HOME/.cache/skill-eval/tmp
mkdir -p "$TMPDIR"
# keep in sync with seed.sh
mise_state() {
  echo "$(sha256sum "$(readlink -f "$HOME/.config/mise/config.toml")" | cut -d' ' -f1)" \
    "$(ls "$HOME/.local/share/mise/installs" | sort | md5sum | cut -d' ' -f1)"
}
CAP=(systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=512M --)
SCRATCH=$(mktemp -d -p "$TMPDIR" "check-$ID.XXXXXX")
trap 'rm -rf "$SCRATCH"; rm -rf "$C/tests/regress/work/eval-$ID"' EXIT

[ -d "$C/nvim" ] && [ -x "$C/tests/regress/nv.sh" ] || { echo "usage: $0 <clone dir>" >&2; exit 2; }
C=$(cd "$C" && pwd)
# the branch seed.sh cloned
BRANCH=$(cat "$C/.git/eval-branch" 2>/dev/null || echo main)

result() { # result <ok 0|1> <what> <evidence>
  local s=FAIL
  [ "$1" = 1 ] && s=PASS
  printf '%s %s %s -- %s\n' "$s" "$ID" "$2" "$(printf '%s' "$3" | tr '\n\t' ' ' | cut -c1-400)"
}

wait_mem() {
  while [ "$(awk '/^MemAvailable/ {print $2}' /proc/meminfo)" -lt 3000000 ]; do
    echo "($ID: MemAvailable under 3 GB, waiting 30s)" >&2
    sleep 30
  done
}

# probe <files...>: the probe's facts for the clone's config, FILES classified from a scratch cwd
probe() {
  local d
  d=$(mktemp -d -p "$SCRATCH" probe.XXXX)
  wait_mem
  (cd "$d" && env -u CFG -u NVR_HOME -u NVR_DATA FILES="$*" timeout 90 "${CAP[@]}" "$C/tests/regress/nv.sh" nightly --headless \
    -c "luafile $EV/probe.lua" 2>&1)
}
# field <line> <key>: the value of key=value in a probe line
field() { printf '%s\n' "$1" | tr '\t' '\n' | sed -n "s/^$2=//p" | head -1; }
# has <comma list> <name>
has() { [[ ",$1," == *",$2,"* ]]; }

# A mise isolated in the scratch dir, for read-only queries (never the user's mise)
iso_mise() {
  (
    for v in $(compgen -e); do [[ $v =~ ^_*MISE_ ]] && unset "$v"; done
    export MISE_DATA_DIR=$SCRATCH/iso/data MISE_CACHE_DIR=$HOME/.cache/skill-eval/mise-cache MISE_STATE_DIR=$SCRATCH/iso/state \
      MISE_CONFIG_DIR=$SCRATCH/iso/config MISE_GLOBAL_CONFIG_FILE=$SCRATCH/iso/config/config.toml MISE_CEILING_PATHS=$HOME MISE_YES=1
    mkdir -p "$SCRATCH/iso/config"
    cd "$SCRATCH" && timeout 120 mise "$@"
  )
}

# suite_install <spec...>: install into the clone's own suite mise (tests/regress/data/mise), as suite.sh --refresh does
suite_install() {
  wait_mem
  (
    for v in $(compgen -e); do [[ $v =~ ^_*MISE_ ]] && unset "$v"; done
    export MISE_DATA_DIR=$C/tests/regress/data/mise/data MISE_GLOBAL_CONFIG_FILE=$C/tests/regress/data/mise/config.toml \
      MISE_CONFIG_DIR=$SCRATCH/suite-mise/config MISE_STATE_DIR=$SCRATCH/suite-mise/state \
      MISE_CACHE_DIR=$HOME/.cache/skill-eval/mise-cache MISE_CEILING_PATHS=$HOME MISE_YES=1
    mkdir -p "$SCRATCH/suite-mise/config"
    cd "$SCRATCH" && timeout 170 "${CAP[@]}" mise use -g "${@/%/@latest}" 2>&1 | tail -3
  )
}

# suite <suite.sh args...>: run the clone's suite on its own data, capped; prints the log
suite() {
  wait_mem
  (cd "$C/tests/regress" && env -u CFG timeout 170 "${CAP[@]}" ./suite.sh "$@" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
}
# suite_status <log> <check>: PASS, FAIL or MISSING for one check of a suite log
suite_status() { awk -v c="$2" '$1 ~ /^(PASS|FAIL)$/ && $3 == c { print $1; f=1 } END { if (!f) print "MISSING" }' <<<"$1" | head -1; }
# suite_ok <log> <check...>: every named check PASSed and the suite left the user's mise alone. The other hygiene lines
# (live nvim dirs, inotify) also see the user's own editor and other sessions, so they don't decide an eval check.
suite_ok() {
  local log=$1 c
  shift
  grep -qF "PASS the user's mise config, mise installs and rustup toolchains unchanged" <<<"$log" || return 1
  for c in "$@"; do [ "$(suite_status "$log" "$c")" = PASS ] || return 1; done
}
# suite_reasons <log> <check>: the reason lines under a check's result line
suite_reasons() { awk -v c="$2" '$3 == c && $1 ~ /^(PASS|FAIL)$/ { on=1; next } on && /^       / { print; next } { on=0 }' <<<"$1" | head -4; }

# live <check files...>: run eval-owned checks (live/<id>/) in the clone's suite as a work dir, then remove them
live() {
  local w=$C/tests/regress/work/eval-$ID
  rm -rf "$w"
  mkdir -p "$w"
  cp "$@" "$w/"
  suite --work "eval-$ID"
}

# languages_doc: the clone's own test that docs/languages.md is what `mise run docs` renders; prints run.sh's output and
# fails while the file is out of date
languages_doc() { (cd "$C" && TMPDIR=$SCRATCH timeout 60 tests/unit/run.sh languages_doc 2>&1); }
# languages_row <text>: the rows of docs/languages.md's "Tools by language" table whose Filetypes cell contains the text,
# e.g. `zig`
languages_row() {
  awk -F' [|] ' -v t="$1" '/^## / { on = ($0 == "## Tools by language") } on && /^\| / && index($2, t) { print }' "$C/docs/languages.md" 2>/dev/null
}

# section <file> <heading prefix>: the lines of a markdown "## " section
section() { awk -v h="## $2" 'index($0, h) == 1 { on=1; next } on && /^## / { exit } on' "$1"; }

base() { git -C "$C" merge-base HEAD "origin/$BRANCH" 2>/dev/null || git -C "$C" rev-parse HEAD; }
# changed_lua: Lua files under nvim/ changed since the branch, or new
changed_lua() {
  {
    git -C "$C" diff --name-only "$(base)" -- 'nvim/*.lua'
    git -C "$C" ls-files --others --exclude-standard -- 'nvim/*.lua'
  } | sort -u | while read -r f; do [ -f "$C/$f" ] && echo "$f"; done
}

check_stylua() {
  local st=$C/tests/regress/data/mise/data/installs/stylua/latest/stylua files out
  mapfile -t files < <(changed_lua)
  if [ ${#files[@]} = 0 ]; then
    result 0 "changed Lua passes stylua --check" "no Lua file under nvim/ changed since $(base | cut -c1-7)"
    return
  fi
  if out=$(cd "$C" && "$st" --check "${files[@]}" 2>&1); then
    result 1 "changed Lua passes stylua --check" "$($st --version): ${files[*]}"
  else
    result 0 "changed Lua passes stylua --check" "$(printf '%s' "$out" | grep -m3 -E '^Diff in|^-|^\+' | paste -sd' ')"
  fi
}

# The user's real mise as seed.sh recorded it before the run (seed.sh mise_state). Another session that installs
# a tool during the run also flips the gate, so check a TOUCHED against the run's own commands.
gate() {
  local sha md5 MISE_CONFIG_SHA MISE_INSTALLS_MD5
  read -r MISE_CONFIG_SHA MISE_INSTALLS_MD5 2>/dev/null <"$C/.git/eval-mise-state" || { echo "GATE env TOUCHED -- no $C/.git/eval-mise-state; reseed"; return; }
  read -r sha md5 < <(mise_state)
  if [ "$sha" = "$MISE_CONFIG_SHA" ] && [ "$md5" = "$MISE_INSTALLS_MD5" ]; then
    echo "GATE env OK -- config sha256 $sha, installs md5 $md5"
  else
    echo "GATE env TOUCHED -- config sha256 $sha (want $MISE_CONFIG_SHA), installs md5 $md5 (want $MISE_INSTALLS_MD5)"
  fi
}
