# Test image and CI: decisions

Living record of the decisions for running the test suites in a container, locally and in GitHub Actions.
Dates are when the decision was made.

## Goal

Both test tiers (`tests/unit`, `tests/regress`) run the same way on any machine and on every pull request, from a
pinned Neovim and a tool set rebuilt from the repo, not from a hand-grown sandbox.

Why: the repo had no CI, so pull requests showed "no checks reported". The suite's sandbox
(`tests/regress/{data,shared-cache,cache-seed}`, about 4 GB) grew by hand and drifted: docker-language-server was
never installed after #20 added it to the catalog, so `docker_compose_bake` failed everywhere until it was
installed by hand. `nv.sh` ran whatever nightly was in the user's mise, and new worktrees needed the sandbox
copied in.

## Status

- Built (2026-10-17) on branch `test/image`: `tests/image/Dockerfile`, `tests/image/entrypoint.sh`,
  `/.dockerignore`, mise tasks `test:image:build` and `test:image`, `.github/workflows/test.yml`.
- Verified locally with podman 6.1.3: the unit tier and the full suite pass in the image (see "Measurements").
- Not verified: the workflow itself (it can't run before the branch is pushed). `actionlint` 1.7.12 and
  `zizmor` 1.30.1 report nothing on it.

## D52: a step merges only after CI is green (2026-10-17)

Decided by the user. A rearchitecture step (and any pull request) merges only after its `test` job in
`.github/workflows/test.yml` is green. The job is named `test` so it can be made a required status check in
the branch protection of `main`. Recorded in the Process section of `docs/rearchitecture-decisions.md`.

## One install path: the suite's own refresh (2026-10-17)

**Decision.** The image installs the suite's tools, plugins and parsers with `suite.sh --refresh-only`, which
runs `refresh.lua` exactly as `suite.sh --refresh` does on the host, into `tests/regress/data/` under `/work`.
The tool list is the `@needs` of every check plus the catalog, as on the host; there is no list in the Dockerfile.

Two small seams make the layering possible, with no change on the host:

- `refresh.lua` reads `NVR_REFRESH_STEPS` (default `plugins tools resolve parsers`, today's order; the first
  step was `lazy` until step 6b of the rearchitecture moved the config to vim.pack). `tools` was
  split into `tools` (the `mise use -g` and rustup installs, which need only `lua/tools/catalog.lua`) and
  `resolve` (every need resolves through the config's resolver).
- `suite.sh --refresh-only` refreshes and exits without running checks.

**Rejected.**

- A second tool list in the Dockerfile (`mise use -g ...`): two lists to keep in sync, the drift this replaces.
- Copying the host's sandbox into the image: 4 GB of hand-grown state, the drift again.
- A fat devcontainer with the user's whole environment: bigger, and it would pin nothing the suite cares about.

## Stages and layer order (2026-10-17)

Multi-stage, at the user's request: build-only tools stay out of the final image.

| stage | what | rebuilt when |
| --- | --- | --- |
| `runtime` | base, apt packages, mise, rustup, the tree-sitter CLI, user `nvr` | a pin or package changes |
| `nvim` | the pinned nightly, built from source | `NVIM_COMMIT` changes |
| `needs` | every check's `@needs`, as one stub check `needs.lua` | any check changes (seconds) |
| `tools` | `NVR_REFRESH_STEPS=tools` on a stub config holding only `catalog.lua` | the catalog, the needs list or the suite's scripts change |
| `plugins` | `plugins resolve parsers` on the real config | any config change |
| `test` | `runtime` plus `/opt/nvim`, `data/rustup`, `data/mise`, `data/nvim` | |

- The `needs` stage keeps the tools layer when a check is added without a new tool: the `tools` stage copies
  only its output, and the layer cache keys a copy on its content.
- The final image copies `data/mise` and `data/rustup` from `tools`, not from `plugins`, and before `data/nvim`,
  so a config change rebuilds only the last ~100 MB.
- The installs must stay at the path they were installed to: mise's installs keep absolute paths (shebangs, the
  pypi venvs' symlinks). So `/work/tests/regress/data` is the path at build and at run time.
- Build-only, left out of the final image: uv (mise's pypi backend installs with it), unzip, xz-utils, bzip2,
  the download caches (`shared-cache/`), rustup's downloads, nvim's build toolchain.
- Must stay in the final image: the Go toolchain (gopls and goimports run with `go` on PATH) and node (the npm
  servers), both inside `data/mise`; rustup and its proxies (`/usr/local/cargo/bin`, as `~/.cargo/bin` on the
  host: the resolver finds `rust-analyzer` there and asks `rustup which`); the tree-sitter CLI, gcc and
  libc6-dev, because `fresh_bootstrap.sh` downloads and builds parsers on a first start; git, curl, tmux
  (`pending_keys.sh`), gawk (`suite.sh` uses `asorti`), procps (`pgrep`); python3 (the pypi venvs point at it);
  libicu76 (marksman, a .NET binary, exits without it). lua5.1 and luarocks were here for `:checkhealth lazy`
  in `startup.lua`; vim.pack replaced lazy.nvim (docs/rearchitecture-decisions.md, "Step 6b: vim.pack") and
  `startup.lua` reads `:checkhealth vim.pack`, so both went.

## Base image (2026-10-17)

**Decision.** `debian:trixie-slim`, pinned by digest in `ARG BASE`. glibc, so mise's prebuilt tools, clangd and
node run as on the host.

**Rejected.** Alpine (musl: the prebuilt glibc tools don't run). Ubuntu: no gain over Debian slim, larger. An
Arch base would match the host's packages (CachyOS) more closely, notably gcc (see "What differs from the host"),
but is rolling and larger; kept as the option if compiler parity starts to matter.

## How the nightly is pinned (2026-10-17)

**Decision.** `ARG NVIM_COMMIT` names a commit on Neovim's master; the `nvim` stage fetches that commit and builds
it (`RelWithDebInfo`, as the official nightlies) into `/opt/nvim`. `nv.sh` and `tests/unit/run.sh` take the
binary from `$NVR_NVIM` (the image sets it), else the user's mise nightly as before.

Why: Neovim keeps one nightly release, replaced every night, so a URL with a checksum breaks the next day. A
commit is content-addressed and rebuilds the same way. The pin is the host's nightly of 2026-10-16
(`v0.13.0-dev-1868+gbe5167e21c`).

**The host's nightly (2026-10-18).** The user's mise nightly is now `github:neovim/neovim@nightly`, not the bare
`neovim`, whose first registry backend is a vfox plugin (`mise registry neovim` prints `vfox:jdx/vfox-neovim
aqua:neovim/neovim`). `nv.sh`, `gui.sh` and `tests/unit/run.sh` ask mise for its dir (`nvim_build` in
`tests/regress/lib.sh`, `mise where`) instead of hard-coding `installs/neovim/nightly`, and `nv.sh` names the
install command when it is missing. The lookup costs about 19 ms per `nv.sh` start (pooled medians 33.0 ms with
`NVR_NVIM` set, 51.7 ms without; 5 interleaved rounds of 3 runs, all 5 agree): real, but one-off and unfelt (about
2 s over a full suite's 89 checks), so it is not cached.

To bump: set `NVIM_COMMIT` to a newer master commit, e.g. the one the latest nightly's `nvim --version` names,
and rebuild; only the `nvim` stage and the layers after it rebuild.

**Rejected.** The `nightly` release tarball (moves daily), mise's `neovim@nightly` (moves daily), mise's
`neovim@ref:<sha>` (builds from source too, with more moving parts).

Other pins, each an `ARG` with a sha256: mise 2026.10.8 (the host's), rustup 1.29.1, the tree-sitter CLI 0.27.0
(the version `nv.sh` puts on PATH on the host; keep the two in step), uv 0.13.0 (the host's). The catalog's
tools are `@latest`, as on the host's `--refresh`: they are fixed by the layer cache and move when the tools
layer rebuilds.

## Cache and CI (2026-10-17)

**Decision.** The workflow builds with buildx and `docker/build-push-action`, caching every stage in the
GitHub Actions cache (`type=gha,mode=max`), then runs `mise-tasks/test/image/_default` with bash (the same file
`mise run test:image` runs) for `unit` and for `suite`, and uploads the suite's `last/` on failure. It passes
the job's own `github.token` as a build secret so mise's GitHub API calls are not rate-limited; the secret is
mounted for the tools step only and is in no layer. Actions are pinned by commit.

`mode=max` because the tools layer lives in an intermediate stage: with `min` only the final layers are cached
and the tools would reinstall on every config change.

**Rejected.** GHCR as a registry cache: needs `packages: write`, and pull requests from forks can't push to it.
An inline cache: caches the final stage only.

Runner limits: the image is 2.72 GB and the build keeps the stages besides it, so the job first deletes the
runner's Android, .NET and GHC trees for disk headroom. Not measured on a runner.

## D156: Dependabot keeps the actions' pins current (2026-10-19)

**Context.** Every action in the workflows is pinned by commit SHA with a version comment (`test.yml`,
`cache-prune.yml`), the pin GitHub's secure-use guide recommends, and nothing updated them.

**Decision (the user's).** `.github/dependabot.yml` checks the `github-actions` ecosystem monthly and groups every
update into one PR, with `ci:` commits. Dependabot updates a SHA pin and its version comment together
([docs](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot)).
`.github/` is a test input (D148), so that PR runs the full test job, about once a month; `ci:` commits cut no release.

**Rejected.** Weekly or ungrouped updates: a full test run per action per week for pins that rarely matter that soon.
It doesn't cover `nvim-pack-lock.json` or `mise.toml`, which Dependabot has no ecosystem for.

## D153: tombi formats offline (2026-10-19)

Investigation approved by the user; logs and scripts in `~/.cache/nvim-config/tombi-flake/`.

**Context.** `tools_choice_state` failed twice in CI with `NOTIFY Formatting failed in mise.toml with tombi:
Formatter 'tombi' timeout` (run 39294838773 attempt 2, run 39297757962 leg 3/3, which had its runner to itself). The
check writes a `mise.toml`, and formatting on save runs tombi through conform, synchronously, with conform's default
1 s timeout (`timeout_ms = 1000`, conform.nvim `lua/conform/init.lua:417`). With no catalog in its cache, or one
older than a day (`TOMBI_CACHE_TTL`, default 86400 s), tombi first fetches the SchemaStore catalog and the file's
schema, waiting up to 5 s (`TOMBI_HTTP_TIMEOUT`)
([environment variables](https://github.com/tombi-toml/tombi/blob/main/docs/src/routes/docs/environment-variables.mdx)).
The image starts with an empty `cache-seed/` (`tests/image/Dockerfile:129-130`), and a run's checks share one cache
(`suite.sh:280`), so the first check in a run to format TOML pays the fetch. In both failures that was
`tools_choice_state`: no check before it in its shard (fish_format to toggle_wk_specs) mentions a TOML file
(`grep -l toml checks/*`). Measured with tombi 1.8.7 on `mise.toml`:

| cache | network | time |
| --- | --- | --- |
| empty | up | 132 to 164 ms |
| fresh | up | 64 to 74 ms |
| empty | cut (`unshare -rn`) | 5.0 s, exit 1, "failed to fetch catalog" |
| a day old | cut | 10.1 s |
| empty or a day old | cut, `--offline` | 4 to 50 ms |

The same timeout hits a user: saving a TOML file offline with a day-old cache fails every time.

**Decision.** conform runs `tombi format --offline` (`nvim/lua/format/conform.lua`). Offline, tombi reads the
cache whatever its age and skips the fetch
([store.rs](https://github.com/tombi-toml/tombi/blob/80a03cf506e5cfb2cbcd53e0b6b24979369eb567/crates/tombi-schema-store/src/store.rs#L533-L557)),
and its built-in `tombi://` schemas still apply: a `Cargo.toml`'s dependencies come out sorted with an empty cache,
and a `mise.toml` formats the same with and without the fetched schema. The tombi language server stays online and
fills the same cache (`TOMBI_CACHE_HOME`, else `$XDG_CACHE_HOME/tombi`, `crates/tombi-cache/src/lib.rs`).

**Rejected.**

- A longer conform timeout: a save would still block up to 5 s, or 10 s, on the network, and with an empty cache and
  no network tombi fails anyway.
- Pre-seeding tombi's cache in the image: fixes CI only, and the seeded catalog expires after a day.
- `TOMBI_OFFLINE=true` in the formatter's environment: conform's `env` is already the resolver's per-project
  environment (`nvim/lua/format/conform.lua`), so the flag is simpler.

**Tests.** `toml_format_offline` saves a TOML file behind a proxy that accepts connections and never answers, once
with an empty tombi cache and once with a stale one, and checks the written file is formatted. Before the fix it
fails both cases with the CI message (3 of 3 runs); after, it passes 20 of 20. `tools_choice_state` with an empty
`cache-seed/` (as in the image): 20 of 20 before and after with the network up, and 0 of 5 before, 5 of 5 after,
with the network cut.

## D157: socket paths fit, and a gr map of its own fails keys_gr_typed (2026-10-19)

Approved by the user; wrong implementations and logs in `~/.cache/nvim-config/gr-biome/`.

**Context.** Two checks passed without testing what they claim.

- `lint_dedupe`'s "biome project" case never had biome's server locally. Biome's daemon binds
  `$XDG_CACHE_HOME/biome/biome-daemon/biome-socket-2.5.15`, and a check's cache was
  `~/.cache/nvim-regress/run/<date>-<time>-<pid>/nightly/cache`: 115 bytes here, over the 107 a unix socket path
  holds (`path must be shorter than SUN_LEN`). The case saw only the linter and passed. In CI the path was 107
  bytes (`/home/nvr`, two-digit pids), which fits with nothing to spare. Worktrees also copied a symlinked
  `cache-seed/` as a symlink, so their runs wrote into the main checkout's seed.
- `keys_gr_typed` passed with a global or buffer-local `gr` map. which-key decides at `gr`: within `timeoutlen` of
  the `g` it hands `gr` to Neovim, which waits `timeoutlen` for a longer map; after that it keeps the sequence and
  waits for the next key itself (which-key `state.lua:188-196`). Typing every key fast or every key slow never
  leaves a pause after a fast `gr`, so the `gr` map never ran.

**Decision.**

- Run dirs go to `~/.cache/nvr/<6 random chars>` (`mktemp -d`), so a check's cache is about 45 bytes here and 41 in
  CI. `suite.sh` refuses to start when a home would leave less than 56 bytes for a socket, naming `NVR_RUNS`.
  `mktemp` keeps each run and shard in its own dir.
- `suite.sh` copies `cache-seed/.`, the seed's contents, so a symlinked seed is only read.
- `lint_dedupe` checks that the server attached in each case where it should run.
- `keys_gr_typed` also types each key fast with a pause before the last key.

**Rejected.**

- Pointing `XDG_CACHE_HOME` at a short symlink in `/tmp`: tools that resolve the path would get the long one back.
- `XDG_RUNTIME_DIR` for run dirs: it is a tmpfs, so each run's copy of the plugins and caches would sit in memory.
- A static check that no `gr` map exists: a typed check catches every way a shorter map wins, including `nowait`.

**Tests.** With `origin/main`'s suite, `lint_dedupe` with the new check fails "biome project: biome attached" and
passes with this branch's. `keys_gr_typed` fails on a global, a buffer-local and a `nowait` `gr` map, each added
alone to the config, and passes on the config as it is.

## Local runs (2026-10-17)

- `mise run test:image:build`: podman by default (`NVR_ENGINE=docker` for docker), capped with
  `--memory 3g`. This machine's docker has no buildx; its legacy builder can't mount a build secret
  (`RUN --mount`), while podman and buildx can. BuildKit has no per-build memory cap, so a docker build is not
  capped.
- `mise run test:image [unit [args] | suite [args] | <command>]`: builds first (cached), then runs the
  container with `--memory 2g --memory-swap 2560m`, the same cap as the host's `systemd-run -p MemoryMax=2G
  -p MemorySwapMax=512M`. The checkout is mounted read-only at `/src`; the entrypoint copies `nvim/` and
  `tests/` (without the checkout's own sandbox) into `/work` beside the image's `data/`, so the suite can write
  `last/` and run state. Failed checks' output lands in `tests/regress/last/image/`.
- The container runs as `nvr` (uid 1000), not root, so checks see an ordinary user. With rootless podman,
  `--userns=keep-id:uid=1000,gid=1000` makes that uid the caller, so the output is the caller's. With docker the
  output files belong to uid 1000.
- tini is PID 1, so the checks' orphans are reaped, as systemd does on the host; the suite reads a check's exit
  from `/proc/<pid>/stat`.
- The entrypoint warns when `nvim/` differs from the config the image was built from (a hash of `nvim/` kept
  at build time), since `data/` then holds the wrong plugins; the mise task rebuilds first, so it only shows
  when the image is run directly.

## What differs from the host (2026-10-17)

- Hygiene assertions on the live dirs (`~/.config/nvim`, `~/.local/share/mise/installs`, `~/.rustup`...) hold
  trivially in the container: the dirs don't exist. They stay and pass.
- `--changed <range>` needs git history; `.git` is not copied (in a worktree it is a file pointing outside the
  checkout).
- `cache-seed/` is empty, so Go's build cache and gopls start cold; no check went over budget for it.
- `gui.sh` stays host-only: it drives the `cachyos` QEMU VM over ssh.
- Debian's gcc 14 builds a large parser much slower than the host's gcc 16: `tree-sitter build` of
  tree-sitter-gitcommit took 28-38 s in the image and 5.4 s on the host. Plain `gcc -O2` takes 4.9 s; the
  `-Wall` tree-sitter adds makes the difference (29.5 s with it). clang 19 builds it in 7.3 s but adds about
  300 MB. This exposed `tools_prompts`, which opens a Dockerfile and `COMMIT_EDITMSG`: those start parser
  installs, and the slow build outlived the check ("leaked: tree-sitter cc cc1"). The check now stubs the parser
  install, since parsers are not what it tests; it passed on the host only because the build happened to finish
  in time.
- The host's sandbox had drifted from the config: it holds the toml and zig parsers, which no `ensure_installed`
  names; the image has exactly the config's list.

## Measurements (2026-10-17, this machine, 16 cores, podman 6.1.3)

- Image: 2.72 GB (`podman images`). Largest layers: `data/mise` 1.21 GB, `data/rustup` 664 MB, apt packages
  389 MB, mise + tree-sitter + rustup 211 MB, `data/nvim` 96 MB, nvim 60 MB.
- Cold build: 365 s, nvim built with 4 jobs. After a runtime package change (nvim cached): 179 s. After a
  config-only change: 56 s (only `needs`, `plugins` and the last layers ran; the tools step and both tool
  layers came from the cache).
- Full suite in the image: SUITE PASS, 69 checks, 135.9 s wall (`mise run test:image`, 194 s with the cached
  build check and the unit tier), against 144.5 s for a full run on the host. Unit tier: UNIT PASS, 2 files.
