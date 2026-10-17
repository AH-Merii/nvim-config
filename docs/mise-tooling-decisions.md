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
- Built (2026-10-12), in `nvimt2` (worktree `~/Projects/nvim-config-t2`, branch `nvimt2/mise-tooling`), not merged:
  - resolver, catalog and sub-filetypes in `nvim/lua/tools/`;
  - prompts, `:Tools` and the lualine indicator in `nvim/lua/tools/ux.lua`;
  - the explicit server list and LSP wiring in `nvim/lua/core/lsp_servers.lua`;
  - conform and nvim-lint adapters in their plugin specs;
  - Mason removed;
  - the regression suite runs on its own isolated mise (`tests/regress/lib.sh` `mise_env`).
- Where the build departs from this record, and why: see "Deviations in the build" below.
- Follow-ups built (2026-10-12), same slot: jactionlint replaces actionlint, the indicator shows a wrench icon,
  `:Tools` offers Restart only for a server whose binary resolved, and LSP linked editing replaces nvim-ts-autotag.

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

- A prompt only the first time a project or tool is missing. After that, a quiet lualine indicator (a wrench icon
  with the missing count, e.g. `󰖷 2`, and `?` for an unanswered project config; hidden when neither applies; decided
  2026-10-12) plus a
  `:Tools` view (per tool: chosen binary, where it came from, reason if missing; install / retry / restart).
- One batched prompt per project, not per filetype. Answers remembered per project config file and asked
  again when that file changes.
- Never prompt for library code (site-packages, node_modules, cargo registry, Go module cache), git commit
  messages, help/diff/nofile buffers, or headless runs and tests.

## Where config lives (2026-10-12): option (b)

**Reopened (2026-10-17)**: D46 in `docs/rearchitecture-decisions.md` chose option (a), one file per language, and
"Step 1: lang/" there built it. Server settings, formatters, linters, covering servers and sub-filetypes now live in
`nvim/lua/lang/`; the catalog keeps the install specs. The record below is the 2026-10-12 decision.

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
| `*/.github/workflows/*.y{a,}ml` | `yaml.github-actions` | jactionlint, zizmor (lint) |
| `pyproject.toml` | `toml.pyproject` | pyproject-fmt (format) |
| `compose.y{a,}ml`, `docker-compose.y{a,}ml` and their `.<name>.` overrides (`compose.override.yaml`) | `yaml.docker-compose` | docker-language-server (server) |
| `docker-bake.hcl`, `docker-bake.override.hcl` | `hcl.docker-bake` | docker-language-server (server) |

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
  Since D46 (2026-10-17) the sub-filetypes are variants in `nvim/lua/lang/`, which give the base's servers to every
  variant and give conform and nvim-lint an explicit list for it, so neither the cost nor the plugins' rules above apply.
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
| YAML | yamlls | prettierd | yamllint, **jactionlint**, replaces ~~actionlint~~; **zizmor** |
| Markdown | marksman | prettierd | **markdownlint-cli2**, replaces ~~markdownlint-cli~~ |
| HTML / CSS / SCSS | **html, cssls** | prettierd | none |
| sh / bash | **bashls** (runs shellcheck) | shfmt | ~~nvim-lint shellcheck~~ |
| Fish | fish-lsp | **fish_indent** (fish's builtin, fish via mise; 2026-10-13) | none |
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
| golangci-lint, shellcheck, tflint, trivy, hadolint, checkmake, yamllint | registry short names | yes |
| jactionlint | `jactionlint` (registry: `github:jdx/jactionlint`; v2.1.0, static binary) | yes |
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

- **gh_actions_ls** (dropped 2026-10-12 for this reason; jactionlint + zizmor cover workflows): v0.0.3, last published 2025-01-09, ~686 weekly downloads; mise's npm installer
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

## Deviations in the build (2026-10-12)

Where the build differs from the decisions above, or fills a gap they left.

- **CMake server name**: the server is enabled as `neocmake`, nvim-lspconfig's name for neocmakelsp
  (`nvim-lspconfig/lsp/neocmake.lua`; there is no `neocmakelsp.lua`). The binary is still `neocmakelsp`.
- **Untrusted project config with `[env]`**: the prompt offers only *Use + install* and *Global only*
  (`nvim/lua/tools/ux.lua`, `ask_project`). *Installed only* could never take effect there: mise refuses every
  call in that dir until the config is trusted.
- **Library code**: besides site-packages, node_modules, the cargo registry and the Go module cache, prompts are
  also skipped in dist-packages, cargo git checkouts and rustlib sources.
- **biome server**: limited to JS/TS/JSON (`nvim/after/lsp/biome.lua`), as in the per-language table.
  nvim-lspconfig also lists HTML and CSS, where biome starts only inside a Biome project (its `root_dir` looks for
  `biome.json`). There, the install offer would have named biome on every HTML and CSS file.
- **Server root when the server finds none**: it uses the tools' project root (the nearest mise config, `.venv`,
  `node_modules`, language project file or `.git`). This gives one process per project, run from that project's
  binary. Before, every buffer without a server root shared one client, started from whichever project's binary
  came first. Only files outside any project still share a rootless client, and they all resolve the same binary.
- **Running servers restart when their binary moves**: after a refresh, an accepted project config or an install,
  a server running a different binary from the one now resolved for its root is restarted
  (`nvim/lua/core/lsp_servers.lua`). The table above only says to start servers for open files. Without the restart,
  *Use + install* left the global server running in the project.
- **Toolchain calls in `root_dir`**: gopls's `root_dir` runs `go env` and rust_analyzer's runs `cargo metadata`, both
  from Neovim's PATH. They now run with the tool's resolved PATH. Without it, go installed only through mise
  raised ENOENT, and that error stopped every other tool resolving in the same root.
- **golangcilint args**: nvim-lint builds them once, when the linter module loads, by running `golangci-lint` and
  `go` from Neovim's PATH. They are now rebuilt for the resolved binary (`nvim/lua/plugins/nvim-lint.lua`).
- **tsc root**: lspconfig's tsc `root_dir` runs `tsc --version` from PATH and warns when it isn't TS 7. It is
  replaced by one that keeps its lockfile, `.git` and Deno rules; the resolver's TS 7 check does the version part.
- **Statusline formatters**: lualine lists formatters only once their binaries are resolved, because conform's
  availability check would block a redraw on the resolver (about 84 ms cold per project).
- **Load order** (the unverified risk above): conform's `command` waits for the result (`tools.wait`). nvim-lint
  and LSP `root_dir` resolve asynchronously, and run again on `User ToolsChanged`.

Still open:

- The neocmakelsp shutdown caveat above is still unverified.

Decided since:

- **actionlint → jactionlint** (2026-10-12). mise's registry marks actionlint deprecated: `mise WARN actionlint is
  deprecated: jactionlint is an actively maintained fork of actionlint with upstream fixes merged`. jactionlint is
  `github:jdx/jactionlint` (registry name and binary `jactionlint`, v2.1.0). It replaces actionlint in the catalog
  and in the `github-actions` linters, as nvim-lint linter `jactionlint` defined in `nvim/lua/plugins/nvim-lint.lua`
  (nvim-lint has none). Evidence and choices:
  - Its CLI is GNU style: `--format '{{json .}}' --stdin-filename NAME -`; actionlint's single-dash `-format` is
    rejected ("unknown option -format; did you mean --format?"), so nvim-lint's actionlint args can't be reused.
  - Its JSON has the fields nvim-lint's actionlint parser reads (`line`, `column`, `end_column`, `kind`, `message`)
    plus `id`, `severity`, `end_line` and `doc_url`. The linter has its own parser: `severity` (`error`, `warn`, `info`,
    the levels of `--min-severity`) becomes the diagnostic severity, where actionlint's parser makes every finding a
    warning, and `id` becomes the diagnostic code.
  - It runs with `--profile correctness` ("what actionlint checks", per `--help`). The default profile adds security
    rules zizmor already reports: on one test workflow it added concurrency-limits, missing-timeout,
    missing-permissions, unpinned-uses and artipacked to the unknown-runner-label finding both profiles report. The
    flag overrides a `profile` set in a project's `.github/jactionlint.yaml`; that file's per-rule levels still apply.

## Follow-up decided alongside (2026-10-12): nvim-ts-autotag → LSP linked editing

- Drop `windwp/nvim-ts-autotag` (`nvim/lua/plugins/auto-pairs-tags-comments.lua:308-312`) once the html server from
  this feature is in. Paired-tag rename comes from `vim.lsp.linked_editing_range.enable(true, { client_id = … })`
  on LspAttach for clients that support `textDocument/linkedEditingRange` (runtime doc/lsp.txt:2621-2641).
- Accepted loss: auto-closing a tag on `>` (no core equivalent).
- Built (2026-10-12) in `nvimt2`: nvim-ts-autotag is gone from the plugin spec and `lazy-lock.json`, and
  `nvim/lua/core/lsp.lua` enables linked editing per client on LspAttach.
- Which servers advertise it, probed 2026-10-12 (each server started on a matching file, `initialize` answer read,
  `linkedEditingRangeProvider` and `client:supports_method("textDocument/linkedEditingRange")`):
  - yes: html (vscode-langservers-extracted 4.10.0; on `<div><p>x</p></div>` it returned both `div` names) and tsc
    (typescript-go 7.0.2; in a `.tsx` file it returned both names of a JSX tag);
  - no: cssls, biome 2.5.15, marksman, yamlls 1.25.0, lua_ls 3.19.1, pyrefly 1.3.2, ruff 0.17.0, bashls, clangd 23.1.0,
    tombi 1.8.1.

## Follow-up decided alongside (2026-10-12): the tree-sitter CLI joins the catalog

- The tree-sitter CLI becomes a catalog tool, spec `tree-sitter` (registry, `mise registry tree-sitter` maps it to
  `aqua:tree-sitter/tree-sitter`). Recorded only: built after the mise build lands.
- Trigger: nvim-treesitter's parser install runs `tree-sitter build` (`nvim-treesitter/lua/nvim-treesitter/install.lua:305-316`).
  Without the CLI it logs `Error during "tree-sitter build"` (`install.lua:315`) and fails silently; the config tries
  each language once per session (`nvim/lua/plugins/nvim-treesitter.lua:178,189`).
- With this, the first failed build offers the global install like any other missing tool, under the same UX rules
  (offered once, never headless).
- Why: a fresh machine without the CLI silently loses the parser of every language that isn't bundled. It works on
  this machine only because `tree-sitter = "latest"` was set globally on 2026-10-12.

## `:Tools` review, case by case (2026-10-13)

Walking through every resolver case with the user, from screenshots of `:Tools` in `nvimt2`. Built 2026-10-13 in
`nvimt2`, branch `nvimt2/tools-ux-review`; see "Built from this review" at the end of this section.

- **Rows fit the window.** Names are padded to the longest name, not 28 columns. Roles come right after the name as
  plain words (`lsp, formatter, linter`), so they are never what gets cut off. A found tool shows its source and
  version (`global mise · 0.17.0`), not its install path. A missing tool shows `not installed · install`, not the
  mise command. The last row is `Rescan tool sources` (renamed from "Retry all" during case 3).
  - Why: the rows ran past the picker's edge and hid the roles, while 20 columns stayed blank.
- **A tool's menu only acts on that tool.** Pressing a row offers `Start <server>` or `Restart <server>` (whichever
  applies), and `Install` when it is missing. It does not offer "Retry: resolve it again".
  - Why: that entry refreshes every tool in the folder (`tools.refresh(root)`), which is misleading from one tool's
    menu. Looking tools up again stays as the `Rescan tool sources` row in the main list.
  - Rejected: renaming it "Look for it again" (still misleading).
- **The statusline's linters list shows only linters that will run**, like the LSP and formatter lists: not ones
  whose binary is missing, and not ones whose covering server is attached.
  - Why: in `~` it listed `ruff` as a linter while ruff was missing everywhere, because it showed the configured list
    (`lualine.lua:150-154`).
- **A project mise config that pins no tools is ignored**: no project question, no row in `:Tools`. Exception: an
  untrusted config that sets `[env]`, because mise refuses to run in that folder until it is trusted.
  - Why: `~/Projects/nvim-config/mise.local.toml` only sets `CLAUDE_CODE_PLUGIN_DIRS`, yet it was asked about.
- **Case 1 (outside a project, tool found): no prompt.** A server tool's menu holds `Start`/`Restart <server>` only;
  a tool without a server opens no menu and instead notifies its full path, e.g.
  `stylua 2.6.0 · global mise · <path>`.
- **Case 2 (outside a project, tool missing): the prompt names no command.**
  `python needs pyrefly and ruff` / `Install them globally with mise` /
  `Not now (won't ask again; install later from :Tools)`. One tool: `Install it globally with mise`; a tool's
  `:Tools` menu: `Install globally with mise`. Progress reads `Installing pyrefly, ruff`; the result notification
  reads `Installed pyrefly and ruff`, or `Couldn't install ruff` followed by mise's error.
  - Why: the user doesn't need the command; "globally with mise" says where and how, and sets it apart from the
    project installs of cases 4-6.
- **Case 3 (project `.venv`/`node_modules` has the tool): it wins, silently.** The row reads
  `project .venv · 0.15.0` (or `project node_modules · …`). A tool the project env lacks falls through to case 1 or 2;
  Neovim never installs into a project's `.venv` or `node_modules`.
- **Case 4 (project mise config pins the tool, answered "use + install").** The project question becomes
  `Use this project's mise.toml?` / `Yes, and install ruff (trusts mise.toml)` (just `Yes (trusts mise.toml)` when
  nothing is missing) / `Only versions already installed` / `No, use my global tools`. No path or version list in
  the question; `:Tools` shows them (`project mise · 0.15.0`). The answer row in `:Tools` reads
  `Use mise.toml? yes, install missing`; picking it asks again.
  - Why: the old question named the full path, every pin and the command, and ran past the picker.
  - **`.venv`/`node_modules` vs a mise pin: ask on conflict.** When the project config is in use and a tool is found in
    both with different versions, ask once per project: `ruff is in .venv (0.16.0) and mise.toml (0.15.0)` /
    `Use .venv's 0.16.0` / `Use mise.toml's 0.15.0`. Same version: no question. The answer is remembered and can be
    switched from the tool's `:Tools` menu (`Use mise.toml's 0.15.0 instead`).
    - Rejected: `.venv` always wins (the user wants to be able to say no); a switch only in `:Tools` (hard to find);
      one project-wide answer in the mise.toml question (makes that question longer for a rare case).
- **Prompt titles don't say "which is not installed".** The prompt only appears for missing tools, so the title is
  just `python needs pyrefly and ruff` (case 2) or `python needs ruff 0.15.0 (pinned by mise.toml)` (case 5).
- **Case 5 (pinned, answered "only versions already installed").** A pinned version that is installed is used. A
  missing one can be installed for the project without trusting it: `mise install ruff@0.15.0` run outside the
  project installs into mise's shared store, leaves the project untrusted and its config unchanged, and the
  project then resolves to it (probed 2026-10-13 in a scratch mise: `mise trust --show` still `untrusted`,
  `mise which ruff` -> `installs/ruff/0.15.0/.mise-bins/ruff`).
  - No global copy: prompt `python needs ruff 0.15.0 (pinned by mise.toml)` / `Install 0.15.0 for this project with
    mise` / `Install it globally with mise (latest)` / `Not now (won't ask again; install later from :Tools)`.
  - A global copy exists: no prompt; it is used, the row reads `global mise · 0.17.0 (project wants 0.15.0)`, and the
    tool's `:Tools` menu adds `Install 0.15.0 for this project with mise`.
  - "For this project", not "locally": the version lands in mise's shared store, not in the project folder.
  - Still different from "Yes": that trusts the config (its `[env]` and hooks apply) and installs every pin up front.
- **Case 6 (pinned, answered "No, use my global tools").** The project's mise config is skipped; a project
  `.venv`/`node_modules` still applies; then global mise, then the system PATH; a missing tool gets the case 2 prompt,
  never a project install. A row whose version differs from the pin still notes it:
  `global mise · 0.17.0 (project wants 0.15.0)`. The answer row reads `Use mise.toml? no`.
  - Why: the user wants to see when the editor runs a different version than the project expects, even when the
    config is ignored. Rejected: hiding the note as noise.
- **`:Tools` names the pins once, on the answer row** (decided after case 7): `Use mise.toml (pyrefly 1.3.0, ruff
  0.15.0)?`, at most three pins then `+N more`, only the pins this filetype uses. Tool rows then drop the
  `(project wants …)` note, which replaces what cases 5 and 6 said about rows; prompts keep their pinned-version text.
  - Why: the answer row already shows what the project wants, so repeating it per tool is noise.
- **The answer row says what picking it does, not the current answer**: `Choose how to use mise.toml (pyrefly 1.3.0,
  ruff 0.15.0)`; picking it asks the mise.toml question again. Replaces the `Use mise.toml? …` row text above. The
  current answer is visible from the tool rows' sources (`project mise` vs `global mise`).
  - Why: showing the answer on the row was confusing. Rejected: `Change mise.toml settings` (suggests editing the file).
- **The mise.toml row is a direct action, named for what it does** (replaces the two row entries above): while the
  config is not fully in use ("No" or "Only versions already installed") the row reads
  `Use mise.toml (pyrefly 1.3.0, ruff 0.15.0) · trusts it`, and picking it trusts the config, installs the missing
  pins and uses them (the "Yes" answer), with no further menu. While it is in use ("Yes") the row reads
  `Stop using mise.toml (pyrefly 1.3.0, ruff 0.15.0)` and picking it switches to global tools ("No").
  "Only versions already installed" stays a choice in the first-time prompt only.
  - Why: the user wants the row to say what picking it will do, not the current state, and no nested menu.
    `· trusts it` stays because picking the row is the trust decision.
  - Rejected: `Choose how to use mise.toml` (vague); showing the current answer on the row (confusing).
- **Case 8 (untrusted project config that sets `[env]`).** mise refuses every call in the folder, so the pins can't
  be read; tools resolve globally (and from a project `.venv`/`node_modules`). The first-time prompt stays:
  `Trust this project's mise.toml? (it sets environment variables)` / `Yes, trust it and install its tools` /
  `No, use my global tools`. The `:Tools` row reads `Trust mise.toml and use its tools` (no versions: mise hides the
  pins until it is trusted); picking it trusts, installs and uses them.
  - Note: trusting it in a terminal (`mise trust`) leaves the file unchanged, so Neovim only sees it after
    `Rescan tool sources`.
- **Case 9 (a copy fails the version check; today only tsc, which needs TypeScript 7+).** Rejected copies are
  skipped in the usual order. A found copy notes what was skipped: `global mise · 7.0.2 (project's 5.9.3 is too old)`
  (a note, no action: upgrading the project is not the editor's job). If none passes, the prompt reads
  `typescript needs tsc 7 or newer (project has 5.9.3)` / `Install it globally with mise` / `Not now (…)`.
- **Case 10 (a tool needs a runtime: node or go).** mise installs npm tools without node (its embedded aube package
  manager) but never adds node, and the tool then fails to run (probed 2026-10-13 in a scratch mise with no node on
  PATH: `mise use -g npm:yaml-language-server@1.25.0` succeeded, running it gave `exec: node: not found`;
  https://mise.jdx.dev/dev-tools/backends/npm.html: "Add `node` to `[tools]` … but never adds it for you").
  - So an install of a tool whose runtime is missing installs the runtime in the same step:
    `yaml needs yaml-language-server` / `Install it and node globally with mise`. Same for go (gopls, goimports,
    golangci-lint).
  - When the runtime goes missing later (removed, or the tool came from outside Neovim): row
    `✗ yaml-language-server  lsp  needs node · install`, prompt `yaml needs node to run yaml-language-server` /
    `Install node globally with mise`; the tool menu entry reads `Install node globally with mise`.
- **Case 11 (rustup components: rust-analyzer, rustfmt, clippy).** Checked with `rustup which <tool>` in the project
  folder, since rustup's stand-ins exist either way. Missing: `rust needs rust-analyzer` / `Install it with rustup`
  (naming the toolchain when the project pins one: `Install it with rustup (toolchain 1.92)`), run in the project so
  it lands in that project's toolchain. No rustup: `Install Rust globally with mise, then add rust-analyzer`. Rows:
  `not installed · install`, and once found `rustup · stable` (the toolchain, not a version).
- **Case 12 (a tool mise can't install).** fish joins the catalog after all: spec `github:fish-shell/fish-shell`
  (not in mise's registry by name, but its GitHub releases ship a Linux binary; probed 2026-10-13: `mise install
  github:fish-shell/fish-shell@latest` installed fish 4.9.3 as a single `fish` binary). The formatter runs
  `fish -c 'builtin fish_indent'`, since fish 4 has fish_indent as a builtin (`printf … | fish -c 'builtin
  fish_indent'` indented the input, exit 0). Prompt: `fish needs fish` / `Install it globally with mise`.
  - Side effect: `mise use -g` puts mise's fish ahead of `/usr/bin/fish` on the terminal PATH; the login shell is
    unaffected.
  - That leaves no catalog tool mise can't install. The `kind = "none"` path stays for future ones: no prompt, still
    counted in the wrench, row `not installed · install <x> with your package manager`, picking it shows that advice.

### Built from this review (2026-10-13)

Where the build fills a gap the cases above left, or departs from them:

- **The pickers size themselves to their rows.** `vim.ui.select` here is snacks' picker, whose `select` layout is
  `width = 0.5, min_width = 80, max_width = 100` (`snacks.nvim/lua/snacks/picker/config/layouts.lua:144-151`), so
  rows past 100 columns were cut whatever their format. Every Tools picker passes its own width through
  `opts.snacks` (`snacks/picker/select.lua:70-73`): the longest row or title plus room for the numbers and borders,
  up to the screen's width (`select` in `nvim/lua/tools/ux.lua`). Asked for by the user during the build.
- **fish needs 4.1 or newer.** `builtin fish_indent` came in fish 4.1.0: "The fish_indent and fish_key_reader programs
  are now also available as builtins" (https://fishshell.com/docs/current/relnotes.html). The catalog's version
  check, which only tsc had (`accept`), became `min = "<version>"` for both: tsc `"7"`, fish `"4.1"`.
- **fish-lsp lists fish in `requires`.** fish-lsp 1.1.4 runs `$fish_lsp_fish_path` or `fish` from PATH for its
  features, and `fish_indent` from PATH only for its own formatting (`execFile("fish_indent", …)` in
  `fish-lsp/dist/fish-lsp`). conform formats fish files, so the server's formatting is only the fallback.
- **Which copy wins before the conflict question is answered**: the project env, as before. A dismissed question is
  asked again next session.
- **Case 5's offer** (`Install 0.15.0 for this project with mise`) is made when a global or system copy runs, not when
  a `.venv`/`node_modules` copy does: that copy already wins over the pin.
- **Roles of a tool another one calls** read `used by <server>` (shellcheck: `used by bashls`), keeping the roles
  column short.
- **`:Tools retry` is now `:Tools rescan`**, matching the row.
- **The linters list and nvim-lint share one check** (`nvim/lua/tools/lint.lua`): `covering_server` moved there from
  `nvim/lua/plugins/nvim-lint.lua`, with the "will this linter run" test both use.
