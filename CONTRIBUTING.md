# Contributing

How the config is laid out and how to change it. For what it does and how to run it, see [README.md](README.md).
Design decisions for the bigger features are in [docs/](docs/), one `*-decisions.md` per feature.

## Setup

```sh
mise run setup            # once per clone: pushes check the formatting and scan for secrets first
mise run fmt              # format the Lua with stylua
mise tasks                # everything else
```

Hooks don't come with a clone, so `mise run setup` points git at `.githooks/` (`core.hooksPath`), whose pre-push hook
runs for `git push` and `but push` alike. With GitButler, use a build that keeps its own hooks in git config
(nightly, until a release has [gitbutlerapp/gitbutler#14698](https://github.com/gitbutlerapp/gitbutler/pull/14698));
setup tells you if yours doesn't.

## Architecture

### Initialization Flow

The loading sequence is strictly ordered in `init.lua`:

1. `lang`, `tools` and `tools.ux` - The languages' variant filetypes and buffer options, the tool resolver, install prompts
   and `:Tools` (before any plugin looks a tool up)
2. `core.lsp` - Configure diagnostic appearance before any LSP loads
3. `config.options` - Set Vim options & define `mapleader`
4. `config.keymaps` - Register global keymaps
5. `config.autocmds` - Setup autocommands and event hooks
6. `core.lazy` - Bootstrap Lazy.nvim and load all plugins
7. `config.helpers` - Loaded on `VeryLazy` event after plugins ready

**Critical**: This order ensures dependencies are met (e.g., `mapleader` defined before keymaps).

### Directory Structure

```
nvim/
├── init.lua                  # Entry point (loads modules in order)
├── lua/
│   ├── core/                 # Core framework initialization
│   │   ├── lazy.lua         # Plugin manager bootstrap
│   │   ├── lsp.lua          # Diagnostic configuration
│   │   └── lsp_servers.lua  # Enabled servers, each run from its resolved binary
│   ├── lang/                # One data file per language, and the registry that reads them (init.lua)
│   ├── tools/               # Tool resolver (mise), catalog, prompts and :Tools
│   ├── ui/                  # facts.lua: what applies to each buffer, for the statusline, the tools indicator and :Status
│   ├── config/              # Editor configuration
│   │   ├── options.lua      # Vim options
│   │   ├── keymaps.lua      # Global keymaps
│   │   ├── autocmds.lua     # Autocommands
│   │   ├── helpers.lua      # LSP debugging commands (:LspInfo, :Status, ...)
│   │   ├── textobjects.lua  # Custom text objects
│   │   ├── utils.lua        # Custom utilities
│   │   └── ui2/             # Messages, command line and pending keys on Neovim's ui2
│   └── plugins/             # Plugin specifications, one file per plugin or group
├── after/
│   └── ftplugin/            # Filetype keymaps, and labels for the runtime ftplugins' maps
```

### Module Dependencies

- `config.keymaps` depends on `config.options` (needs `mapleader`)
- `config.helpers` depends on LSP clients being loaded (deferred via `VeryLazy`)
- `blink.cmp` adds its completion capabilities to every server through `vim.lsp.config('*')`
  (`blink.cmp/plugin/blink-cmp.lua:1-7`), so a server's config doesn't merge them
- Plugin files are independent but may integrate with each other

## LSP Configuration

### Tools and languages

**Tools from mise** (`lua/tools/`, decisions in `docs/mise-tooling-decisions.md`)
- Every server, formatter and linter binary comes from mise or the system, found per project root, first hit wins: the project env (`.venv/bin`, `node_modules/.bin`), the project's mise config if you accepted it, global mise tools, then the system `PATH` without mise shims, mise install dirs or Mason's bin dir. Each tool runs from that absolute path with cwd = the project root
- `lua/tools/catalog.lua` lists each binary's mise spec, project dirs, runtime (node, go) and rustup component
- A project whose mise config pins tools asks once: *Yes* (trusts the config and installs its missing pins), *Only versions already installed* or *No, use my global tools*. The answer is kept in `stdpath("state")/tools/projects.json` until the config changes. Where a `.venv`/`node_modules` copy and a pin differ in version, it asks which one to use
- A missing tool is offered once, in one batched prompt ("python needs pyrefly and ruff" / "Install them globally with mise"), and only on files it would run on. A missing runtime (node, go) is installed in the same step; a pinned version can be installed for the project without trusting its config. Workflow YAML is `yaml.github-actions`, `pyproject.toml` is `toml.pyproject`, and Compose and Bake files are `yaml.docker-compose` and `hcl.docker-bake` (variants in `lua/lang/`), so jactionlint, zizmor, pyproject-fmt and the Docker language server run and are offered only there
- Never prompts for library code (site-packages, node_modules, cargo registry, Go module cache), git commit messages, special buffers, headless runs, or with `vim.g.install_tools = "off"`
- After that: a statusline indicator (a wrench with the missing count, `?` for an unanswered project config; hidden when nothing is missing) and `:Tools` (per tool: roles, source and version; a tool's menu starts or restarts its server or installs it; a row to use or stop using the project's mise config; `Rescan tool sources`; `:Tools install|rescan|restart|project`)
- `core/lsp_servers.lua` enables every server a language names, with its fields from `lang.views().lsp`. A server whose binary is missing is not started and raises no error; it starts once the binary turns up, and restarts when a refresh or install moves its binary

**Languages** (`lua/lang/`, decision D46 in `docs/rearchitecture-decisions.md`)
- One data file per language (`python.lua`, `go.lua`, ...) holds its filetypes, treesitter parsers, servers with their
  settings, formatters, linters, variants and buffer options. `lua/tools/catalog.lua` only says how to install each
  binary; a language names a server, formatter or linter, and the catalog gives its binary
- `lang.of(ft)` answers what applies to a filetype: its servers, formatters, linters (with the server that covers each),
  their binaries and its options. The install prompts, `:Tools`, the statusline, `:Status`, and the format and linting
  modules below ask it. A dotted filetype no language declares gets its parts' formatters, linters and options as
  conform, nvim-lint and the ftplugins combine them, and no servers
- `lang.views()` builds the tables the plugins get: conform's `formatters_by_ft`, nvim-lint's `linters_by_ft`, each
  server's `vim.lsp.config` fields (applied above nvim-lspconfig's `lsp/<name>.lua`), the variants' filetype rules and
  the parsers. Every variant gets explicit entries
- A mistake in a language file, such as two languages declaring one filetype or two variants claiming one file name,
  skips that declaration and is reported once at startup; the first declaration, in file name order, stays
- A variant (a dotted filetype such as `yaml.github-actions`) gets its base's servers and linters plus its own, and its
  own formatters if it names any, else its base's. One with `match` rules needs an `example` path

**The statusline** (`plugins/lualine.lua`, step 4 in `docs/rearchitecture-decisions.md`)
- `require("ui.facts").get(buf)` holds a buffer's servers running, the formatters and linters that will run, the
  missing tools (and whether the project's mise config waits for an answer), its tools root and its git checkout. What
  will run is `format.plan(buf).run` and `linting.plan(buf).run`; the rest is built from `lang.of`, the resolver's
  results and the attached clients. It is cached per buffer, and `User FactsChanged` fires when it changes
- lualine's spec only draws it: the LSP, formatter and linter lists, the tools indicator (`tools.ux.status`), the
  branch's condition and the path's project come from the facts. A segment that needs something new about a buffer
  gets it added to the facts, not computed in the spec. `:Status` reads its LSP and formatter lines there too

### Adding a language or a tool

1. Add the binary to `lua/tools/catalog.lua`: its mise spec and the names it serves (`servers = { <name> = { args } }`,
   `formatters`, `linters`)
2. Name it in the language's file in `lua/lang/` (a new file for a new language): the server under `servers`, with any
   settings, the formatter under `formatters`, the linter under `linters` (`covered_by` when a server reports the same
   findings), and a variant under `variants` for a tool that runs only on some files of a filetype
3. Run `nvim --clean --headless -l tests/unit/lang_test.lua`: it fails when a name has no catalog binary or a catalog
   binary is used by no language

The `language-tools` skill (`.claude/skills/language-tools/`) walks through the whole change, checks included.

### Language File Pattern

```lua
-- Every field, on TOML (lua/lang/toml.lua itself needs fewer)
---@type lang.Spec
return {
  filetypes = { "toml" },
  parsers = { "toml" },                         -- installed at startup; others install when a buffer needs them
  servers = { tombi = { settings = {} } },      -- nvim-lspconfig's name -> vim.lsp.Config fields
  formatters = { "tombi" },                     -- conform names, run in order
  linters = { tombi = { covered_by = "tombi" } }, -- nvim-lint names
  variants = {
    ["toml.pyproject"] = {
      about = "pyproject.toml: pyproject-fmt formats it instead of tombi",
      match = { filename = { "pyproject.toml" } },
      example = "sub/pyproject.toml",
      formatters = { "pyproject-fmt" },
    },
  },
  options = { expandtab = true },                -- buffer options, set on FileType
}
```

A server, the formatters or a linter can name their own `filetypes` where they differ from the language's (clangd also
serves `objc`; Go formats only `go`). `cmd` has no effect: `core/lsp_servers.lua` runs the resolved binary with the
catalog's args.

## Plugin Management

### Lazy.nvim Loading Strategies

**Event-based** (load on buffer events):
```lua
{ "plugin/name", event = { "BufReadPost", "BufNewFile" } }
```

**Command-based** (load when command invoked):
```lua
{ "plugin/name", cmd = "CommandName" }
```

**Key-based** (load when keymap triggered):
```lua
{ "plugin/name", keys = { { "<leader>x", ":Command<CR>" } } }
```

**Filetype-based** (load for specific filetypes):
```lua
{ "plugin/name", ft = "lua" }
```

**Priority loading** (load immediately):
```lua
{ "plugin/name", priority = 1000, lazy = false }
```

### Adding a New Plugin

1. Create `lua/plugins/[name].lua`
2. Return Lazy plugin spec with appropriate loading strategy
3. Include keymaps in the `keys` table for lazy loading
4. Add `config` function for setup
5. Use `dependencies` table for plugin dependencies

## Filetype-Specific Configuration

### Adding Filetype Behavior

**Option 1**: Buffer options go in the language's file (`options` in `lua/lang/<lang>.lua`); keymaps go in
`after/ftplugin/[filetype].lua`

Example structure:
```lua
local opts = { noremap = true, silent = false, buffer = true }
vim.keymap.set("n", "<space>x", ":.lua<CR>", opts)
```

**Option 2**: Add filetype autocommand in `lua/config/autocmds.lua`

```lua
autocmd("FileType", {
    pattern = { "markdown", "text" },
    callback = function()
        vim.opt_local.spell = true
        vim.opt_local.wrap = true
    end,
})
```

## Important Patterns

### Blink + LSP Integration

blink.cmp sets its completion capabilities for every server with `vim.lsp.config('*', …)` when it loads
(`blink.cmp/plugin/blink-cmp.lua:1-7`). A server's config in `lua/lang/` lists only the capabilities it adds, such as
`workspace.fileOperations`.

### Conditional Plugin Setup

Gracefully handle missing dependencies:

```lua
config = function(_, opts)
    require("plugin").setup(opts)

    local ok, dep = pcall(require, "dependency")
    if ok then
        dep.setup()
    else
        vim.notify("dependency not found", vim.log.levels.WARN)
    end
end
```

### VeryLazy Deferred Loading

For heavy utilities that depend on plugins being loaded:

```lua
vim.api.nvim_create_autocmd("User", {
    pattern = "VeryLazy",
    once = true,
    callback = function()
        require("heavy.module")
    end,
})
```

### Autocommand Groups

Always use groups for organization and reloading:

```lua
local group = vim.api.nvim_create_augroup("MyGroup", { clear = true })

vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function() ... end,
})
```

## Key Integrations

### Formatting & Linting Chain

For each language, the tooling chain is:
1. **Conform.nvim** (primary formatter)
2. **nvim-lint** (linter)
3. **LSP** (fallback formatter if no conform formatter)

Configure in:
- `lua/lang/<lang>.lua` - `formatters` and `linters`; conform's and nvim-lint's tables are built from them
- `lua/tools/catalog.lua` - The tool's binary and mise spec (`formatters = { ... }` or `linters = { ... }`)
- `definitions` in `lua/format/conform.lua` and `lua/linting/nvim_lint.lua` - Only a formatter's or linter's own
  definition or args, kept by tool since conform and nvim-lint key them by name for every filetype

Two modules own them (step 2 in `docs/rearchitecture-decisions.md`); the plugin specs only load the plugin and call
their `setup()`, and each module's adapter file is the only one that knows its plugin:
- `lua/format/` (`format/conform.lua` the adapter): `format.buffer(buf)` formats with the formatters that run, else an
  attached server, and reports once what ran (`<leader>lf`, `:FormatWithConform`, and on save while
  `format.on_save.get()`, which `<leader>Tf` flips); `format.plan(buf)` is what the language names and what of it runs
  now, cached per buffer; `format.has(buf, range?)` is the key gates' need, a named formatter or a formatting server
- `lua/linting/` (`linting/nvim_lint.lua` the adapter; not `lint/`, which is nvim-lint's own module): it lints on
  entering a buffer, writing and leaving insert mode, drops a linter's findings when its covering server attaches, and
  lints again when ToolsChanged finds a linter; `linting.plan(buf)` (`.run` is what `ui.facts` lists) and
  `linting.has(buf)` as for format

### Utilities

`lua/config/utils.lua` provides:

- `toggle_go_test()` - Toggle between Go test/implementation files
- `copyFilePathAndLineNumber()` - Copy GitHub URL with line number (in git repos) or absolute path

## Testing Changes

After modifying configuration:

1. Source the file: `<space>%` or `:source %`
2. Restart Neovim to test full initialization flow
3. Check plugin status: `:Lazy` (press `U` to update, `X` to clean)
4. Check LSP status: `:LspStatus` or `:Status`
5. Check for errors: `:messages`

### Unit tests

`tests/unit/` tests a module through its interface, in-process, with no plugins: `mise run test:unit` (or
`tests/unit/run.sh [name-regex]`) runs every `*_test.lua` in a few seconds, with throwaway Neovim dirs. The tool
resolver runs there on a fake tool backend instead of mise, and LSP code on an in-process fake server;
`tests/unit/README.md` has the conventions. Run them while iterating; they don't replace the suite.

### Regression suite

`tests/regress/suite.sh` runs the config headless against fixtures, on nightly, without touching your own Neovim
dirs; `tests/regress/README.md` has the options and how to write a check. Run the whole suite before a branch lands.

### Test image and CI

`mise run test:image` runs both tiers in a container with a pinned nightly and the suite's tools, built from
`tests/image/Dockerfile`; nothing from your own setup is needed. CI runs the same image on every pull request
(`.github/workflows/test.yml`), and a pull request merges once its `test` job is green.
`docs/test-image-decisions.md` has how the image is built, pinned and bumped.

## Notes

- Diagnostic signs use Nerd Font icons
