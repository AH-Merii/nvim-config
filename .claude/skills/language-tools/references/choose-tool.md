# Steps 1-2: the plugin's definition and the mise spec

Every command here is read-only. Queries that touch mise go through `scripts/iso-mise.sh`, which keeps them away from the user's mise. Start each Bash call with:

```sh
R=<repo root>; SK=$R/.claude/skills/language-tools/scripts
L=~/.local/share/nvimt2/site/pack/core/opt   # this config's plugins (NVIM_APPNAME=nvimt2); else $R/tests/regress/data/nvim/site/pack/core/opt
T=<your isolated dir>               # made once: mkdir -p ~/.cache/language-tools && mktemp -d -p ~/.cache/language-tools
```

## 1.1 Read the built-in definition (always)

Each plugin ships one file per tool. Read it before you write any wiring:

```sh
ls $L/nvim-lspconfig/lsp/ | grep -i <part of name>            # servers
ls $L/conform.nvim/lua/conform/formatters/ | grep -i <part>   # formatters
ls $L/nvim-lint/lua/lint/linters/ | grep -i <part>            # linters
cat <the file>
```

What to take from it:

- **The name.** The file name is the name for a language file's `servers`, `formatters` and `linters`, and the catalog's role lists. It is often not the tool's own name: `terraform fmt` is conform's `terraform_fmt`, biome's linter is nvim-lint's `biomejs`, Lua's language server is `lua_ls`.
- **The binary**, from `cmd` (servers, linters) or `command` (formatters). The catalog is keyed by it, because the resolver looks for that file name:

  | Plugin name | Binary (catalog key) | Where |
  |---|---|---|
  | server `neocmake` | `neocmakelsp` | `nvim/lua/tools/catalog.lua:109` |
  | formatter `terraform_fmt` | `terraform` | `catalog.lua:104` |
  | linter `biomejs` | `biome` | `catalog.lua:60` |
  | linter `clippy` | `cargo-clippy`, which runs `cargo` | `catalog.lua:100` |

- **The args.** For a server, everything after the first element of `cmd` goes in the catalog: `cmd = { "tombi", "lsp" }` gives `servers = { tombi = { "lsp" } }`, and `cmd = { "clangd" }` gives `servers = { clangd = {} }`. For formatters and linters, the args are how step 3 must run the tool.
- **Where it applies.** A server's `filetypes`; whether a linter reads stdin.

Why this is a hard step: a definition of your own for a tool the plugin ships (an `opts.formatters.<new name>` running the same binary as a conform formatter, a `lint.linters.<name>` table for a linter nvim-lint has) shadows or duplicates the maintained one, and it drifts as upstream fixes its args and parser. `check.sh` fails on both cases.

You write a definition only when no file exists. For a linter, see `edit-files.md`, "Linter" (jactionlint is the example). For a formatter, see "Formatter". For a server, nvim-lspconfig must have it: `lsp/init.lua` (`setup`) warns on unknown names, and `checks/startup.lua` fails on that warning.

## 1.2 Find the mise spec

1. **The registry first:**

   ```sh
   $SK/iso-mise.sh $T mise registry <tool>
   ```

   If it prints backends (`mise registry ruff` printed `aqua:astral-sh/ruff asdf:simhem/asdf-ruff`), the spec is the short name, `ruff`. Use the short name whatever backend it prints (`aqua:`, `core:`, ...). Exit 1 with `tool not found in registry` means you need a backend spec.

2. **Find the upstream repo before trying backends.** Guessed owners 404: earlier runs guessed the language's org or a similarly named user and lost time on `package not found`. Find it in one of these, and quote where you found it:
   - the server's `---@brief` URL at the top of `nvim-lspconfig/lsp/<name>.lua`;
   - conform's `meta.url` in the formatter file;
   - nvim-lint's README table, which links every linter: `grep -n -i '<name>' $L/nvim-lint/README.md`, then the link line it points to;
   - package metadata: `curl -s https://crates.io/api/v1/crates/<name>` (`.crate.repository`), `https://pypi.org/pypi/<name>/json` (`.info.project_urls`), `https://registry.npmjs.org/<name>` (`.repository.url`).

3. **Then query backends on that repo or package,** in this order, and take the first that prints a version:
   1. `aqua:<owner>/<repo>`, then `github:<owner>/<repo>`: a prebuilt binary, nothing to build.
   2. `npm:<pkg>`, `pypi:<pkg>`, `go:<module path>`: when the tool ships that way. These need `runtime` (1.3).
   3. `cargo:<crate>` last: it compiles from source and needs rust.

   ```sh
   $SK/iso-mise.sh $T mise latest aqua:<owner>/<repo>
   ```

   - A version means the spec works: `mise latest github:clangd/clangd` printed `23.1.0`, and `mise latest npm:intelephense` printed `1.18.5`.
   - `mise ERROR ... not found` with exit 1 means it doesn't.
   - A transient `502 ... fallback=true` WARN followed by a version is fine.
   - A `deprecated [ubi]` WARN means: use `github:` instead.

4. **Known traps** (from `docs/mise-tooling-decisions.md`):
   - `pint` is `aqua:cloudflare/pint`, a Prometheus linter, not Laravel Pint.
   - `actionlint` is deprecated for `jactionlint`. `mise registry` and `mise latest` don't show deprecations; only the install does. Read the `mise use` output in step 3 for `mise WARN <tool> is deprecated: ...`, and switch to the tool it names.
   - `pipx:` is an older alias of `pypi:`.
   - mise's npm installer refuses low-download packages without `allow_low_downloads`.

5. Write the spec **without** a version. Refresh and the install offer add `@latest` themselves (`nvim/lua/tools/init.lua:218`, `tests/regress/refresh.lua`).

## 1.3 The other catalog fields

The fields are documented at `nvim/lua/tools/catalog.lua:4-14`.

| Field | Set it when | Example |
|---|---|---|
| `project` | Projects may pin their own copy, in `.venv/bin` (`venv`) or `node_modules/.bin` (`node_modules`) | ruff, biome |
| `runtime = "node"` / `"go"` | The binary needs node or go on PATH at run time: every `npm:` tool, and go tools that call go | `catalog.lua:59,63,92` |
| `runtime = "rust"` with `component` | A rustup component (rust-analyzer, rustfmt, clippy). Leave out `spec` | `catalog.lua:95-97` |
| `requires = { "<catalog binary>" }` | The tool calls another catalog binary at run time | bashls requires shellcheck, `catalog.lua:74` |
| `min = "<version>"` | Older versions don't work; an older copy is skipped and noted in `:Tools` | tsc `"7"`, fish `"4.1"`, `catalog.lua:54,82` |
| no `spec` | Nothing mise can install provides it; `:Tools` says to use the system package manager | none today |

A new runtime kind needs an entry in `M.runtimes` (`catalog.lua:23-27`). Add one only if step 3 shows the tool fails without it.

## 1.4 Check the choice

- **It must do the job on real files.** In step 3, also run it on one real file of this repo if the language exists here. A linter that floods a normal file with false positives (for example, Lua globals like `vim`) needs a config file. Report that to the user as an open point; don't add config files to their projects.
- **Version coupling.** Some servers must match their compiler's or runtime's version, and `@latest` of each can differ. Read the tool's README for this, compare the versions `mise latest` prints, and report the pairing as an open point.
- **Duplicate diagnostics.** If a server already runs this linter's rules, the linter needs `covered_by` (`edit-files.md`, "Linter"). Leave it out when the server reports different rules (yamlls and yamllint): the linter would go quiet whenever the server attaches.
