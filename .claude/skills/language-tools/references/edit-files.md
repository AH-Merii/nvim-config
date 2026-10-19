# Step 4: edit the config

Paths are relative to the repo root `R`. Line numbers are from the commit this skill was written against, so find the spot by its text, not by its number.

## Files to touch

Work down the table. For each row, either make the edit or note why it does not apply. "Always" rows apply to every change.

| # | File | When | Section |
|---|---|---|---|
| 1 | `nvim/lua/tools/catalog.lua` | Always: one entry per binary | Catalog |
| 2 | `nvim/lua/lang/<lang>.lua`, `servers` | Each new server, with its settings | Server |
| 3 | `nvim/lua/lang/<lang>.lua`, `formatters` | Each new formatter. Skip it if the server formats and LSP formatting is enough (Typst: tinymist) | Formatter |
| 4 | `nvim/lua/lang/<lang>.lua`, `linters` | Each new linter | Linter |
| 5 | `nvim/lua/lang/<lang>.lua`, `variants` | The tool runs only on some files of a filetype | `sub-filetypes.md` |
| 6 | `nvim/lua/lsp/init.lua`, `roots` | nvim-lspconfig's `root_dir` runs the tool from PATH or checks its version | Custom root |
| 7 | `definitions` in `nvim/lua/format/conform.lua` or `nvim/lua/linting/nvim_lint.lua` | Only a formatter's extra args, or a definition conform or nvim-lint lacks | Formatter, Linter |

You never edit these: `:Tools`, the install prompts, the statusline, `:Status`, `nvim/lua/lsp/init.lua`, conform's `formatters_by_ft`, nvim-lint's `linters_by_ft`, the server list. They are built from, or ask, `nvim/lua/lang/` (`lang.views()`, `lang.of()`).

## A language file

One file per language, `nvim/lua/lang/<lang>.lua`, returns data; its fields are documented at the top of `nvim/lua/lang/init.lua` (`lang.Spec`). A new language is a new file; `lang/init.lua` reads every file in the directory. A language with one server, one formatter and one linter (`nvim/lua/lang/toml.lua`):

```lua
---@type lang.Spec
return {
  filetypes = { "toml" },
  servers = { tombi = {} },
  formatters = { "tombi" },
  linters = { tombi = { covered_by = "tombi" } },
}
```

The keys are the Neovim filetypes (`:set ft?` in a file of that language), not file extensions. Each filetype belongs to one language; two files declaring one fail at startup.

## Catalog

The catalog lives in `nvim/lua/tools/catalog.lua`, inside `M.tools`. Put the entry under a `-- <Language>` comment, as the existing groups are. Key it by the **binary name**, and use `["..."]` when the name has a dash. Each role name goes in exactly one entry.

**One binary, three roles** (tombi: server, formatter and linter):

```lua
  -- TOML
  tombi = { spec = "tombi", servers = { tombi = { "lsp" } }, formatters = { "tombi" }, linters = { "tombi" } },
```

**Server with no args, plus a separate formatter binary.** This is the shape for a new language:

```lua
  -- C / C++
  clangd = { spec = "github:clangd/clangd", servers = { clangd = {} } },
  ["clang-format"] = { spec = "clang-format", formatters = { "clang_format", "clang-format" } },
```

**Formatter added to an existing language** (gofumpt). It is one new line; nothing else in the Go group changed:

```lua
  gofumpt = { spec = "gofumpt", formatters = { "gofumpt" } },
```

**Linter that projects may pin in a venv** (zizmor):

```lua
  zizmor = { spec = "zizmor", project = venv, linters = { "zizmor" } },
```

**npm server**: `runtime = "node"` is required, see `choose-tool.md` 1.3:

```lua
  ["yaml-language-server"] = { spec = "npm:yaml-language-server", project = node_modules, runtime = "node", servers = { yamlls = { "--stdio" } } },
```

If the catalog lacks a name, nothing fails. The tool then runs from Neovim's PATH and is never offered for install. `check.sh` (its audit) is what catches this.

## Server

Add the nvim-lspconfig name (not the binary name) under `servers`. Its value is a table of `vim.lsp.Config` fields, merged over nvim-lspconfig's `lsp/<name>.lua` with `vim.lsp.config(name, ...)` (`lsp/init.lua`); `{}` when nvim-lspconfig's config is enough:

```lua
-- before
  servers = { gopls = { ... } },
-- after
  servers = { gopls = { ... }, ["<nvim-lspconfig name>"] = {} },
```

A server is configured in one language only; another language or a variant that also wants it names it without settings (a variant lists it in its `servers` list, see `sub-filetypes.md`).

- A name with no catalog entry, or with no nvim-lspconfig config, warns at startup (`lsp/init.lua`, `setup`), and `checks/startup.lua` fails on that warning. `tests/unit/lang_test.lua` fails on the first case too.
- A catalog server no language names fails `tests/unit/lang_test.lua` ("catalog server ... is named by a language").

Fields you may need:

- **`filetypes`**: where the server attaches, when that differs from the language's `filetypes`. Narrow it when nvim-lspconfig lists filetypes another language owns, or widen it to keep nvim-lspconfig's extras (`nvim/lua/lang/c.lua`: clangd also serves objc and cuda). Variants of the listed filetypes get the server too, so a variant never needs listing here. Leaving it out gives the language's filetypes, which replace nvim-lspconfig's list (`nvim/lua/lang/web.lua`: biome serves only JS, TS and JSON).
- **Share one position encoding** when the server shares a filetype with pyrefly (`ruff` in `nvim/lua/lang/python.lua`). `checks/lsp_attach.lua` fails when one buffer's clients use mixed encodings.
- **Settings**: `settings`, `capabilities`, `root_markers`, `on_init`, `commands`, `handlers`; see gopls (`go.lua`), rust_analyzer (`rust.lua`) and pyrefly (`python.lua`).
- **No `exit_timeout` for quitting.** `lsp/init.lua`'s VimLeavePre handler stops every server on quit, one that is
  still starting or busy included, so a server that orphans children or exits slowly needs nothing here (#42).

Do not set `cmd` (`wiring()` replaces it with the resolved binary plus the catalog args). Do not merge blink capabilities either; blink sets them for every server through `vim.lsp.config('*')` (`blink.cmp/plugin/blink-cmp.lua:1-7`).

## Custom root

Add a custom root only when nvim-lspconfig's `root_dir` runs the tool or a version check from PATH. tsc's `root_dir` runs `tsc --version`, so `roots.tsc` in `nvim/lua/lsp/init.lua` replaces it, and the version check moved to the catalog's `min`.

A `root_dir` that runs the language's toolchain (`go env`, `cargo metadata`) already runs with the tool's PATH (the `root_dir` that `wiring()` returns in `lsp/init.lua`), so it needs no root entry.

## Formatter

List conform names under `formatters`, in the order they run. The value **must be a plain list of names**; conform's own function form and nested alternatives are not supported (the adapter loop in `nvim/lua/format/conform.lua` wires each name to the resolver).

To pick a formatter per file, use a variant (`sub-filetypes.md`). That is how the old pyproject.toml chooser function was replaced.

Before and after for gofumpt (`nvim/lua/lang/go.lua`):

```lua
-- before
  formatters = { "goimports", filetypes = { "go" } },
-- after
  formatters = { "goimports", "gofumpt", filetypes = { "go" } },
```

`filetypes` on the list limits it to some of the language's filetypes (Go formats only `go`; `gomod` falls back to LSP formatting).

- **Extra args** go under `definitions.<name>` in `nvim/lua/format/conform.lua`, by tool rather than by language (conform keys formatters by name for every filetype). The resolver wrapper keeps them (the `tbl_extend` in `M.setup`):

  ```lua
  local definitions = {
    shfmt = { prepend_args = { "-i", "2", "-kp" } },
  }
  ```

- **A formatter conform does not ship** needs a full definition under `definitions.<name>` in `nvim/lua/format/conform.lua` (`command = "<bare binary name>"`, `args`, `stdin`), plus its catalog entry. The wrapper replaces `command` with the resolved path. Check first that no conform file runs the same binary (`grep -l 'command = "<binary>"' $L/conform.nvim/lua/conform/formatters/*.lua`): if one does, use its name. `check.sh` fails on a definition that duplicates a built-in.

## Linter

1. Add the nvim-lint name under `linters`, with a table of options (`{}` for none). For a variant, add it to the variant's `linters`; the base's linters still run there:

   ```lua
       ["yaml.github-actions"] = {
         ...
         linters = { jactionlint = {}, zizmor = {} },
       },
   ```

   `filetypes = { ... }` limits a linter to some of the language's filetypes (tflint and trivy run only on `terraform`).
2. **Covered by a server?** Some servers report the same findings as a linter, because they run the same tool: ruff, biome, tombi, tflint, and rust_analyzer for clippy. For those, name the server (`nvim/lua/lang/python.lua`):

   ```lua
     linters = { ruff = { covered_by = "ruff" } },
   ```

   The linter then stays quiet while that server is attached (`linting.plan(buf).covered` reads them). Leave it out when the server's diagnostics are different rules from the linter's: for example, yamlls and yamllint.
3. **No nvim-lint definition?** Only then write one. Check both the name and the binary: `ls $L/nvim-lint/lua/lint/linters/<name>.lua` and `grep -l "cmd = .<binary>." $L/nvim-lint/lua/lint/linters/*.lua`. If either finds a file, use that linter's name and don't define one of your own; to change its args, put only `args` under `definitions.<name>` in `nvim/lua/linting/nvim_lint.lua`, which is merged over the built-in. If both are empty, define it under `definitions` in `nvim/lua/linting/nvim_lint.lua`, as jactionlint is. Set `cmd` to the **bare binary name**; `wrap_linter` in `M.lint` there swaps in the resolved path. Write the parser for the JSON the tool prints, which you saw in `verify.md` section 2:

   ```lua
       jactionlint = {
         cmd = "jactionlint",
         stdin = true,
         args = { "--format", "{{json .}}", "--profile", "correctness", "--stdin-filename", function() return vim.api.nvim_buf_get_name(0) end, "-" },
         ignore_exitcode = true, -- exits 1 when it has findings
         parser = function(output) ... end,
       }
   ```

4. **Rare cases:**
   - `keep_cwd[name] = true` in `nvim/lua/linting/nvim_lint.lua` is for a parser that matches paths relative to Neovim's cwd (tflint).
   - Rebuild a linter's args per resolved binary when its nvim-lint module runs the tool from PATH while loading. golangcilint does this (`golangcilint_args` in `nvim/lua/linting/nvim_lint.lua`); read the module's top lines to check.

## Treesitter

Nothing to edit. A language file names no parsers (D119 in `docs/rearchitecture-decisions.md`): `parsers.needed(ft)` in `nvim/lua/parsers/init.lua` derives them from the filetype's own parser and the languages its injections query names, and installs them when a buffer first needs them. Check what a filetype gets with `:lua =require("parsers").needed("<ft>")`, or in `:Tools`.

`tests/regress/refresh.lua` pre-seeds the suite with what every declared filetype needs, so a new language's parsers come with the next `--refresh`.

Once a parser is there, the buffer gets treesitter's highlighting and indent. Declare `treesitter` in the language's file only when something must stay beside it (D128), with the reason in a comment:

```lua
-- nvim/lua/lang/python.lua
treesitter = {
  indent = false, -- keep the runtime's indent plugin (indent/<ft>.vim): treesitter's indents <case> wrong
  syntax = true, -- keep regex syntax on beside treesitter: <what reads it, e.g. that indent plugin>
},
```

Regex syntax can't go in `options` (`syntax = "ON"`): `vim.treesitter.start` turns it off after FileType. A capture the language's query lacks goes in `nvim/queries/<parser>/<query>.scm`, starting with `;; extends` so it adds to nvim-treesitter's query instead of replacing it (D135: `(pipe_table_cell) @spell` for markdown). Variants get their base's settings. `tests/regress/checks/treesitter_lang.lua` checks every declared filetype against its settings; add a check of the behaviour the setting is for, as `python_indent.lua` does.

## Areas

`tests/regress/areas.map` already maps `lua/lang/*`, `lua/tools/*` and `lua/lsp/init.lua`. Add a line only for a new config file outside those globs. An unmapped file makes `--changed` run every area.
