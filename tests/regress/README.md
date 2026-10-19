# nvim-regress

One rerunnable regression suite for the Neovim config, on nightly 0.13-dev.
Nothing here edits the config under test, the repo, or the live `~/.config/nvim`,
`~/.local/share/nvim`, `~/.local/state/nvim` and `~/.cache/nvim`.

## Run

```sh
suite.sh                        # full suite
suite.sh lsp                    # only checks whose name matches /lsp/
suite.sh --area which-key       # iteration: checks tagged with an area
suite.sh --changed main         # iteration: areas touched by `git diff main` in $CFG, plus startup and smoke
suite.sh --work <feature>       # iteration: the checks in work/<feature>/
suite.sh --list [...]           # print what would run, run nothing
suite.sh --shard 2/3 [...]      # run shard 2 of 3 of the selection, balanced by durations.tsv
shard-cover.sh 3 [...]          # check that 3 shards split the selection exactly (--results: what shard runs ran)
durations.sh <results.tsv...>   # rewrite durations.tsv from runs' last/results.tsv (CI's: the regress-results artifact)
suite.sh --selftest             # the runner's own tests: leak, over budget, fsmonitor, missing server
suite.sh --refresh              # sync plugins, the suite's tools and parsers in data/ for the current CFG, then run
suite.sh --refresh-only         # the same sync, then exit without running checks (the test image's build)
suite.sh --refresh-dry-run      # print the tools every check needs and which do not resolve, change nothing, run nothing
CFG=/path/to/nvim suite.sh      # test another config dir (default: ../../nvim, this repo's config)
```

- A positional argument is a name filter (an extended regex on the check name).
- A plain run, with no `--area`, `--changed` or `--work`, runs everything. Use it at integration
  points: before a branch lands, and for the final regression.
- Output: one line per check and version with PASS/FAIL, elapsed and budget, the reasons under
  each FAIL, then a table, per-area timings, total wall time and the hygiene assertions. The exit
  status is non-zero on any failure.
- The output and stderr of failed checks are kept in `last/<version>/`, replaced when that check
  runs again, so parallel runs of different checks don't clobber each other.
  Run dirs live in `~/.cache/nvim-regress/run/` (`$NVR_RUNS`) only while the suite runs. They sit outside
  the repo so that no project marker above a fixture, such as an untracked `mise.local.toml`, reaches a check.

### Tiers

| when | run |
| --- | --- |
| iterating on one area | `suite.sh --area lsp,format` |
| after editing config files | `suite.sh --changed <git-range>` (e.g. `HEAD`, `main`) |
| developing a feature | `suite.sh --work <feature>` |
| before a branch lands, final regression | `suite.sh` |

`--changed` maps each changed file (relative to `$CFG`) through `areas.map` to areas, and always
adds `startup` and `smoke`. A changed file that no line of `areas.map` matches runs every area, so
add a line when a new config file appears.

### Refresh

`--refresh` brings the plugins to the lockfile (vim.pack clones what is missing) and parsers to the config's list.
Tools:

- Every tool a check runs comes from the suite's own mise, never the user's: `data/mise/data` is its
  `MISE_DATA_DIR` and `data/mise/config.toml` its global config (`lib.sh` `mise_env`). Rust components
  come from the suite's own `RUSTUP_HOME`, `data/rustup`. The user's `~/.config/mise`,
  `~/.local/share/mise` and `~/.rustup` are never written.
- The keep-list is the `@needs` of every check in `checks/`, `selftest/` and `work/*/`, whatever the
  run selected: catalog binaries (`lua/tools/catalog.lua`), plus the binaries they call (`requires`).
- Catalog specs go into the suite's global config with one `mise use -g <spec>@latest ...`, plus the
  runtimes they need (`node@lts`, `go@latest`); rustup components into a minimal stable toolchain.
  Then every need must resolve through the config's own resolver, or the refresh fails.
- It never uninstalls; delete `data/mise` or `data/rustup` by hand to start over.
- An empty keep-list fails the refresh.
- `--refresh-dry-run` prints the keep-list, the specs and components, and which needs do not
  resolve now, without plugins, parsers or installs, then exits. Log in `last/refresh-dry-run.log`.

### Feature work: work/ then checks/

1. `mkdir work/<feature>` and write its checks there, same format as `checks/` (fixtures in
   `work/<feature>/fixtures/<name>/` if needed). Run them with `suite.sh --work <feature>`.
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

### In the test image

`tests/image/Dockerfile` builds an image with a pinned nightly and the suite's tools, plugins and parsers,
installed by `suite.sh --refresh-only` at build time; CI (`.github/workflows/test.yml`) runs both tiers in it.

```sh
mise run test:image:build          # podman (or docker, NVR_ENGINE=docker); cached, a config change rebuilds plugins only
mise run test:image                # builds, then tests/unit/run.sh and the full suite
mise run test:image suite lsp      # suite.sh args; `unit [args]` for the unit tier, or any command (bash)
```

- The checkout is mounted read-only and copied into the container beside the image's `data/`; the container is
  capped at 2 GB. Failed checks' output lands in `last/image/` (`$NVR_OUT`).
- `nv.sh` and `tests/unit/run.sh` take the nvim binary from `$NVR_NVIM` (the image sets it), else the user's
  mise nightly, `github:neovim/neovim@nightly` (`mise where` finds it; `nv.sh` fails with a hint when it is missing).
- `--refresh-only` refreshes and runs nothing; `NVR_REFRESH_STEPS` picks the steps (`plugins tools resolve parsers`,
  the default, in that order).
- Behaves differently in the container: the hygiene assertions on the live nvim, mise and rustup dirs hold
  trivially (they don't exist there), `--changed` has no git history (`.git` is not copied), and `cache-seed/` is
  empty, so Go caches start cold. `gui.sh` stays host-only: it drives the QEMU VM.

## Layout

| path | what |
| --- | --- |
| `suite.sh` | runner |
| `nv.sh` | launcher: `nv.sh nightly [nvim args]`, sandboxed env (see Hygiene) |
| `lib.sh` | shared shell helpers |
| `harness.lua` | headless check harness, loaded with `-c` |
| `refresh.lua` | `--refresh`: plugins to the lockfile (vim.pack update and delete, blink's library), the suite's mise and rustup installs for every `@needs`, parser install/update |
| `areas.map` | config file glob to areas, for `--changed` |
| `checks/` | the kept checks |
| `selftest/` | checks that must fail in a given way (`@expect-fail <regex>`), for changes to the runner |
| `work/<feature>/` | checks of a feature in development, optional `fixtures/`; `work/.gitkeep` keeps the dir, which the test image copies, while no feature is |
| `fixtures/<name>/` | fixture trees; `default` is a small git repo with one file per language |
| `data/` | `data/nvim`: seed XDG_DATA_HOME (plugins in `site/pack/core/opt`, parsers), each version runs on a reflink copy; `data/mise`, `data/rustup`: the suite's tools, used in place |
| `cache-seed/` | go-build, golangci-lint, gopls caches copied into each run so linters start warm |
| `shared-cache/` | Go module and npm download caches, used in place by every run (not copied), so Go and npm runs start warm |
| `gui.sh` | optional GUI check: a fresh start in ghostty in the `cachyos` QEMU VM, never on the host desktop |

## Add a check

A check is one file in `checks/` (or `work/<feature>/`): `<name>.lua`, run headless inside the
harness, or `<name>.sh`, run by bash for anything the harness cannot drive (a TUI under tmux, a
fresh data dir). The header is comment lines at the top:

```lua
-- @desc     every enabled server attaches to its filetypes
-- @areas    lsp tools
-- @budget   60
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
| `@fixture` | no | dir under `fixtures/` (or `work/<feature>/fixtures/`); default `default`. Copied fresh per check; it is the cwd |
| `@args` | no | nvim startup args, e.g. a file to open, relative to the fixture |
| `@needs` | no | catalog binaries the check needs; a Lua check FAILs before its body when one does not resolve, `--refresh` installs them into the suite's mise |
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
- A key check judges where a key works by pressing it (`feed`) and observing what it did, and where the
  popup offers it with `wk_lists`/`wk_menu`, never by whether a buffer has a map (`maparg`,
  `nvim_buf_get_keymap`): how a key is gated may change, from buffer maps to global maps that test their
  need when pressed (`docs/rearchitecture-decisions.md`, D48).

### Lua harness API

Globals available to a `.lua` check (cwd is the fixture copy; VeryLazy has fired):

| name | what |
| --- | --- |
| `check(name, ok, detail)` | record PASS/FAIL; `detail` is shown after `--` |
| `info(msg)` | record an INFO line |
| `feed(keys)` | `nvim_feedkeys(keycode(keys), "mx")`: typed, mappings applied, executed now |
| `wait_until(pred, ms)` | `vim.wait` with a 10ms poll; returns the predicate result |
| `health(name, ms)` | text of `:checkhealth <name>` after its FileType checkhealth event, the last step (nightly renders async); `"TIMEOUT"` if it never comes |
| `deprecations()` | `health("vim.deprecated")` |
| `lsp_expected(buf, ms)` | sorted names of servers that must attach to `buf`, and notes; handles function `cmd`; waits up to `ms` (10s) for root_dir lookups, and expects one still looking |
| `wait_attach(buf, names, ms)` | returns `missing, reasons`; returns early once every missing server has failed |
| `wait_diagnostics(buf, pred, ms)` | waits until `pred(vim.diagnostic.get(buf))`, returns the diagnostics |
| `lsp_log_tail(pat, n)` | last `n` lsp.log lines containing `pat` |
| `wk_lists(buf, mode, lhs)` | the label which-key's popup shows for `lhs` in `buf` and `mode` (`true` with none), `nil` where it leaves the key out; read with `buf` current, as a key press builds the popup |
| `wk_menu(buf, mode)` | every key, groups left out, the popup lists in `buf` and `mode`, as `{ [keys] = label }` |
| `wk_wait(buf, mode, lhs, listed, ms)` | waits up to `ms` (5s) until the popup lists `lhs` (`listed` true) or leaves it out; use it, not `wait_until`, since each popup read schedules which-key work that wakes a `wait_until` predicate forever |
| `FIX`, `VERSION` | fixture dir, `nightly` |

After the check body the harness also records as failures: errors in `:messages` (`MSG`) and
ERROR-level notifications in snacks.notifier's history (`NOTIFY`): snacks.notifier owns `vim.notify`
and never echoes. ui2 keeps no history of its own (its pager renders `:messages`), and it stays off
headless, so `MSG` covers every message it would show (only gui.sh checks that ui2 attaches). Not
`v:errmsg`: `:silent!` and `try` still set it, for errors the user never sees (nvim's two markdown
ftplugins both `sil! nunmap <buffer> [[` on `:edit!`). Before quitting it waits up to 15s for running
nvim-lint linters, which the config kills at the quit, so an error a run reports late is still seen. A check
that must see what a quit leaves running drives its own nvim instead (`checks/lint_quit_kill.sh`).

Headless gotchas the harness handles: the config fires VeryLazy once a UI enters (`lua/app/init.lua`),
so headless the harness fires it after VimEnter; which-key and the other deferred plugins are loaded by the time the check
runs. Nightly `:checkhealth` is async. Without a UI the config never prompts or installs
(`tools.can_install()` is false), so tools come from `--refresh`, never from a check. A check that
runs a tool itself asks the resolver for it (`require("tools").wait(name, FIX)`: `path`, `env`).

### Shell checks

Run as `bash <file>` with cwd at the fixture copy and these in the environment:
`NV` (the launcher: `"$NV" "$V" [nvim args]`), `V` (version), `S` (suite dir), `FIX`, `H` (the
version's home: `config/`, `cache/`), `CHECK_OUT` (append `PASS name`/`FAIL name -- why` lines,
then `DONE`). `NVR_DATA` is the data dir, a throwaway empty one under `@fresh`.

### Keymap clashes

Keymap clashes (`checks/keymap_clashes.lua`, report only). For n, x and o it lists every built-in key a map of ours hides: global maps after startup, and buffer-local maps in python, lua, markdown, go, text and sh buffers once their servers and gitsigns attach. It compares them against two sources. The first is the same nvim's default maps, read from a `--clean --headless` child with throwaway XDG dirs. The second is the commands and text objects in `$VIMRUNTIME/doc/index.txt`: the normal, text-object, `[`/`]`, `g`, `z`, operator-pending and visual tables, where normal-mode motions (note 1) count in x and o too. A map counts as hiding a built-in when it equals the key, prefixes it, or gives a char, mark or register argument to it (`ma`, `'a`). A map identical to one the `--clean` nvim has (a default, a runtime ftplugin map) is not ours, and which-key triggers are skipped. Each version keeps its list in `state/<version>/keymap_clashes.txt`, the one place a check keeps anything between runs. The check diffs against that list, rewrites it and logs `INFO NEW` / `INFO GONE` lines, which only show with `-v` (`suite.sh -v keymap_clashes`). It fails only when its own logic breaks: a probe map on `ip` in o mode must be reported and one on `<F35>` must not; each index.txt section and mode must parse to a sane count, with long-standing keys in the right modes; the `--clean` dump must succeed. It never asserts on which clashes exist.

## Hygiene (built in)

- `nv.sh` strips every live nvim dir, any Mason bin dir and any mise shims dir from PATH, unsets the
  user's `MISE_*` and `__MISE_*` vars and points every `MISE_*` dir into the sandbox (`MISE_CEILING_PATHS=$HOME`
  keeps mise from reading the user's `~/.config/mise/config.toml` as a project config), points
  the XDG dirs and GOPATH into the sandbox and the Go module and npm caches into `shared-cache/`
  (`GOFLAGS=-modcacherw` keeps them deletable), and exports `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor
  GIT_CONFIG_VALUE_0=false` (env only; the user's git config sets fsmonitor on).
- Every check runs in its own session and process group, tagged with `NVIM_REGRESS_TAG` in its
  environment. A tagged process still alive 3s after the check ends FAILs the check with its name
  ("leaked: tflint(1234)"), followed by one line per process with its pid, parent pid, age and
  command line (`ps -o pid=,ppid=,etimes=,args=`; a parent that is gone shows as the reaper, often
  1), also kept as `LEAK` lines in `last/`; then the group and every tagged process is killed. Known, expected
  leaks go in the check's `@allow-leak` with a reason.
- Before the run: no text file and no symlink anywhere under `data/` may reach a live nvim dir or an
  old sandbox (copied tool trees start binaries by absolute path; nvim-treesitter links
  `site/queries/*` into its plugin dir by absolute path); `--refresh` repoints them into `data/`.
  The scan is `find -exec /usr/bin/grep` plus symlink targets: `grep -r` skips symlinks.
- No display: the config sets `clipboard=unnamedplus`, so suite.sh unsets `WAYLAND_DISPLAY`,
  `DISPLAY` and `TMUX` for every check, and nv.sh unsets the first two. After the run, any
  `wl-copy`, `xclip` or `xsel` carrying a suite tag FAILs the run and is killed; one whose environ
  has the live `~/.config` is the user's own and is left alone.
- After the run: nothing under the live nvim dirs, the user's `~/.config/mise`, `~/.local/share/mise/installs`
  or `~/.rustup/toolchains` is newer than the run's stamp, no inotify
  instance and no `git fsmonitor--daemon` was left by the sandbox.

## GUI check (optional, not in the default run): in the VM only

The GUI check runs in the `cachyos` QEMU VM from `~/VMs` (see its README), headless (`GL=headless`,
frames over VNC), and never on the host desktop: a test window there took keyboard focus, niri's
`screenshot-window` overwrote the clipboard, and a crop caught the user's own windows. gui.sh opens
no host window, runs no host `niri msg` and touches no host clipboard; every GUI step is in the guest.

```sh
gui.sh up                          # lease cachyos, restore after-pr140, boot headless, log in, push builds + $CFG + fixtures
gui.sh scenes nightly ~/out        # empty data/state/cache, then six scenes -> ~/out/nightly-<n>-<scene>.png
                                   #   plus ~/out/<ver>-messages.txt (:messages, v:errmsg, ui2 attached, parser count, ]c lines)
gui.sh start nightly main.lua      # or drive it by hand: keys '<Space>', expr 'mode()', shot ~/out/x.png, stop
gui.sh down                        # release the lease (powers the VM off)
```

The scenes: first start (plugin and parser install, no hit-enter prompt), the
missing-tool prompt on `main.lua` (answered Install; `mise use --path` in the guest, D91), which-key for `<leader>` with lua_ls attached,
the completion menu, pending keys (`"a2d`), and `:Gitsigns diffthis` with `]c`. In the guest, the
config replaces `~/.config/nvim` (the home-manager one is kept as `nvim.hm`), the build is
`~/nvr/builds/<ver>`, nvim listens on `/tmp/nvr.sock` and is driven with `--remote-send` and
`--remote-expr` over ssh, and ghostty is spawned with the guest's `niri msg action spawn`. The
snapshot has no mise tools, so `push` copies the host's tree-sitter CLI into `~/.local/bin`.
