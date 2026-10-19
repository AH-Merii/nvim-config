# Contributing

How the config is laid out and how to change it. For what it does and how to run it, see [README.md](README.md).
Design decisions for the bigger features are in [docs/](docs/), one `*-decisions.md` per feature.

## Setup

```sh
mise run setup            # once per clone: pushes check the formatting and scan for secrets first
mise run fmt              # format the Lua with stylua
mise run docs             # regenerate docs/languages.md from the language files
mise tasks                # everything else
```

Hooks don't come with a clone, so `mise run setup` points git at `.githooks/` (`core.hooksPath`), whose pre-push hook
runs for `git push` and `but push` alike. With GitButler, use a build that keeps its own hooks in git config
(nightly, until a release has [gitbutlerapp/gitbutler#14698](https://github.com/gitbutlerapp/gitbutler/pull/14698));
setup tells you if yours doesn't.

## Architecture

### Initialization Flow

`init.lua` enables `vim.loader` (Neovim's byte-compiled module cache, before the first require) and calls
`require("app").start()`. `lua/app/init.lua` runs the startup phases in the order of its `M.phases` list, each once:

1. `options` - `lua/options.lua` (editor-wide options and `mapleader`), then ui2, before any message can be lost
2. `registries` - Neovim's own keys as key rows (`keys.neovim`), each language file's `keys` rows (`keys.languages`),
   the LSP keys (`lsp.buffer`), and each feature's `setup()` in the order of `M.features` in
   `lua/features/init.lua`: its rows, needs, autocmds and options
3. `tools` - The languages' variant filetypes and buffer options (`lang.setup()`), the tool
   resolver, install prompts and `:Tools` (before any plugin looks a tool up)
4. `plugins` - `lua/app/plugins.lua`: vim.pack installs what every module's `plugins` names
   (`require("features").plugins()`) and the disk lacks, then the startup plugins load. neoblocks is one: its
   messages module hooks ui2 here. Startup's own reports (`require("app").report()`) wait until the phases above are
   done, so they become toasts and enter the message history; other messages before it skip them
5. `servers` - `lsp.setup()`: one `vim.lsp.config` per server a language names, then `vim.lsp.enable`
6. `buffer` - At the first `BufReadPre` or `BufNewFile`: the plugins that serve files (nvim-lint, origami)
7. `deferred` - At `VeryLazy`, after the first screen: the deferred plugins, then the callbacks given to
   `require("features").at_very_lazy(fn)`

Each phase is timed: `:lua =require("app").times()` lists the phases that ran and their milliseconds.
`checks/app_phases.lua` holds the order.

**Critical**: This order ensures dependencies are met (e.g., `mapleader` defined before any key row; `keys` raises
for a `<leader>` row added without it).

### Directory Structure

```
nvim/
├── init.lua                  # Entry point: vim.loader, then the startup phases (lua/app/)
├── lua/
│   ├── app/                 # Startup phases (init.lua); vim.pack installs every module's plugins (plugins.lua)
│   ├── options.lua          # Editor-wide options
│   ├── lang/                # One data file per language, and the registry that reads them (init.lua)
│   ├── tools/               # Tool resolver (mise), catalog, prompts and :Tools
│   ├── parsers/             # The treesitter parsers a buffer needs, installed on demand (init.lua), and its
│   │                        # nvim-treesitter backend
│   ├── lsp/                 # Enabled servers, each run from its resolved binary (init.lua); the LSP keys and what a
│   │                        # server gives a buffer (buffer.lua); pyrefly's type-error switch
│   ├── format/, linting/    # Formatting and linting, each with its plugin adapter
│   ├── keys/                # Key rows and needs (init.lua), the which-key adapter, Neovim's own keys as rows, and
│   │                        # the language files' rows (languages.lua)
│   ├── textobjects/         # The treesitter text objects and moves
│   ├── ui/                  # The theme, icons, snacks (picker, notifier), the statusline (with neoblocks' messages:
│   │                        # ui2's messages and command line), and facts.lua: what applies to each buffer
│   └── features/            # One module per feature, owning its plugins, keys, autocmds and options; init.lua
│                            # lists them and the adapters that bring plugins
```

### Module Dependencies

- Every key row depends on `options` (needs `mapleader`)
- `features/lsp_status.lua` makes its commands at `VeryLazy`, after nvim-lspconfig's plugin file defines its own
  `:LspInfo` and `:LspLog`
- `blink.cmp` adds its completion capabilities to every server through `vim.lsp.config('*')`
  (`blink.cmp/plugin/blink-cmp.lua:1-7`), so a server's config doesn't merge them
- A feature's `setup()` runs before any plugin loads: what needs a plugin goes in that plugin's spec (`setup` or
  `init`), or in a callback given to `require("features").at_very_lazy(fn)`, which runs after the plugins that load
  at `VeryLazy` (the Snacks toggles)

## LSP Configuration

### Tools and languages

**Tools from mise** (`lua/tools/`, decisions in `docs/mise-tooling-decisions.md`)
- Every server, formatter and linter binary comes from mise or the system, found per project root, first hit wins: the project env (`.venv/bin`, `node_modules/.bin`), the project's mise config if you accepted it, global mise tools, then the system `PATH` without mise shims, mise install dirs or Mason's bin dir. Each tool runs from that absolute path with cwd = the project root
- `lua/tools/catalog.lua` lists each binary's mise spec, project dirs, runtime (node, go) and rustup component
- A project whose mise config pins tools asks once: *Yes* (trusts the config and installs its missing pins), *Only versions already installed* or *No, use my global tools*. The answer is kept in `stdpath("state")/tools/projects.json` until the config changes. Where a `.venv`/`node_modules` copy and a pin differ in version, it asks which one to use
- A missing tool is offered once, in one batched prompt ("python needs pyrefly and ruff" / "Install them globally with mise"), and only on files it would run on. A global install writes the config's own global mise file, `conf.d/nvim-config.toml` in mise's config dir (or `$MISE_GLOBAL_CONFIG_FILE` when set), never the user's `config.toml` (D91 in `docs/mise-tooling-decisions.md`). A missing runtime (node, go) is installed in the same step; a pinned version can be installed for the project without trusting its config. Workflow YAML is `yaml.github-actions`, `pyproject.toml` is `toml.pyproject`, and Compose and Bake files are `yaml.docker-compose` and `hcl.docker-bake` (variants in `lua/lang/`), so jactionlint, zizmor, pyproject-fmt and the Docker language server run and are offered only there
- Never prompts for library code (site-packages, node_modules, cargo registry, Go module cache), git commit messages, special buffers, headless runs, or with `vim.g.install_tools = "off"`
- After that: a statusline indicator (a wrench with the missing count, `?` for an unanswered project config; hidden when nothing is missing) and `:Tools` (per tool: roles, source and version; a tool's menu starts or restarts its server or installs it; a row to use or stop using the project's mise config; `Rescan tool sources`; `:Tools install|rescan|restart|project`)
- `lsp/init.lua` enables every server a language names, with its fields from `lang.views().lsp`. A server whose binary is missing is not started and raises no error; it starts once the binary turns up, and restarts when a refresh or install moves its binary

**Treesitter parsers** (`lua/parsers/`, D116 to D121 in `docs/rearchitecture-decisions.md`)
- A language file names no parsers. `parsers.needed(ft)` derives them: the filetype's own parser (`get_lang`), then
  the languages nvim-treesitter's injections query for it names with `#set! injection.language`, through
  `; inherits:`, one level deep. Names nvim-treesitter has no parser for are left out
- On a buffer's FileType, `features/treesitter.lua` calls `parsers.ensure`: what it lacks installs as one group (a
  toast as it starts and one as it ends), once a session per parser. A parser Neovim bundles (lua, c, markdown) gets
  nvim-treesitter's copy too, for its indents and injections; the buffer uses Neovim's until it lands.
  Installs need a UI and `vim.g.install_tools ~= "off"` (`tools.can_install`), and tree-sitter, which the tool resolver
  finds and the tools prompt offers. A failed parser counts in the statusline's missing count; `:Tools` lists each
  parser with Retry and Update
- `parsers.setup({ backend })` swaps nvim-treesitter for a fake (`tests/unit/fake_parsers.lua`)
- Once a parser is there, `features/treesitter.lua` starts highlighting and sets nvim-treesitter's `indentexpr`, unless
  the language's file says what stays instead (`treesitter`, D128): `indent = false` keeps the runtime's indent plugin,
  and `syntax = true` turns regex syntax back on after every `vim.treesitter.start`, which turns it off, `<leader>TT`'s
  included. Python needs both: its indent plugin reads the regex syntax groups to skip brackets in strings

**Languages** (`lua/lang/`, decision D46 in `docs/rearchitecture-decisions.md`)
- One data file per language (`python.lua`, `go.lua`, ...) holds its filetypes, servers with their
  settings, formatters, linters, variants, buffer options and treesitter settings. `lua/tools/catalog.lua` only says
  how to install each binary; a language names a server, formatter or linter, and the catalog gives its binary
- `lang.of(ft)` answers what applies to a filetype: its servers, formatters, linters (with the server that covers each),
  their binaries, its options and its treesitter settings. The install prompts, `:Tools`, the statusline, `:Status`,
  and the format and linting modules below ask it. A dotted filetype no language declares gets its parts' formatters,
  linters, options and treesitter settings as conform, nvim-lint and the ftplugins combine them, and no servers
- `lang.views()` builds the tables the plugins get: conform's `formatters_by_ft`, nvim-lint's `linters_by_ft`, each
  server's `vim.lsp.config` fields (applied above nvim-lspconfig's `lsp/<name>.lua`) and the variants' filetype
  rules. Every variant gets explicit entries
- A mistake in a language file, such as two languages declaring one filetype or two variants claiming one file name,
  skips that declaration and is reported once at startup; the first declaration, in file name order, stays
- A variant (a dotted filetype such as `yaml.github-actions`) gets its base's servers and linters plus its own, its
  own formatters if it names any, else its base's, and its base's options and treesitter settings. One with `match`
  rules needs an `example` path
- `docs/languages.md` lists each language's and variant's tools and each binary's install spec. `docs/languages.lua`
  generates it from `lang` and the catalog (`mise run docs`); don't edit it by hand

**The statusline** (`ui/statusline.lua`, steps 4 and 4b in `docs/rearchitecture-decisions.md`)
- `require("ui.facts").get(buf)` holds a buffer's servers running, the formatters and linters that will run, the
  missing tools (and whether the project's mise config waits for an answer), its tools root and its git checkout. What
  will run is `format.plan(buf).run` and `linting.plan(buf).run`; the rest is built from `lang.of`, the resolver's
  results and the attached clients. It is cached per buffer, and `User FactsChanged` fires when it changes
- The spec, neoblocks.nvim's statusline, only draws it: the LSP, formatter and linter lists, the tools indicator
  (`tools.ux.status`), the branch's condition and the path's project come from the facts. A segment that needs
  something new about a buffer gets it added to the facts, not computed in the spec. `:Status` reads its LSP and
  formatter lines there too
- The line is rebuilt on events only (the spec's `events`, what neoblocks' built-ins need, and `User FactsChanged`),
  never on a cursor move: the location and progress are statusline expressions Neovim evaluates on each draw. Only
  the search count is recounted on a move, while a search is highlighted

### Adding a language or a tool

1. Add the binary to `lua/tools/catalog.lua`: its mise spec and the names it serves (`servers = { <name> = { args } }`,
   `formatters`, `linters`)
2. Name it in the language's file in `lua/lang/` (a new file for a new language): the server under `servers`, with any
   settings, the formatter under `formatters`, the linter under `linters` (`covered_by` when a server reports the same
   findings), and a variant under `variants` for a tool that runs only on some files of a filetype
3. Run `nvim --clean --headless -l tests/unit/lang_test.lua`: it fails when a name has no catalog binary or a catalog
   binary is used by no language
4. Run `mise run docs` and commit `docs/languages.md` with the change: `tests/unit/languages_doc_test.lua` (and so CI)
   fails while it is out of date

The `language-tools` skill (`.claude/skills/language-tools/`) walks through the whole change, checks included.

### Language File Pattern

```lua
-- Every field, on TOML (lua/lang/toml.lua itself needs fewer)
---@type lang.Spec
return {
  filetypes = { "toml" },
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
  -- what stays on beside treesitter once it attaches, each with its reason: the runtime's indent plugin instead of
  -- treesitter's indent, regex syntax beside treesitter's highlighting (lua/lang/python.lua)
  treesitter = { indent = false, syntax = true },
}
```

A server, the formatters or a linter can name their own `filetypes` where they differ from the language's (clangd also
serves `objc`; Go formats only `go`). `cmd` has no effect: `lsp/init.lua` runs the resolved binary with the
catalog's args.

## Plugin Management

### Plugin specs

vim.pack (`:h vim.pack`) installs the plugins; `lua/app/plugins.lua` loads each in its phase. A spec is a table
(`app.Plugin` in that file):

```lua
{
  src = "author/notes.nvim", -- on GitHub, or any URL git clones
  version = "main", -- a branch, tag or commit, or vim.version.range("1.*"); default the default branch
  -- "startup", "buffer" (the first file), "deferred" (after the first screen, the default) or "on_demand" (only
  -- at one of its `cmd`)
  phase = "buffer",
  cmd = { "Notes" }, -- commands that load it if used before its phase, as `nvim +Notes` does
  init = function() end, -- before any plugin loads
  setup = function() require("notes").setup({}) end, -- once it is on the runtimepath
  build = function(path) end, -- after vim.pack installs or updates it
  dev = true, -- with $NVIM_PLUGIN_DEV naming a directory that holds notes.nvim, load that checkout instead
}
```

A plugin's module that is required before its phase loads it then (a picker action that requires trouble), so a
plugin another one needs early has no `dependencies` to declare. Each phase loads its plugins in list order:
`M.adapters` first, then `M.features` (`lua/features/init.lua`).

### Adding a New Plugin

1. Add its spec to the `plugins` list of the feature it serves (`lua/features/<feature>.lua`), or of the adapter or
   ui module that wraps it
2. Leave it deferred unless something before the first screen needs it (`startup`), it sets up the buffers it
   finds when it loads (`buffer`), or loading it changes something before it is used, such as global maps
   (`on_demand`, with the `cmd` that loads it). Give a deferred plugin `cmd` for commands used from the command line
   at launch
3. Add its keys as rows (see "Adding a key"). A row whose action requires the plugin loads it on the first press
4. Start Neovim: vim.pack clones it and adds it to `nvim/nvim-pack-lock.json`; commit that file with the spec

To remove a plugin, delete its spec, then `:packdel <name>` (or `:lua vim.pack.del({ "<name>" })`), which removes
it from the disk and the lockfile. Edits to a spec take effect after a restart: `ZR` (`:restart`) saves and
restores the session (`:h ZR`).

### Adding a feature

A feature is `lua/features/<name>.lua`, listed in `M.features` in `lua/features/init.lua`:

```lua
-- A sketch of lua/features/notes.lua
local M = {}

M.plugins = { { src = "author/notes.nvim", setup = function() require("notes").setup({}) end } } -- app.Plugin

function M.setup() -- runs once at startup, before any plugin loads
  local group = vim.api.nvim_create_augroup("features.notes", { clear = true })
  require("keys").feature("notes")({ { "<leader>on", "<cmd>Notes<CR>", "Open notes" } })
end

return M
```

It owns everything about itself: its plugins, rows, needs, autocmds (in a `features.<name>` augroup) and options.

## Filetype-Specific Configuration

### Adding Filetype Behavior

Buffer options go in the language's file (`options` in `lua/lang/<lang>.lua`). Regex syntax beside treesitter is not
one: `vim.treesitter.start` turns it off after FileType, so it goes in `treesitter` (D128). A language's own keys, such
as labels for its runtime ftplugin's maps, go in its file's `keys`; a feature's keys for a filetype are
`keys.language(ft)` rows in the feature (see "Adding a key"):

```lua
-- lua/lang/markdown.lua
keys = {
  { "]]", label = "Next heading", mode = { "n", "x", "o" } },
  filetypes = { "markdown" }, -- else the language's filetypes
},
```

Other filetype behaviour is a FileType autocommand in the feature it belongs to (`features/editing.lua` sets up prose
buffers):

```lua
vim.api.nvim_create_autocmd("FileType", {
  group = group,
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

Gracefully handle missing dependencies in a spec's `setup`. A plugin that failed to install is never loaded, so
requiring it fails:

```lua
setup = function()
    require("plugin").setup({})

    local ok, dep = pcall(require, "dependency")
    if ok then
        dep.setup()
    else
        vim.notify("dependency not found", vim.log.levels.WARN)
    end
end,
```

### Deferred work

For work that needs the deferred plugins, run after the first screen:

```lua
require("features").at_very_lazy(function()
    require("heavy.module")
end)
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

## Adding a key

Every key is a row in `lua/keys/` (step 3 in `docs/rearchitecture-decisions.md`, D48 and D49). The owner declares
its rows where it lives (a feature's `setup()`, a plugin spec, `lsp/buffer.lua`, a language file's `keys`), with an
adder for itself:

```lua
local keys = require("keys")
local key = keys.feature("git", { need = "git" })   -- defaults go into each row
key({ "]g", function() require("gitsigns").nav_hunk("next") end, "Next git hunk", icon = { icon = "", color = "green" } })
key({ "<leader>TG", toggle = Snacks.toggle.new({ ... }) })   -- or toggle = { get = fn, set = fn }, label = "Name"
keys.language("python")({ "]]", label = "Next top-level def/class" })  -- a label for the ftplugin's own map
```

- A row is `{ lhs, action, label }` plus `need`, `toggle`, `icon`, `mode`, `group`, `native` (Vim's own key with no
  map), `hidden`, `echo`, `listed`, `remap`, `silent`, `nowait`. An unknown field raises.
- `need` says where the key acts: a word defined with `keys.need(word, test)`, an LSP method (`"rename"`,
  `"workspace/symbol"`) or `"client:<name>"`. A word answers whether the key would act at the cursor now (D132): a
  hunk key needs a hunk on the cursor's line, a fold key a fold there; a key whose action doesn't depend on the cursor
  needs a buffer or cwd fact. `test(buf, win)` gets the window whose cursor and window options to read (nil where no
  window shows the buffer). An LSP method need is the closest answer knowable without asking the server: a server
  supports the method (D133). `]]`, `[[` and the treesitter moves stay at buffer level, by decision.
- A test runs on every press and once per popup rebuild (each press of `g`, `z`, `]`, `[` or `<leader>`), inside
  D61's 8.3 ms frame, so it must be a lookup; cache anything slow in the owner, filled by the owner's own events
  (`features/git.lua`'s git needs). A new row with a need is classified in `keys_act_here`'s table (cursor, buffer
  by decision, or server), which fails until it is.
- Where the need fails the key does what it did before: the global map it took over, or Vim's own key. A `<leader>`
  key, or a row with `echo = true` (Neovim's `gr*` and `gO`), echoes the need it lacks instead. A label-only row
  with a need over another's global map (Neovim's `]d` and `gx`) only hides the key where the need fails.
- Rows are global maps; only `keys.language(ft)` rows are buffer-local, and a buffer's own map (an ftplugin's) wins.
- `keys.holds(need, buf)` and `keys.menu(buf, mode)` say where a key acts and what the popup lists; `keys.list()` gives
  every row with its owner and `file:line`. `:map` and the keymaps picker list a gated key in every buffer.
- `keys/which_key.lua` is the only code that knows which-key. Don't call `require("which-key").add`: a row's label,
  icon and group are the popup's spec.
- Test a key by pressing it and reading the popup (`wk_lists`, `wk_menu`, `wk_wait` in the regress harness), never by
  which maps exist; unit tests drive `keys` directly (`tests/unit/keys_test.lua`).

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
  writing or reloading a buffer, and on entering it or leaving insert mode when it or any file changed since its
  last lint (D72), drops a linter's findings when its covering server attaches, lints again when ToolsChanged finds
  a linter, and kills the runs still going when Neovim exits (D95); `linting.plan(buf)` (`.run` is what `ui.facts`
  lists) and `linting.has(buf)` as for format

### Utilities

Not mapped to a key; run them with `:lua`:

- `require("features.files").toggle_go_test()` - Toggle between Go test/implementation files
- `require("features.git").copyFilePathAndLineNumber()` - Copy GitHub URL with line number (in git repos) or absolute
  path

## Testing Changes

After modifying configuration:

1. Source the file: `<space>%` or `:source %`
2. Restart Neovim to test full initialization flow
3. Check plugin status: `:checkhealth vim.pack`; `<leader>sp` lists the plugin specs; `:packupdate` updates
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
