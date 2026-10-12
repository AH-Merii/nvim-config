# Replacing Mason with mise: decisions

Living record of the decisions for moving LSP servers, formatters and linters from Mason to mise.
Newest status first in each section. Dates are when the decision was made.

## Goal

Stop using Mason. Every LSP server, formatter and linter comes from mise (or the system where noted),
resolved per project, with project-pinned tools taking priority.

## Status

- Decided: resolution order, global installs, UX, where config lives, every per-language tool choice,
  project prompt, install timing, versions, where it is built, file-scoped tools.
- Done: Mason bin dir removed from the shell PATH.
- Verified: every chosen tool installs through mise and runs (see "Install specs").
- Not started: implementation.

## Resolution order (2026-10-12)

For each tool, per project root, first hit wins:

1. **Project env**: `.venv/bin`, `node_modules/.bin`, searched upward from the buffer.
2. **Project mise config**, only if the user accepted that config.
3. **Global**: global mise tools, then the system PATH, ignoring mise shims, mise per-project install dirs
   and Mason's bin dir.
4. **Missing**: offer a global mise install.

Facts this rests on:

- `executable()` can't be trusted: `which -a ruff` finds `~/.local/share/mise/shims/ruff`, while
  `mise which ruff` says "ruff is a mise bin however it is not currently active".
- PATH is fixed when Neovim starts, so binaries are resolved per project root and passed as absolute paths.
- mise uses an untrusted project's plain `[tools]` without asking; only configs with `[env]` are refused
  until trusted. So "did the user accept this project config" is our check, not mise's.
- `mise install` / `mise exec` trust their active config automatically (`mise help trust`), so the project
  prompt must say it trusts the config.
- Useful mise queries, run with cwd = project root: `mise ls --current --json` (source path, installed,
  active) and `mise bin-paths` (`-C /` gives global tools only).

## Global installs (2026-10-12)

- **On demand**: nothing is installed up front. A tool is offered for global install the first time a
  filetype needs it.
- **Versions**: written as `"latest"`, matching the rest of the global config; updated with `mise upgrade`.

- Global installs use `mise use -g` and land in the tracked global config `~/.config/mise/config.toml`.
- Verified in isolation: `mise use -g` on a symlinked config keeps the symlink and all comments, and appends
  the new tool at the end of `[tools]`.

## UX (2026-10-12)

- **Project prompt**, the first time a file opens in a project with its own mise config. Three choices,
  remembered until that config file changes:
  - *Use + install*: run `mise install` there (this trusts the config, so the prompt says so).
  - *Installed only*: use what the project pins only if it's already installed; no install, no trust.
  - *Global only*: ignore the project config; project env (`.venv`, `node_modules`) still applies.

- A prompt only the first time a project or tool is missing. After that, a quiet lualine indicator plus a
  `:Tools` view (per tool: chosen binary, where it came from, reason if missing; install / retry / restart).
- One batched prompt per project, not per filetype. Answers remembered per project config file and asked
  again when that file changes.
- Never prompt for library code (site-packages, node_modules, cargo registry, Go module cache), git commit
  messages, help/diff/nofile buffers, or headless runs and tests.

## Where config lives (2026-10-12): option (b)

- Each role stays where it lives today: server settings in `after/lsp/`, formatters in conform's
  `formatters_by_ft`, linters in nvim-lint's `linters_by_ft`.
- One new tool catalog, keyed by binary: mise install spec, project paths (`.venv/bin`, `node_modules/.bin`),
  runtime needs (node, go), and a probe for toolchain components. It replaces Mason's `servers`,
  `package_names` and `extra_packages` tables (`nvim/lua/plugins/mason.lua:4-33`).
- An explicit `vim.lsp.enable{...}` list replaces mason-lspconfig's automatic enabling. It must name ruff,
  biome and tflint explicitly.
- Rejected: (a) one file per language generating conform/nvim-lint tables. It would rebuild things that
  already work (the TOML formatter chooser, `covering_server`).

How the three roles differ:

| | Language server | Formatter (conform) | Linter (nvim-lint) |
|---|---|---|---|
| Process | One long-running process per project root | One run per format | One run per lint |
| Missing tool | Not started, no error | Skipped; conform falls back to LSP formatting | Skipped |
| After install | Start the server for open files | Next format works | Re-lint open files |
| Absolute path via | Function-form `cmd` (must also pass cwd = root) | conform `command` function | nvim-lint per-run hook |

## File-scoped tools (2026-10-12): dotted sub-filetypes

Rule: a tool is offered for install only on the files it would actually run on. Running and install
offers come from the same tables, so they can't drift apart. Today they do: actionlint only runs on
workflow files (`nvim/lua/plugins/nvim-lint.lua:93-101`), but Mason offers it for every YAML file, and
pyproject-fmt for every TOML file (`nvim/lua/plugins/mason.lua:30-33`).

How: files that need extra tools get a dotted sub-filetype from `vim.filetype.add`, defined in one place.

| Files | Filetype | Extra tools |
|---|---|---|
| `*/.github/workflows/*.y{a,}ml` | `yaml.github-actions` | actionlint, zizmor (lint) |
| `pyproject.toml` | `toml.pyproject` | pyproject-fmt (format) |

Why this works with the existing tools:

- Neovim's docs suggest a custom filetype via `vim.filetype.add()` for matching files by name or pattern
  (runtime `lua/vim/lsp.lua:178-179`).
- nvim-lint: with no exact key, it uses the union of each part's linters (`nvim-lint/lua/lint.lua:223-238`),
  so `yaml.github-actions` gets yamllint plus the `github-actions` linters.
- conform: tries the whole filetype, then the most specific part first (`conform.nvim/lua/conform/init.lua:227-236`),
  so `toml.pyproject` gets pyproject-fmt and other TOML files get tombi.
- Treesitter uses the first part (`vim/treesitter/language.lua`, `get_lang`), so highlighting is unchanged.
- Cost: servers match filetypes exactly (runtime `lua/vim/lsp.lua:497-498`), so servers that should still
  attach need the new name added in `after/lsp/` (yamlls for `yaml.github-actions`, tombi for `toml.pyproject`).
  yamlls already lists compound names such as `yaml.docker-compose` (`nvim-lspconfig/lsp/yamlls.lua:74`).
- Rejected: per-tool path patterns, which every adapter (nvim-lint, conform, LSP, install prompt) would have to
  honour separately.

## Where it is built (2026-10-12)

- Built and tried in a test slot before merging. Test slots are numbered for parallel features:
  `nvimt`, `nvimt2`, `nvimt3`, ... each a worktree with its own `NVIM_APPNAME` and launcher.
- `nvimt` currently carries the ui2 branch, so this feature goes in `nvimt2`.

## Mason removal (2026-10-12)

- Done: the old Mason bin dir is off the shell PATH. The dotfiles line
  `fish_add_path $XDG_DATA_HOME/nvim/mason/bin` was removed in AH-Merii/SMS-Supercharge-My-Shell#160
  (squash-merged as 9c91fd3), and the entry was dropped from the fish universal `fish_user_paths`.
  The old `nvim` config doesn't need it: Mason prepends its own bin dir inside Neovim
  (`mason.nvim/lua/mason/settings.lua:17`, `PATH = "prepend"`).

- Assume Mason is removed. The current breakages it causes are not fixed separately: `nvimn` runs no
  language servers (mason-lspconfig only enables servers in nvimn's own, empty Mason dir), and
  rust-analyzer is broken (missing rustup component).

## Per-language tools (2026-10-12)

Bold = change from today. Struck = removed.

| Language | Language server | Formatter | Linter |
|---|---|---|---|
| Python | pyrefly + **ruff server** | ruff (conform) | ruff (nvim-lint, backstop) |
| TOML | **tombi** | **tombi**; pyproject-fmt for `pyproject.toml` | tombi |
| Lua | lua_ls | stylua | ~~luacheck~~ |
| JS / TS | **tsc** (TS 7), replaces ~~ts_ls~~ | biome | biome |
| JSON | none | biome | **biome**, replaces ~~jsonlint~~ |
| YAML | yamlls | prettierd | yamllint, actionlint, **zizmor** |
| Markdown | marksman | prettierd | **markdownlint-cli2**, replaces ~~markdownlint-cli~~ |
| HTML / CSS / SCSS | **html, cssls** | prettierd | none |
| sh / bash | **bashls** (runs shellcheck) | shfmt | ~~nvim-lint shellcheck~~ |
| Fish | fish-lsp | **fish_indent** (system) | none |
| C / C++ | clangd | clang-format (**via mise**) | none |
| Go | gopls (stale settings cleaned) | goimports **then gofumpt** | golangci-lint |
| Rust | rust-analyzer (**rustup component**) | rustfmt | clippy |
| Terraform | terraform-ls, tflint | terraform fmt | tflint, trivy |
| CMake | **neocmakelsp** | gersemi | none |
| Typst | tinymist (formats with typstyle) | ~~separate typstyle~~ | none |
| Dockerfile | **docker_language_server** | none | hadolint |
| Make | none | none | checkmake |
| PHP | ~~intelephense~~ (PHP dropped) | none | none |

Notes on specific choices:

- **Ruff**: enable the ruff server for live diagnostics and code actions; keep conform's ruff steps for
  save and nvim-lint as the backstop. Probe evidence: no duplicate diagnostics (nvim-lint skips ruff while
  the server is attached, `nvim/lua/plugins/nvim-lint.lua:48-82`); server fix + organize + format gives
  byte-identical output to conform; server formatting alone does not fix or sort imports.
- **luacheck**: dropped in favour of lua_ls diagnostics. It does work under mise
  (`github:lunarmodules/luacheck` bundles Lua 5.4); the crash was the old Mason copy on system Lua 5.5.
- **tsc**: TS 7's native server (`nvim-lspconfig/lsp/tsc.lua:11-13`). A project still on TS 5/6 is served
  by the global TS 7.
- **bashls**: runs shellcheck itself, so the nvim-lint shellcheck entry goes to avoid duplicates. shellcheck
  stays installed.
- **gofumpt**: gopls had `gofumpt = true` but conform formatted with goimports, so it never applied.
- **Typst**: tinymist already formats with typstyle (`nvim/after/lsp/tinymist.lua:5`).
- **PHP**: no longer written; intelephense and its `after/lsp` override go.

## Install specs

Verified = installed in an isolated mise dir and the binary ran (LSPs also answered `initialize`).

| Tool | Spec | Verified |
|---|---|---|
| pyrefly | `pypi:pyrefly` (decided; `pipx:` is an older alias of `pypi:`) | yes |
| clangd | `github:clangd/clangd` (decided) | yes |
| clang-format | `clang-format` (registry, conda backend) | yes |
| ruff, biome, stylua, shfmt, terraform, typstyle, tinymist, marksman, lua-language-server, terraform-ls | registry short names | yes |
| golangci-lint, shellcheck, tflint, trivy, hadolint, actionlint, checkmake, yamllint | registry short names | yes |
| fish-lsp, yaml-language-server | `npm:<name>` | yes |
| prettierd | `npm:@fsouza/prettierd` (needs node at runtime) | yes |
| gopls | `go:golang.org/x/tools/gopls` | yes |
| goimports | `go:golang.org/x/tools/cmd/goimports` (needs go at runtime) | yes |
| gersemi, pyproject-fmt | `pypi:<name>` | yes |
| rust-analyzer, rustfmt, clippy | rustup components of mise's `rust = "stable"` | rustfmt, clippy present |
| tsc | `npm:typescript` (TS 7.0.2; node needed at runtime: the npm launcher wraps the native binary) | yes |
| html, cssls (and jsonls) | `npm:vscode-langservers-extracted` (node at runtime) | yes |
| bashls | `npm:bash-language-server` (node >= 20 at runtime) | yes |
| markdownlint-cli2 | `markdownlint-cli2` (registry; node >= 22 at runtime) | yes |
| tombi | `tombi` (registry, static binary; caches SchemaStore in `~/.cache/tombi`) | yes |
| neocmakelsp | `github:neocmakelsp/neocmakelsp` | yes, caveats |
| docker_language_server | `github:docker/docker-language-server` (static binary) | yes |
| zizmor | `zizmor` (registry; exits non-zero when it has findings) | yes |
| gofumpt | `gofumpt` (registry, static binary) | yes |

Caveats from the check pass:

- **gh_actions_ls** (dropped 2026-10-12 for this reason; actionlint + zizmor cover workflows): v0.0.3, last published 2025-01-09, ~686 weekly downloads; mise's npm installer
  refuses it without `allow_low_downloads = true`. Needs `init_options = {}` (lspconfig already sets it).
- **neocmakelsp**: exits on `shutdown` without replying. Should look like a normal exit to Neovim
  (unverified).
- **zizmor**: without a GitHub token, the online-only audits are skipped; local checks run offline.
- All npm-based tools need node at runtime, which the global `node = "lts"` provides.

Watch out: `pint` in the mise registry is `aqua:cloudflare/pint` (a Prometheus linter), not Laravel Pint.

## Implementation notes (from the research, 2026-10-12)

Details the build needs that the decisions above don't spell out.

- **Test slot mechanics** (copy what `nvimt` does): a git worktree (e.g. `~/Projects/nvim-config-t2`), a
  symlink `~/.config/nvimt2 -> <worktree>/nvim`, and a launcher `~/.local/bin/nvimt2` running
  `NVIM_APPNAME=nvimt2 exec ~/.local/share/mise/installs/neovim/nightly/bin/nvim "$@"`.
  GitButler only manages the main checkout; worktrees use plain git.
- **LSP wiring**:
  - Capture each server's merged config once, then override it with `vim.lsp.config(name, {...})`, which
    merges above `after/lsp/` (lsp.txt:229-243).
  - Wrap `root_dir`: once `root_dir` is set, `root_markers` is ignored, so the wrapper calls
    `vim.fs.root(buf, markers)` itself (or chains the original `root_dir`, e.g. rust_analyzer's
    `cargo metadata`), resolves the binary asynchronously, and only calls `on_dir` when it's found.
  - `cmd` becomes a function returning `vim.lsp.rpc.start({abs, args...}, dispatchers, { cwd = root, env = env })`.
    cwd must be passed by hand: the 0.13 cwd = root_dir default only covers array cmds (news.txt:157-158).
    A function `cmd` also skips the `executable()` check that the mise shims fool.
  - After an install, re-fire `FileType` for loaded buffers under that root (or call `vim.lsp.enable` again).
- **conform**: `formatters[name] = { command = fn, env = fn }`; built-in args are inherited (`inherit`
  defaults to true). A missing tool returns an unrunnable path so conform marks it unavailable and
  `lsp_format = "fallback"` applies.
- **nvim-lint**: per-run `wrap_linter` sets `cmd`, `cwd` (else it uses `getcwd()`) and `env`; `filter`
  drops missing linters. Keep the `covering_server` table (`nvim-lint.lua:48`) that skips a linter while its
  server is attached.
- **Resolver queries** (cwd = scope root, async, stdin closed): `mise ls --current --json` (fields `source.path`,
  `installed`, `active`), `mise bin-paths` (`-C /` = global only), `mise env --json` only for tools that need a
  runtime. Strip from any PATH used: `~/.local/share/mise/shims`, `~/.local/share/mise/installs/*` and any
  `*/mason/bin`. ~25-40 ms per call.
- **Untrusted project configs**: plain `[tools]` is used by mise without trust, so the accept/decline gate is
  ours. A config with `[env]` makes every mise call in that dir fail until trusted; treat as "global only".
  *Use + install* runs `mise trust <path>` then `mise install` with cwd = root.
- **Toolchain probes**: rust-analyzer, rustfmt, cargo-clippy are rustup proxies; check with `rustup which <bin>`
  (cwd = root) and install with `rustup component add <name>`. `executable()` is not enough.
- **Explicit server list** must include servers mason-lspconfig only enabled because they were installed:
  ruff, biome, tflint. Note: today `nvimn` enables no servers at all (its own Mason dir is empty).
- **Go**: gopls `after/lsp/gopls.lua` has stale settings (e.g. the `gc_details` code lens, removed in gopls v0.18).
- **Mason code to remove**: `nvim/lua/plugins/mason.lua` (incl. `ensure_python`), the mason.nvim and
  mason-lspconfig entries in `lazy-lock.json`, `installed()` and the mason-registry relint in
  `nvim-lint.lua` (41-45, 103-117), the actionlint path autocmd (93-101, replaced by `yaml.github-actions`),
  and the comment at `core/lsp.lua:1`.
- **Tests to rework** (`tests/regress`): `refresh.lua` (`mason_sync`), `harness.lua` (`from_mason`),
  `nv.sh` PATH handling, `checks/lint_mason_relint.lua`, `areas.map`. Headless runs must never prompt
  (`vim.g.install_tools = "off"` or no UI attached); tool installs for tests go to an isolated mise dir
  (`MISE_DATA_DIR`, `MISE_CONFIG_DIR`, `MISE_GLOBAL_CONFIG_FILE`, etc. worked for the research probes).
- **Load order**: conform loads on `BufWritePre` and nvim-lint on `BufReadPre`; the resolver must be ready
  before either (unverified risk).
- **Isolation pitfall in scripts**: inside an already mise-activated shell, `mise exec npm:...` can drop node
  from PATH ("node is not a valid shim"); add `node@lts` to the exec or prepend node's bin dir.
