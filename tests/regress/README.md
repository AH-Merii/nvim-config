# nvim-regress

One rerunnable regression suite for the Neovim config, on stable 0.12.5 and nightly 0.13-dev.
Nothing here edits the config under test, the repo, or the live `~/.config/nvim`,
`~/.local/share/nvim`, `~/.local/state/nvim` and `~/.cache/nvim`.

## Run

```sh
suite.sh                        # full suite, stable and nightly in parallel
suite.sh both lsp               # full selection mode, only checks whose name matches /lsp/
suite.sh --area which-key       # iteration: checks tagged with an area
suite.sh --changed main         # iteration: areas touched by `git diff main` in $CFG, plus startup and smoke
suite.sh --work <feature>       # iteration: the checks in work/<feature>/
suite.sh --list [...]           # print what would run, run nothing
suite.sh --selftest             # the runner's own tests: leak, over budget, fsmonitor, missing server
suite.sh --refresh              # sync lazy, Mason and parsers in data/ for the current CFG, then run
suite.sh --refresh-dry-run      # print the Mason keep, install and remove sets, change nothing, run nothing
CFG=/path/to/nvim suite.sh      # test another config dir (default: ../../nvim, this repo's config)
```

- Positional `stable|nightly|both` picks versions; a second positional is a name filter (an
  extended regex on the check name).
- A plain run, with no `--area`, `--changed` or `--work`, runs everything on both versions. Use it
  at integration points: before a branch lands, and for the final regression.
- Iteration runs (`--area`, `--changed`, `--work`) default to stable only, plus nightly for checks
  marked `@version-sensitive`. An explicit `stable|nightly|both` overrides that.
- Output: one line per check and version with PASS/FAIL, elapsed and budget, the reasons under
  each FAIL, then a table, per-area timings, total wall time and the hygiene assertions. The exit
  status is non-zero on any failure.
- The output and stderr of failed checks are kept in `last/<version>/`, replaced when that check
  runs again, so parallel runs of different checks don't clobber each other.
  Run dirs live in `run/` only while the suite runs.

### Tiers

| when | run | versions |
| --- | --- | --- |
| iterating on one area | `suite.sh --area lsp,format` | stable, plus nightly for `@version-sensitive` checks |
| after editing config files | `suite.sh --changed <git-range>` (e.g. `HEAD`, `main`) | same |
| developing a feature | `suite.sh --work <feature>` | same |
| before a branch lands, final regression | `suite.sh` | both, in parallel |

`--changed` maps each changed file (relative to `$CFG`) through `areas.map` to areas, and always
adds `startup` and `smoke`. A changed file that no line of `areas.map` matches runs every area, so
add a line when a new config file appears.

### Refresh

`--refresh` brings lazy to the lockfile and parsers to the config's list. Mason:

- The keep-list is the `@needs` of every check in `checks/`, `selftest/` and `work/*/`, whatever
  the run selected, plus any `ensure_installed` list in the config (the nvim-0-13 config has none:
  it installs per filetype after asking, and keeps that table private in `lua/plugins/mason.lua`).
- It installs what the keep-list lacks and never uninstalls. An installed package in no `@needs` is
  listed as `left alone`; delete it from `data/nvim/mason/packages/` by hand if it is unwanted.
- An empty keep-list fails the refresh.
- `--refresh-dry-run` prints the keep, install and remove sets (remove is always empty) for a reflink
  copy of `data/`, without lazy, parsers or a registry refresh, then exits. Log in
  `last/refresh-dry-run.log`. The config's own startup may still fetch the Mason registry into
  the copy.

### Feature work: work/ then checks/

1. `mkdir work/<feature>` and write its checks there, same format as `checks/` (fixtures in
   `work/<feature>/fixtures/<name>/` if needed). Run them with `suite.sh --work <feature>`; add
   `both` for nightly too.
2. When the feature lands, promote the checks that pass the keep rule below: move them into
   `checks/` with their `@areas` (and fixtures into `fixtures/`), add `areas.map` lines for new
   config files, run `suite.sh --area <its areas>` once, then `rm -r work/<feature>`.

### Agents running the suite

- Start a run expected to take over about 30s with Bash `run_in_background: true`, and give it its
  own cap, e.g. `timeout 1500 ~/.cache/nvim-regress/suite.sh > /tmp/nvr.log 2>&1`.
- While it runs, do other independent work. With nothing else to do, end the turn with a one-line
  status; the job's exit wakes you.
- No `sleep N` waits, no sleep-then-check loops, no long foreground calls.
- Read results with `tail`/`grep` on the log, not by loading it whole.

## Layout

| path | what |
| --- | --- |
| `suite.sh` | runner |
| `nv.sh` | launcher: `nv.sh <stable\|nightly> [nvim args]`, sandboxed env (see Hygiene) |
| `lib.sh` | shared shell helpers |
| `harness.lua` | headless check harness, loaded with `-c` |
| `refresh.lua` | `--refresh`: lazy install/restore/clean, Mason installs for every `@needs`, parser install/update |
| `areas.map` | config file glob to areas, for `--changed` |
| `checks/` | the kept checks |
| `selftest/` | checks that must fail in a given way (`@expect-fail <regex>`), for changes to the runner |
| `work/<feature>/` | checks of a feature in development, optional `fixtures/` |
| `fixtures/<name>/` | fixture trees; `default` is a small git repo with one file per language |
| `data/` | seed XDG_DATA_HOME: lazy plugins, Mason, parsers; each version runs on a reflink copy |
| `cache-seed/` | go-build, golangci-lint, gopls caches copied into each run so linters start warm |
| `shared-cache/` | Go module and npm download caches, used in place by every run (not copied), so Mason installs start warm |
| `gui.sh` | optional GUI check: a fresh start in ghostty in the `cachyos` QEMU VM, never on the host desktop |
| `INVENTORY.md` | where every check came from |

## Add a check

A check is one file in `checks/` (or `work/<feature>/`): `<name>.lua`, run headless inside the
harness, or `<name>.sh`, run by bash for anything the harness cannot drive (a TUI under tmux, a
fresh data dir). The header is comment lines at the top:

```lua
-- @desc     every enabled or Mason-installed server attaches to its filetypes
-- @areas    lsp installer
-- @budget   60
-- @versions stable nightly
-- @version-sensitive
-- @fixture  default
-- @args     main.lua
-- @needs    lua-language-server pyrefly
-- @fresh
-- @allow-leak <comm-regex> <one-line reason>
```

| key | required | meaning |
| --- | --- | --- |
| `@desc` | yes | one line: the behaviour that would go red |
| `@areas` | yes | space-separated areas (see `areas.map`); `startup` and `smoke` always run under `--changed` |
| `@budget` | yes | seconds of wall time, startup included; past it the check is killed and FAILs "over budget" |
| `@versions` | no | where the check can run at all; default `stable nightly` |
| `@version-sensitive` | no | iteration runs also run it on nightly |
| `@fixture` | no | dir under `fixtures/` (or `work/<feature>/fixtures/`); default `default`. Copied fresh per check; it is the cwd |
| `@args` | no | nvim startup args, e.g. a file to open, relative to the fixture |
| `@needs` | no | Mason packages the check needs; missing ones FAIL before launch, `--refresh` installs them |
| `@fresh` | no | run with an empty, throwaway data dir (first launch) |
| `@allow-leak` | no | a process the check may leave behind, with the reason; repeatable |

Shell checks use `#` instead of `--`.

Rules for what goes in:

- Keep a check only if it goes red on a real regression of something we changed or rely on, and
  stays green under any valid alternative implementation. No tautologies, no asserting config
  values or preferences.
- Wait on events, never fixed sleeps: `wait_attach`, `wait_diagnostics`, `wait_until`. A missing
  server must fail within seconds with a reason.
- A check never writes outside its fixture copy and its own state.

### Lua harness API

Globals available to a `.lua` check (cwd is the fixture copy; lazy's VeryLazy has fired):

| name | what |
| --- | --- |
| `check(name, ok, detail)` | record PASS/FAIL; `detail` is shown after `--` |
| `info(msg)` | record an INFO line |
| `feed(keys)` | `nvim_feedkeys(keycode(keys), "mx")`: typed, mappings applied, executed now |
| `wait_until(pred, ms)` | `vim.wait` with a 10ms poll; returns the predicate result |
| `health(name, ms)` | text of `:checkhealth <name>` after its FileType checkhealth event, the last step on both versions (nightly renders async); `"TIMEOUT"` if it never comes |
| `deprecations()` | `health("vim.deprecated")` |
| `lsp_expected(buf, ms)` | sorted names of servers that must attach to `buf`, and notes; handles function `cmd`; waits up to `ms` (10s) for root_dir lookups, and expects one still looking |
| `wait_attach(buf, names, ms)` | returns `missing, reasons`; returns early once every missing server has failed |
| `wait_diagnostics(buf, pred, ms)` | waits until `pred(vim.diagnostic.get(buf))`, returns the diagnostics |
| `lsp_log_tail(pat, n)` | last `n` lsp.log lines containing `pat` |
| `FIX`, `VERSION` | fixture dir, `stable` or `nightly` |

After the check body the harness also records as failures: errors in `:messages` (`MSG`) and
error messages in noice's history (`NOTIFY`). Not `v:errmsg`: `:silent!` and `try` still set it,
for errors the user never sees (nvim's two markdown ftplugins both `sil! nunmap <buffer> [[` on
`:edit!`). Before quitting it waits up to 15s for running nvim-lint linters, which nvim-lint does
not stop on exit.

Headless gotchas the harness handles: lazy's VeryLazy never fires without a UI, so the harness
fires it after VimEnter; which-key and other VeryLazy plugins are loaded by the time the check
runs. Nightly `:checkhealth` is async. mason-lspconfig skips installs when headless, so tools come
from `--refresh`, never from a check.

### Shell checks

Run as `bash <file>` with cwd at the fixture copy and these in the environment:
`NV` (the launcher: `"$NV" "$V" [nvim args]`), `V` (version), `S` (suite dir), `FIX`, `H` (the
version's home: `config/`, `cache/`), `CHECK_OUT` (append `PASS name`/`FAIL name -- why` lines,
then `DONE`). `NVR_DATA` is the data dir, a throwaway empty one under `@fresh`.

### Keymap clashes

Keymap clashes (`checks/keymap_clashes.lua`, report only). For n, x and o it lists every built-in key a map of ours hides: global maps after startup, and buffer-local maps in python, lua, markdown, go, text and sh buffers once their servers and gitsigns attach. It compares them against two sources. The first is the same nvim's default maps, read from a `--clean --headless` child with throwaway XDG dirs. The second is the commands and text objects in `$VIMRUNTIME/doc/index.txt`: the normal, text-object, `[`/`]`, `g`, `z`, operator-pending and visual tables, where normal-mode motions (note 1) count in x and o too. A map counts as hiding a built-in when it equals the key, prefixes it, or gives a char, mark or register argument to it (`ma`, `'a`). A map identical to one the `--clean` nvim has (a default, a runtime ftplugin map) is not ours, and which-key triggers are skipped. Each version keeps its list in `state/<version>/keymap_clashes.txt`, the one place a check keeps anything between runs. The check diffs against that list, rewrites it and logs `INFO NEW` / `INFO GONE` lines, which only show with `-v` (`suite.sh -v both keymap_clashes`). It fails only when its own logic breaks: a probe map on `ip` in o mode must be reported and one on `<F35>` must not; each index.txt section and mode must parse to a sane count, with long-standing keys in the right modes; the `--clean` dump must succeed. It never asserts on which clashes exist.

## Hygiene (built in)

- `nv.sh` strips `~/.local/share/nvim/mason/bin` and every other live nvim dir from PATH, points
  the XDG dirs and GOPATH into the sandbox and the Go module and npm caches into `shared-cache/`
  (`GOFLAGS=-modcacherw` keeps them deletable), and exports `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor
  GIT_CONFIG_VALUE_0=false` (env only; the user's git config sets fsmonitor on).
- Every check runs in its own session and process group, tagged with `NVIM_REGRESS_TAG` in its
  environment. A tagged process still alive 3s after the check ends FAILs the check with its name
  ("leaked: tflint(1234)"), then the group and every tagged process is killed. Known, expected
  leaks go in the check's `@allow-leak` with a reason.
- Lazy's checker state is seeded per check so no check git-fetches the plugins.
- Before the run: no text file and no symlink anywhere under `data/` may reach a live nvim dir or an
  old sandbox (copied Mason trees start binaries by absolute path; nvim-treesitter links
  `site/queries/*` into its plugin dir by absolute path); `--refresh` repoints them into `data/`.
  The scan is `find -exec /usr/bin/grep` plus symlink targets: `grep -r` skips symlinks.
- No display: the config sets `clipboard=unnamedplus`, so suite.sh unsets `WAYLAND_DISPLAY`,
  `DISPLAY` and `TMUX` for every check, and nv.sh unsets the first two. After the run, any
  `wl-copy`, `xclip` or `xsel` carrying a suite tag FAILs the run and is killed; one whose environ
  has the live `~/.config` is the user's own and is left alone.
- After the run: nothing under the live nvim dirs is newer than the run's stamp, no inotify
  instance and no `git fsmonitor--daemon` was left by the sandbox.

## GUI check (optional, not in the default run): in the VM only

The GUI check runs in the `cachyos` QEMU VM from `~/VMs` (see its README), headless (`GL=headless`,
frames over VNC), and never on the host desktop: a test window there took keyboard focus, niri's
`screenshot-window` overwrote the clipboard, and a crop caught the user's own windows. gui.sh opens
no host window, runs no host `niri msg` and touches no host clipboard; every GUI step is in the guest.

```sh
gui.sh up                          # lease cachyos, restore after-pr140, boot headless, log in, push builds + $CFG + fixtures
gui.sh scenes 0.12.5 ~/out         # empty data/state/cache, then six scenes -> ~/out/0.12.5-<n>-<scene>.png
gui.sh scenes nightly ~/out        #   plus ~/out/<ver>-messages.txt (:messages, v:errmsg, parser count, ]c lines)
gui.sh start nightly main.lua      # or drive it by hand: keys '<Space>', expr 'mode()', shot ~/out/x.png, stop
gui.sh down                        # release the lease (powers the VM off)
```

The scenes: first start (lazy bootstrap, plugin and parser install, no hit-enter prompt), the
ask-first tool prompt on `main.lua` (answered Yes), which-key for `<leader>` with lua_ls attached,
the completion menu, pending keys (`"a2d`), and `:Gitsigns diffthis` with `]c`. In the guest, the
config replaces `~/.config/nvim` (the home-manager one is kept as `nvim.hm`), the build is
`~/nvr/builds/<ver>`, nvim listens on `/tmp/nvr.sock` and is driven with `--remote-send` and
`--remote-expr` over ssh, and ghostty is spawned with the guest's `niri msg action spawn`. The
snapshot has no mise tools, so `push` copies the host's tree-sitter CLI into `~/.local/bin`.
