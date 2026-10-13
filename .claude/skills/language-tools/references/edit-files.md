# Step 4: edit the config

Paths are relative to the repo root `R`. Line numbers are from the commit this skill was written against, so find the spot by its text, not by its number.

## Files to touch

Work down the table. For each row, either make the edit or note why it does not apply. "Always" rows apply to every change.

| # | File | When | Section |
|---|---|---|---|
| 1 | `nvim/lua/tools/catalog.lua` | Always: one entry per binary | Catalog |
| 2 | `nvim/lua/core/lsp_servers.lua`, `M.servers` | Each new server | Server |
| 3 | `nvim/after/lsp/<server>.lua` | The server needs settings or a different filetype list, shares a filetype with pyrefly, or must attach on a sub-filetype | Server overrides |
| 4 | `nvim/lua/core/lsp_servers.lua`, `roots` | nvim-lspconfig's `root_dir` runs the tool from PATH or checks its version | Custom root |
| 5 | `nvim/lua/plugins/conform.lua` | Each new formatter. Skip it if the server formats and LSP formatting is enough (Typst: tinymist) | Formatter |
| 6 | `nvim/lua/plugins/nvim-lint.lua` | Each new linter | Linter |
| 7 | `nvim/lua/tools/filetypes.lua` | The tool runs only on some files of a filetype | `sub-filetypes.md` |
| 8 | `nvim/lua/plugins/nvim-treesitter.lua`, `ensure_installed` | A new language with a tree-sitter parser | Treesitter |
| 9 | `tests/regress/areas.map` | Only a new config file that no glob there matches | Areas |

You never edit these: `:Tools`, the install prompts, lualine, `:Status`, `nvim/lua/plugins/lspconfig.lua`. They all read the tables above.

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

Add the nvim-lspconfig name (not the binary name) to `M.servers` in `nvim/lua/core/lsp_servers.lua`. Put it next to its language's neighbours:

```lua
-- before
  "neocmake",
  "tinymist",
  "docker_language_server",
}
-- after
  "neocmake",
  "tinymist",
  "docker_language_server",
  "<nvim-lspconfig name>",
}
```

Both directions are enforced:

- A listed name with no catalog entry, or with no nvim-lspconfig config, warns at startup (`lsp_servers.lua:213-222`), and `checks/startup.lua` fails on that warning.
- A catalog server missing from the list fails `checks/lsp_attach.lua` ("every catalog server is enabled").

## Server overrides: `nvim/after/lsp/<server>.lua`

The file name must be the nvim-lspconfig server name. `checks/lsp_configs.lua` fails on a file that extends no nvim-lspconfig server. The file returns a table that is merged over nvim-lspconfig's. Use it only for the cases below:

- **Narrow the filetypes** when nvim-lspconfig lists filetypes that other servers own. Otherwise the install offer names the server there too (`nvim/after/lsp/biome.lua`):

  ```lua
  return {
    filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "json", "jsonc" },
  }
  ```

- **Attach on a sub-filetype.** Servers match the filetype exactly, so list the dotted name. Start from nvim-lspconfig's own list, because this replaces it (`nvim/after/lsp/tombi.lua`):

  ```lua
  return {
    filetypes = { "toml", "toml.pyproject" },
  }
  ```

- **Share one position encoding** when the server shares a filetype with pyrefly (`nvim/after/lsp/ruff.lua`). `checks/lsp_attach.lua` fails when one buffer's clients use mixed encodings.
- **Settings**: see `gopls.lua`, `rust_analyzer.lua` and `pyrefly.lua`.
- **`exit_timeout`** for a server that orphans children (`tflint.lua`).

Do not set `cmd` (`wiring()` replaces it with the resolved binary plus the catalog args). Do not merge blink capabilities either; blink sets them for every server. The README's older "LSP Server Config Pattern" shows both, but it predates the resolver.

## Custom root

Add a custom root only when nvim-lspconfig's `root_dir` runs the tool or a version check from PATH. tsc's `root_dir` runs `tsc --version`, so `roots.tsc` in `nvim/lua/core/lsp_servers.lua` replaces it, and the version check moved to the catalog's `min`.

A `root_dir` that runs the language's toolchain (`go env`, `cargo metadata`) already runs with the tool's PATH (`lsp_servers.lua:127-140`), so it needs no root entry.

## Formatter: `nvim/lua/plugins/conform.lua`

Add a key to `formatters_by_ft`. The value **must be a plain list of names**: the adapter loop (`conform.lua:71-72`) calls `ipairs` on every value.

- A function value raises `bad argument #1 to 'ipairs' (table expected, got function)` and empties every formatter.
- A nested list of alternatives is never wired to the resolver.

To pick a formatter per file, use a sub-filetype instead (`sub-filetypes.md`). That is how the old pyproject.toml chooser function was replaced.

Before and after for gofumpt:

```lua
-- before
      go = { "goimports" },
-- after
      go = { "goimports", "gofumpt" },
```

For a new language, add one line, `<filetype> = { "<conform name>" },`, near related entries. The key is the Neovim filetype (`:set ft?` in a file of that language), not the file extension.

- **Extra args** go under `opts.formatters.<name>`. The resolver wrapper keeps them (`conform.lua:75`):

  ```lua
    formatters = {
      shfmt = {
        prepend_args = { "-i", "2", "-kp" },
      },
    },
  ```

- **A formatter conform does not ship** needs a full definition under `opts.formatters.<name>` (`command = "<bare binary name>"`, `args`, `stdin`), plus its catalog entry. The wrapper replaces `command` with the resolved path. Check first that no conform file runs the same binary (`grep -l 'command = "<binary>"' $L/conform.nvim/lua/conform/formatters/*.lua`): if one does, use its name. `check.sh` fails on a definition that duplicates a built-in.

## Linter: `nvim/lua/plugins/nvim-lint.lua`

1. Add the name to `lint.linters_by_ft`, keyed by filetype. For an existing filetype, append to its list; this one runs two linters on workflow files:

   ```lua
         ["github-actions"] = { "jactionlint", "zizmor" },
   ```

   For a filetype with no linters yet, add a line: `<filetype> = { "<nvim-lint name>" },`.
2. **Covered by a server?** Some servers report the same findings as a linter, because they run the same tool: ruff, biome, tombi, tflint, and rust_analyzer for clippy. For those, add the pair to `covering_server` (`nvim-lint.lua:68`):

   ```lua
   local covering_server = { ruff = "ruff", biomejs = "biome", tflint = "tflint", clippy = "rust_analyzer", tombi = "tombi" }
   ```

   The linter then stays quiet while that server is attached. Leave the pair out when the server's diagnostics are different rules from the linter's: for example, yamlls and yamllint.
3. **No nvim-lint definition?** Only then write one. Check both the name and the binary: `ls $L/nvim-lint/lua/lint/linters/<name>.lua` and `grep -l "cmd = .<binary>." $L/nvim-lint/lua/lint/linters/*.lua`. If either finds a file, use that linter's name and don't define `lint.linters.<name>`; to change its args, set `lint.linters.<name>.args` on the built-in. If both are empty, define one inline, as jactionlint is (`nvim-lint.lua:35-60`). Set `cmd` to the **bare binary name**; `wrap_linter` swaps in the resolved path (`nvim-lint.lua:155`). Write the parser for the JSON the tool prints, which you saw in `verify.md` section 2:

   ```lua
       lint.linters.jactionlint = {
         cmd = "jactionlint",
         stdin = true,
         args = { "--format", "{{json .}}", "--profile", "correctness", "--stdin-filename", function() return vim.api.nvim_buf_get_name(0) end, "-" },
         ignore_exitcode = true, -- exits 1 when it has findings
         parser = function(output) ... end,
       }
   ```

4. **Rare cases:**
   - `keep_cwd[name] = true` is for a parser that matches paths relative to Neovim's cwd (tflint).
   - Rebuild a linter's args per resolved binary when its nvim-lint module runs the tool from PATH while loading. golangcilint does this (`nvim-lint.lua:95-109`); read the module's top lines to check.

## Treesitter: `nvim/lua/plugins/nvim-treesitter.lua`

Check that a parser exists: `ls ~/.local/share/nvimt2/lazy/nvim-treesitter/runtime/queries/<lang>`. If it does, add `"<lang>"` to `local ensure_installed = { ... }`.

Neovim would install the parser on first use anyway. The list matters for the suite: `tests/regress/refresh.lua` reads it with a pattern to choose which parsers to refresh. So keep it a literal `local ensure_installed = { "a", "b" }` table.

## Areas

`tests/regress/areas.map` already maps `after/lsp/*`, `lua/tools/*`, `lua/core/lsp_servers.lua`, `conform.lua`, `nvim-lint.lua` and `nvim-treesitter.lua`. Add a line only for a new config file outside those globs. An unmapped file makes `--changed` run every area.
