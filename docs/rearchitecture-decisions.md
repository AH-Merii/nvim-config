# Rearchitecture: decisions

Living record of the decisions for reorganising the config by its domain (languages, keys, tools and
features) instead of by plugin. Newest status first in each section. Dates are when the decision was made.

## Goal

Declare each fact once, in data, and turn it into behaviour in a few deep modules. Each plugin lives inside
the one module that owns it. This is a locality project, not a speed one: our own code is 5.5 ms of a
219 ms startup (proposal Part 7), and every hot path keeps a budget.

The full proposal, with its measurements and sources, was written outside the repo on 2026-10-17
(`~/.cache/nvim-config/architecture-review/rearchitecture-proposal-20261017.html`); its evidence is under
`~/.cache/nvim-config/rearch/`. This file holds the decisions taken from it, so the repo has them.

## Status

- Decided (2026-10-17): D45 to D49 below.
- Planned: the path-B steps, in the order under "Path B".
- Built: the unit tier and the tool backend seam ("Unit tier and tool backend seam" below).
- Done ahead of step 3: the key checks observe behaviour, not buffer maps ("D48 prep: key checks"
  below).
- Built: step 1, `lang/` ("Step 1: lang/" below).
- Built: step 4's first half, `ui/facts` and the statusline adapter ("Step 4: ui/facts and the statusline adapter"
  below); the swap to neoblocks follows separately.
- Built: step 2, `format/` and `linting/` ("Step 2: format/ and lint/" below).

## Target layout

```text
nvim/
├── init.lua            require("app").start()
└── lua/
    ├── app/            startup phases, plugin manager adapter
    ├── options.lua     editor-wide options only
    ├── lang/           registry, python.lua, go.lua, …
    ├── tools/          resolver (kept), mise backend, catalog, prompts, :Tools, indicator
    ├── lsp/            server lifecycle and wiring
    ├── format/         format, on save, conform adapter
    ├── linting/        lint, what runs, nvim-lint adapter (not lint/: step 2)
    ├── keys/           rows, needs, which-key adapter, toggles, Neovim's keys as rows
    ├── textobjects/    treesitter objects and moves (kept)
    ├── ui/             facts, statusline, theme, messages (ui2, kept), picker, notify
    └── features/       git, search, editing, completion, folds, diagnostics, windows, lua-dev, profiling
tests/
├── unit/               no plugins, fake tool backend
└── regress/            today's sandboxed suite, kept as the gate
```

Gone at the end: `after/lsp/` and `after/ftplugin/` (into language files), `plugins/` (into features and
adapters), `config/autocmds.lua`, `utils.lua`, `helpers.lua` and `keymaps.lua` (each part to the feature it
serves).

## D46: one file per language is the centre (2026-10-17)

**Context.** Python's settings live in 16 files today: the catalog, the server list, `after/lsp`, conform,
nvim-lint, the covering servers, treesitter, sub-filetypes, ftplugins, autocmds and which-key among them.
Five readers each rebuild "what applies to this buffer" from the plugins' own tables
(`tools/init.lua:892-931`, `core/lsp.lua:30-61`, `plugins/lualine.lua:124-150`, `tools/lint.lua:50-57`,
`config/helpers.lua:289-305`). A dotted filetype gets four different lookup rules, one per plugin
(`docs/mise-tooling-decisions.md:118-124`).

**Decision.** `lang/<lang>.lua` holds a language's filetypes, parsers, servers and their settings,
formatters, linters and covering servers, variants, options and keys. Only how to install a binary stays in
`tools/catalog.lua`. The `lang` module's interface is `lang.of(ft)` (one answer per filetype) and
`lang.views()` (the tables conform, nvim-lint, `vim.lsp.config` and the filetype rules want). One variant
rule: a variant inherits its base's servers and linters, and uses its own formatters when it names any.

**Reopens** "Where config lives: option (b)" (`docs/mise-tooling-decisions.md:77-97`), which rejected one
file per language because it "would rebuild things that already work". The prototype reproduces both
named cases (the TOML formatter choice and covering servers). It also replaces CONTRIBUTING's Tier 2
`after/lsp` files.

**Rejected.** One file per tool (wins only when one tool changes across languages); one table per role
(today's tables moved out of the plugin specs); per-buffer ftplugins with no registry (nothing could ask
what applies to a filetype before a buffer of it opens, so `:Tools`, the prompts and the completeness
checks would lose their single answer).

## D47: path B, replace in place, module by module (2026-10-17)

**Decision.** Each step is a normal PR, gated by the regress suite, and leaves main better on its own.

**Rejected.** Path A, build it beside in a test slot and switch once: every PR on main in the meantime
would have to be ported (23 commits in six days, 2026-10-12 to 2026-10-17), and it ends in one big switch.

### Path B

1. `lang/`: language files; conform's, nvim-lint's and the servers' tables are generated from them; the
   five readers become `lang.of`. Removes `after/lsp`, `tools/filetypes.lua` and most of the
   language-tools skill's step 4.
2. `format/` and `lint/`.
3. `keys/` with needs, Neovim's defaults as rows (D48, D49).
4. `ui/facts` and the statusline adapter, then neoblocks.
5. `features/`, which empties `autocmds`, `utils`, `helpers` and `extras`.
6. `app/` phases, with the plugin manager (D45) last, tried in a slot first.

`tests/unit` grows with each step. Steps 2 and 4 depend only on step 1; step 3 needs step 2 (its
"formatter" need reads format's plan) and the key-check rewrite (D48). Two pieces start alongside step 1
because they depend on nothing: the key-check rewrite, and the unit tier with its fake tool backend.

Not done: the incremental review's cards 8 (servers into the catalog) and 9 (server keys into
`after/lsp`). They move servers and server keys to where this design takes them away from.

## D45: vim.pack replaces lazy.nvim, last (2026-10-17)

**Context.** lazy.nvim's own setup takes 6.6 ms; it runs every plugin's config inside
`require("core.lazy")`, so `--startuptime` shows them as one 37.6 ms line; its key and event triggers
duplicate the key rows and the phases. `vim.pack` installs, locks (`nvim-pack-lock.json`), reviews updates
in a buffer and has `PackChanged` hooks, but has no triggers, no `:Lazy` UI and copies local plugins
instead of linking them (`:h vim.pack`). It is "experimental, yet should be stable enough for daily use".

**Decision.** vim.pack, for the design rather than for speed: `app` owns the phases and times each one.
It goes last. Before switching, measure `vim.pack.add` for the 25 plugins in a test slot.

**Rejected.** Keeping lazy.nvim behind a manager port: with one manager there is one adapter, so the port
would be a hypothetical seam.

## D48: gated keys are global maps that test their need when pressed (2026-10-17)

**Context.** 99 keys are gated today by 10 separate mechanisms (FileType patterns, ftplugins, core/lsp's
sync, nvim-lint's key gate, treesitter attach, gitsigns' on_attach, snacks' async git checks, the
GitHub-remote check, the text-object dispatch, the `[Output]` buffer). core/lsp's sync runs 7 times while
one Python file opens, at 0.39–0.43 ms a call. Four designs were compared (first draft, minimal interface,
common caller, Neovim-native).

**Decision.** Design 2's interface on design 1's mechanism:

- Interface: `keys.feature(name, defaults)` returns an adder for one owner; rows are
  `{ lhs, action, label, need = …, toggle = …, icon = … }`; `keys.language(ft)` for a language's
  buffer-local rows; `keys.need(word, test)`; `keys.holds(need, buf)`; `keys.menu(buf, mode)`;
  `keys.list()`.
- A need is a word defined with `keys.need`, an LSP method by name, or `client:<name>`. Tests must be
  lookups; an owner caches anything slow.
- A row with a need is one global expr map. A press tests the need in the current buffer; where it holds
  the action runs, elsewhere the key does what it did before (the map it took over, or Vim's own key).
  A leader key has nothing to fall back to, so it echoes the need. Only language rows are buffer-local,
  and an ftplugin's own map always wins.
- which-key's filter lists a row only where its need holds. Each need is tested once per popup rebuild.
- No event handlers: `client:supports_method` reads registrations when called, so the capability-handler
  wrap goes (`core/lsp.lua:230-245`). A global `K` stops Neovim adding its buffer `K`, so the K case goes
  too (`core/lsp.lua:150-155`).

Measured on main (8d77d6c) in the regress sandbox: nothing runs on attach, FileType or registration; a
popup rebuild is within noise of today's (1585/1738/1810 µs against 1645/1789/1767 µs); a gated key's press
costs 2–6 µs over a `<Cmd>` map; setting 99 global maps at startup costs 0.90–1.06 ms, once.

**Cost accepted.** `:map`, `maparg` and the keymaps picker (`<leader>sk`) list gated keys in every buffer.
`keys.holds` and `keys.menu` say where a key acts.

**Order of work.** 13 key checks read gating as "the buffer has the map": `toggle_wk_specs.lua:22`,
`pyrefly_toggle_scope.lua:25,38`, `pyrefly_type_errors.lua:41`, `lint_manual_installed.lua:23` in
`checks/`, and 9 of the 11 in `work/keys`. They are rewritten first, on today's code, to check behaviour
(what a press does, what which-key lists). Then the mechanism switches while those checks stay unchanged.

**Rejected.** The first draft's buffer maps while a slow need holds: it keeps `:map` truthful, but costs a
sync on every change, keeps the LSP handler wrap (registration fires no autocmd) and has two mechanisms.
Design 3 (owners set and delete buffer maps from their own events): event code in about 10 owners, and
diagnostics and quickfix keys stay ungated. Inferring a need from the action (design 2): it covers only
`vim.lsp.buf` actions and Neovim's own keys, and most LSP rows open a picker and name their need anyway.

## D49: gr* keys show a message where no server can act (2026-10-17)

**Context.** Today the `gr*` keys fall back to Vim's `gr{char}`, which replaces the character under the
cursor (`:h gr`). Neovim's own `grn` default notifies instead when no client supports rename
("[LSP] Rename, no matching language servers with rename capability.", `runtime/lua/vim/lsp/buf.lua:796` on nightly).

**Decision.** Where no server can act, `grn`, `gra`, `grr`, `gri`, `grt`, `grx` and `gO` show a message
naming the missing need, instead of editing a character.

**Rejected.** Falling back to Vim's `gr{char}` (today's behaviour): an LSP key typed in a buffer with no
server silently edits text.

## Process

- Each step is built in its own git worktree under `.claude/worktrees/`, on a `rearch/<step>` branch from
  `origin/main`, and lands as one PR once the full suite passes and review findings are answered.
- A GitHub release is tagged after each step lands.
- Each step records its own decisions and deviations in a section of this file.
- A step merges only after its CI run (.github/workflows/test.yml) is green (D52).

## Unit tier and tool backend seam (2026-10-17)

**Context.** Principle 7 of the proposal asks for two test tiers: fast in-process tests at each deep module's
interface, and the regress suite for the whole. Its seam ledger finds one real seam under `tools/`: mise, a
third-party CLI that installs over the network (`tools/init.lua:660,672` on main), with a port at
`tools.setup({ backend })` and a fake for the unit tier. The tier starts alongside path-B step 1 (D47).

**Decision: the tool backend seam.** `tools.Backend` (`nvim/lua/tools/init.lua:56-68`) is everything the resolver
asks mise or has mise do, and nothing else:

- Queries: `bin_paths("/")` (the global tools), `scan_project(root)` (what the project's configs pin, installed or
  not, and their bin dirs), `env(scope, dirs)` (the env of a tool that needs a runtime), `install_version(path)`
  (a version read from mise's install dir), `clean_path()` (Neovim's PATH without mise's shims and install dirs,
  which the system layer searches).
- Installs: `use_global`, `install` (a pinned version), `trust` and `install_project`, plus `missing()`, which says
  why installs can't run ("mise is not installed"). The resolver still decides whether installs may run at all
  (`can_install`, `tools/init.lua:635`).
- `tools/mise.lua` is the mise adapter, its queries unchanged. The install commands, and their error text
  (`<command>: <stderr>`), moved there from the resolver unchanged. `tools.setup({ backend = … })` swaps the
  adapter and drops every cached answer (`tools/init.lua:945`); `tools.setup()` keeps mise.

What stays real, outside the seam:

- The project env dirs (`.venv/bin`, `node_modules/.bin`, searched upward) and the system PATH. They are file
  system probes the resolver does itself, cheap and local; unit tests make them in throwaway dirs and set PATH.
  Faking them would leave the resolver's own upward search untested.
- Running a found copy (`--version` for the minimum-version check) and rustup (`rustup which`,
  `rustup component add`). They go through `tools/proc.lua`, where `run` moved from `tools/mise.lua`: they are not
  mise. The fake's tools are real executables, so the version check runs for real.
- The saved answers to the project prompt (`tools/state.lua`), a local file; tests point `state.file` at a temp dir.

**Decision: the unit tier.** `tests/unit/<module>_test.lua`, each runnable alone from the repo root with
`nvim --clean --headless -l tests/unit/<file>`. Its first lines put `nvim/lua` (relative to the file) and
`tests/unit` on `package.path`; it loads no plugins and fails by raising. `tests/unit/run.sh [regex]` (and
`mise run test:unit`) runs each file in its own Neovim with throwaway XDG and temp dirs, prints PASS/FAIL with the
time, and exits non-zero on a failure. Helpers: `helper.lua` (cases, assertions, temp files),
`fake_backend.lua` (the fake tool backend) and `fake_server.lua` (an in-process language server started through
the real `vim.lsp` with a Lua `cmd`, as `tests/regress/work/keys/keys_lsp_gate.lua` does, with control of its
capabilities and registrations and a log of its requests). The whole tier runs in about 0.2 s (`tests/unit/run.sh`:
`fake_server_test` 35 ms, `tools_test` 142 ms).

`tests/unit/tools_test.lua` tests the rules of `docs/mise-tooling-decisions.md`, not today's code paths: the
resolution order (project env, then an accepted project mise config, then global mise, then the system PATH,
`:30-36`), a project env above the root (`:32`), an unanswered or "global only" project config isn't used (`:33`,
`:62-66`), a copy below the minimum version is skipped and one at the minimum is used (case 9), and a tool missing
its runtime installs both in one `mise use -g`, or only the runtime when the tool is there (case 10). Each rule
was shown to bite with a one-bug variant of the resolver.

**Rejected.**

- The backend owning `run`, a seam at the process boundary: the fake would either have to run real processes for
  the version checks anyway or fake every executable, and rustup is not mise.
- The proposal's fake shape, `project = { [".venv"] = { ruff = "0.16.0" } }`: `.venv` is a file system probe,
  not a mise answer. The fake takes `global = { <binary> = <version> }` and `projects = { [root] = { <binary> =
  <version or { version, installed = false }> } }`.
- The fake in `nvim/lua/tools/`: it ships nothing to the editor, so it lives in `tests/unit`. It supports only
  what the tests use; its pinned and project installs raise.
- Overriding `tools.can_install` to let a test install: the test stubs `nvim_list_uis` instead, as
  `tests/regress/checks/tools_indicator.lua:9` does, so the headless guard itself stays real.
- A test framework (busted, mini.test, plenary): a dependency for what `nvim -l` and a 95-line helper do.

## D48 prep: key checks (2026-10-17)

**Context.** D48's "Order of work" counts 13 key checks that read gating as "the buffer has the map". The count
holds on 8bc0551: 4 in `checks/` (`toggle_wk_specs.lua:22`, `pyrefly_toggle_scope.lua:25,38`,
`pyrefly_type_errors.lua:41`, `lint_manual_installed.lua:23`) and 9 of the 11 in `work/keys`
(`grep -l 'nvim_buf_get_keymap\|maparg' work/keys/*` lists all but `keys_global_regress` and `whichkey_ghosts`).
Several also read `require("core.lsp").keys`, which step 3 removes. Two were already red on main:
`keys_diag_gate` took `<leader>Te` (a `when` row with no method) for a diagnostics key, and `keys_git_context`
ran every `<leader>g` callback, one of which left an undotree error in `:messages`.

**Decision.** A key check observes only what a user can, so it stays green, unchanged, when step 3 swaps the
mechanism:

- "The key works here": a real press (`feed`) and its effect. LSP keys press against in-process fake servers
  that record each request (`checks/keys_lsp_gate.lua`, `checks/keys_format_gate.lua`); other keys by the
  cursor, a window or picker opening, the text, the git index, a notification or a toggle's label flipping.
- "The popup offers it here": which-key's own read path, `require("which-key.buf").get({ buf, mode,
  update = true })`, which runs `config.filter` on every map it adds (which-key `tree.lua:26`). The harness
  wraps it as `wk_lists`, `wk_menu` and `wk_wait` (`tests/regress/harness.lua:187-240`) and reads with the
  buffer current, since the filter gets no buffer: a global map the filter hides reads the same as a
  missing buffer map.
- "It falls back here": where the need fails, the key is not listed and makes no request; a non-leader key
  does Vim's own (gd and gD to the declaration in the buffer, gt the next tab page, K `'keywordprg'`,
  `]]`/`[[` the section motions, gO leaves text and cursor). A leader key is only checked not to act, since
  D48 has it echo the need.
- Today's gr* fallback is one case, "gr* with no server: Vim's gr{char}" (`checks/keys_lsp_gate.lua:396`);
  step 3 flips that case for D49 and nothing else.
- The key lists are written out in the checks, from the config's key list, not read from its tables. Each
  list has a completeness case: every key the popup gains when a server with every method attaches
  (`checks/keys_lsp_gate.lua:359`), or in a file of a repo with a GitHub remote
  (`checks/keys_git_context.lua:342`), must be one the checks judge.
- Promoted to `checks/`: `keys_lsp_gate`, `keys_format_gate`, `keys_diag_gate`, `keys_git_context`,
  `keys_git_unstage`, `keys_source_file`, `keys_gr_typed.sh`. Left in `work/keys`: `keys_textobjects` and
  `keys_diff_jump`, rewritten too, which repeat `tobj_moves` (diff-mode `]c`, `]f` per language and in
  fences), `tobj_labels` and `tobj_select`.

**Deviation.** `keys_lsp_gate` lost its "modifier-key lhs" case: it pushed a row into `core.lsp.keys` to test
how the sync matches `<C-x>` maps, which step 3 deletes along with the sync.

**Rejected.** Reading `keys.holds` and `keys.menu`: they don't exist until step 3, and the checks have to pass
before it. Reading global maps as well as buffer ones: with D48 every gated key is a global map in every
buffer. Deriving the key lists from the config's tables: they move in step 3.

**Writing a key check from now on.**

- Press the key and assert what it did; assert where the popup lists it with `wk_lists`/`wk_menu`. Never
  `maparg` or `nvim_buf_get_keymap` to decide where a key works.
- Where its need fails, assert that it doesn't act and isn't listed, and what Vim's own key does for a
  non-leader key; never what a leader key says.
- Wait on the popup with `wk_wait`, not `wait_until`: each read schedules which-key work, and a `wait_until`
  predicate that reads it wakes itself forever (found here: gitsigns never attached while one polled).
- Answer LSP requests from a fake server with empty lists, not `vim.NIL`: Snacks' LSP pickers fail on it.
- Prove the check bites with a sibling wrong implementation per gate (`CFG=<copy with one bug> suite.sh
  <check>`).

## Step 1: lang/ (2026-10-17)

Built on `rearch/lang` from `origin/main` 54ec593 (#23's code lenses, #25's unit tier and #27's key checks
included). What D46 asked for, the choices it left open, and what review changed.

**Built.** `nvim/lua/lang/init.lua` (the registry) and 18 language files: the prototype's 17 with HTML and CSS split
(`rearch/proto/lua/lang/`). Every value was checked against main, not the prototype, which was written against
cf220c8 (gopls' settings and pyrefly's lens commands had changed since). Generated now: the server list and each
server's `vim.lsp.config` fields (`core/lsp_servers.lua`), conform's `formatters_by_ft`, nvim-lint's `linters_by_ft`,
the covering servers (`tools/lint.lua`), the variant filetype rules and the parsers. Gone: `after/lsp/` (9 files),
`tools/filetypes.lua`, `tools.for_filetype`, and the buffer options of `after/ftplugin/lua.lua`. The readers ask
`lang.of`: `tools/ux.lua` (prompts, `:Tools`), `core/lsp.lua` (`has_formatter`, `has_diagnostics`), the lualine
lists, `tools/lint.lua` `to_run`, `:Status`, and nvim-lint's runs, `<leader>ll` and `<leader>li`
(`plugins/nvim-lint.lua`, which passes the names to `try_lint`).

**Checked.** A dump of what the plugins hold and what the readers answer, on main and on the branch
(`~/.cache/nvim-config/rearch/lang/tmp/compare/`: `dump.lua`, `compare.py`, `compare-output.txt`): all 20 servers'
resolved `vim.lsp.config` (filetypes, settings, root markers, capabilities, handlers, commands), both plugin
tables, the plugins' own plans and the readers' answers for 63 filetypes, the detection of 39 paths, the parsers and
lua's options. 1222 values are equal; 12 lists differ only in order (the sorted filetype lists, and
`yaml.github-actions`' linters, which main's readers took in nvim-lint's `vim.tbl_keys` order, `lint.lua:239`); the
rest are the new variant keys and the case under "Answers that changed".

**Decisions.**

- *A server entry is its `vim.lsp.Config` fields.* `servers = { tinymist = { root_markers = …, settings = … } }`
  replaces `after/lsp/tinymist.lua` one for one, applied with `vim.lsp.config(name, …)`, which ranks above
  nvim-lspconfig's `lsp/<name>.lua` as `after/lsp/` did (runtime `lua/vim/lsp.lua`, `lsp.config.__index`). The
  prototype's `tool` field is dropped: the catalog gives the binary (`catalog.binary`).
  Rejected: a separate `config` table inside each entry (the prototype's), one level more for nothing.
- *An item may name its own `filetypes`.* A server, the formatter list or a linter that applies to other filetypes
  than its language's lists them: tsc serves the scripts and not JSON, Go formats only `go`, tflint and trivy run
  only on `terraform`. Main has all of these differences.
  Rejected: one language per set of filetypes that share tools (gomod, tf and objc would each be a file).
- *nvim-lspconfig's extra filetypes are declared, not merged at run time.* clangd lists objc, objcpp and cuda, cssls
  lists less, and `yaml.gitlab`, `yaml.helm-values`, `markdown.mdx`, `c.doxygen` and `cpp.doxygen` are variants with
  only an `about`. Every server attaches where it did, and `lang.of("objc")` still offers clangd as main's
  `for_filetype` did. Nothing in Neovim's runtime or this config sets the five dotted names (runtime
  `lua/vim/filetype.lua` has none of them).
  Rejected: merging nvim-lspconfig's lists into `vim.lsp.config` at setup (the proposal's other option), because
  `lang.of` would then not know those filetypes and the install offer for them would go.
- *A variant names its servers; it cannot configure them.* A server is configured once, in a language's `servers`;
  a variant lists names (`docker.lua`). A second language configuring the same server is skipped and reported.
- *One rule for a dotted filetype no language declares*, the one the plugins applied on main: no servers (a server
  attaches only to the filetypes it lists), the formatters of its last part that has any (conform,
  `conform/init.lua:227-241`), every part's linters (nvim-lint, `lint.lua:224-239`) and every part's options, later
  parts last (Neovim sources each part's ftplugin). Since nvim-lint's runs and keys take their names from `lang.of`,
  the statusline, the key gates and what runs give one answer for `ansible.yaml` as for `yaml`.
  Rejected: the first part's formatters and linters only (the first build). Review found nvim-lint still ran
  yamllint on `ansible.yaml` through its own union while `lang.of` said none, so the statusline said "Linters: none".
- *A mistake in a language file is skipped and reported, not raised.* Two languages declaring one filetype or
  configuring one server, two variants claiming one file name or pattern, a variant without a dot, an unknown server
  in a variant, and a file that does not load: the first declaration in file name order stays, the other is skipped,
  and `lang.setup()` reports them in one error notification (`lang.problems()` lists them). `lang.setup()` runs
  first in `init.lua`, so an error raised there would leave Neovim without lazy, its options and its mapleader; on
  main, a bad `after/lsp` file broke only its server.
  Rejected: raising at load (the first build), and `pcall` around the whole build, which would drop every language
  for one mistake.
- *Linter order*: the base's linters, then the variant's own, each in name order, which is the order nvim-lint's
  union of parts gave (`yamllint, jactionlint, zizmor`). The prototype sorted all of them together.
- *Parsers as main has them.* The prototype added toml, css, dockerfile and others, which would install at startup
  instead of when a buffer needs them. Parsers no language names (query, regex, vim, vimdoc, proto) stay a literal
  `ensure_installed` list in `plugins/nvim-treesitter.lua`, which `tests/regress/refresh.lua` reads along with
  `lang.views().parsers`.
- *Buffer options on FileType.* `lang.setup()` makes a FileType autocmd that sets a language's `options`. It runs
  after the runtime's ftplugins and `after/ftplugin/`, because Neovim makes the `filetypeplugin` autocmd before
  `init.lua` runs (a probe with `-u` printed one autocmd in that group from inside the init file).
- *The `tf` filetype stays a Terraform filetype with only `terraform_fmt`,* as conform had it. It is Neovim's name
  for a TinyFugue file (`vim.filetype.detect.tf`); dropping it is a behaviour change left for later.

**Answers that changed.** nvim-lint no longer has a bare `github-actions` key (only `yaml.github-actions` used it,
through nvim-lint's union of parts; nothing sets the bare filetype).

**Left for later steps.** Keys stay where they are (step 3): `after/ftplugin/*` keymaps and labels, pyrefly's
`<leader>Te`. Formatter and linter definitions and args stay in the plugin specs (step 2): shfmt's and fish_indent's
args, jactionlint's definition, `keep_cwd`, golangcilint's args. `roots.tsc` stays in `core/lsp_servers.lua` (the lsp
module). Per-filetype options in `config/autocmds.lua` (Terraform's commentstring, wrap and spell for prose) and the
tsconfig and dotenv rules in `config/options.lua` stay until step 5. `indent_disabled` stays in the treesitter spec.

**Cost.** Measured headless with `vim.loader` on (`~/.cache/nvim-config/rearch/lang/tmp/bench2.lua`): requiring the
18 files takes 0.9–1.2 ms and building every answer and view 1.1–1.6 ms; `lang.of` on a declared filetype is a table
lookup. `--startuptime` in the suite's sandbox: `init.lua`'s own time goes from 0.75 ms to 1.8–1.9 ms and
`require('lang')` adds 0.7–0.8 ms, while `vim.filetype` loads once as before (1.7 ms, now under `lang.setup`). Total
startup is within noise: two rounds of six runs each gave medians of 115.3 and 115.6 ms on main, 116.4 and 114.4 ms on
the branch.

**Tests.** `tests/unit/lang_test.lua` (no plugins) tests the rules on two fixture languages through `lang._from(specs)`,
with literal expected values: what each filetype gets, items with their own filetypes, the variant rule, the
undeclared fallback, the views, the options `setup` sets, and each kind of mistake (the first declaration stays and the
problem is reported, once, by `setup`). Over the real files it checks only validity and completeness: no problems,
each variant's `about` and example path, and the catalog against the languages. 32 sibling wrong implementations of
`lang/init.lua` each fail it (`~/.cache/nvim-config/rearch/lang/tmp/mutants/run.sh`), the eight review found passing
the first version included. In the suite, `checks/lang_views.lua` replaces `checks/lsp_configs.lua`: what conform,
nvim-lint and `vim.lsp.config` hold is what the languages say, functions compared by identity.
`checks/lang_options.lua` puts an ftplugin on the runtimepath that sets each option a language sets to something else,
and checks the language's value wins. `checks/tools_subfiletypes.lua` reads the variants from `lang`. Checks that
need a language of their own (`lint_compound_ft`, `lint_manual_installed`, `keys_format_gate`, `keys_diag_gate`)
declare it with the test-only `lang._declare(name, spec)`, and set the plugin's own entry as the views would at
startup. `keys_format_gate` loses its "formatter function that finds nothing yet" case: a language's formatters are a
list of names (`lang.Formatters`), so conform's function form has no counterpart.

## Step 4: ui/facts and the statusline adapter (2026-10-17)

Built on `rearch/ui-facts` from `origin/main` 30877d7 (step 1 included), alongside step 2 (`rearch/format-lint`). The
neoblocks swap is not part of it. The user sees the same statusline; what changed is where its answers come from.

**Context.** On main, lualine's spec computed the LSP, formatter and linter lists itself, into one cache shared by
every buffer, on BufEnter, FileType, LspAttach, LspDetach and BufWritePost and on ToolsChanged, asking
`conform.list_formatters_to_run` and `tools.lint.to_run` each time (`plugins/lualine.lua:99-165` on 30877d7). It kept a
project-root cache filled by a `git rev-parse` process per folder (`:71-90`), and it had 12 event listeners of its own
(`:88,155,159,287,450,455`), one of them on the typed string `"ToolsChanged"` (`:160`). `:Status` asked conform again
(`config/helpers.lua:291`), and the tools indicator kept its own per-buffer table (`tools/ux.lua:18,626-660`).

**Built.** `nvim/lua/ui/facts.lua`, a module whose interface is `facts.get(buf)` (a `ui.Facts`: `root`, `repo`,
`servers`, `formatters`, `linters`, `missing`, `unanswered`), `facts.event` (`"FactsChanged"`) and
`facts.setup(opts)`. `plugins/lualine.lua` is now an adapter that draws the facts. The indicator
(`tools.ux.status`) and `:Status` read them too.

**Decisions.**

- *Sources.* Each buffer's facts come from `lang.of(ft)`, the resolver's results (`tools.resolve`/`tools.get`,
  `tools.project`), `vim.lsp.get_clients` and `vim.fs.root`, never from conform's or nvim-lint's tables. A formatter or
  linter "will run" when its catalog binary was found. A linter also needs its covering server (the language's
  `covered_by`) not to be running. The same rule held on main, where it was spread over conform's availability check
  (`plugins/conform.lua:36-39`) and `tools/lint.lua:43-46`. No language's formatter has a `condition` or `require_cwd`
  in conform's definitions (`grep -n 'require_cwd\|condition'` over the 16 formatters in `conform/formatters/`: none), so
  conform's answer was the binary check alone.
- *What will run is one function,* `plan(buf, found, root, servers)` (`ui/facts.lua:53`). Step 2's modules are
  `format` and `linting` (not `lint`, which would shadow nvim-lint), and their plans are tables whose `run` field is the
  list of names. Switching to them replaces the function's body with
  `return require("format").plan(buf).run, require("linting").plan(buf).run`.
- *Missing tools* are the binaries `catalog.needed(found)` lists (`tools/catalog.lua:155`) that resolved without a
  path. The function moved out of `tools/ux.lua`'s `needed` unchanged, requires included, so the prompts and the facts
  count the same binaries. A tool still resolving counts as neither found nor missing.
- *Cached per buffer, compared before announcing.* `get` computes on the first read. FileType, BufFilePost, LspAttach,
  LspDetach, ToolsChanged for the buffer's root and DirChanged mark a read buffer stale. On the next tick it is
  computed again, and FactsChanged fires once if the facts differ (`:111-145`). An event in the same tick merges into
  that one computation, and an event that changes nothing fires nothing. A read in between computes at once.
  BufEnter looks up only the checkout again (about 15 µs; `repo_of`, `:67`). A `git init` then shows on the next
  visit, as lualine's branch component looks again on BufEnter.
  Rejected: firing on every invalidation, which redraws the line on each of those events whether anything changed;
  recomputing on every BufEnter, which costs 206-242 µs per buffer switch for nothing (cost below).
- *The facts wait for what they left pending.* ToolsChanged fires only for a result that differs from the one before a
  refresh (`tools/init.lua:434-462`). So facts read while a refresh re-resolves the same tools would keep "still
  resolving". A computation that finds a tool resolving, or the project scan missing, waits on `tools.resolve_all`
  and `tools.project` itself, then marks the buffer stale (`:98-106`).
  Rejected: relying on ToolsChanged alone. Main's lualine hid the same gap by recomputing on every BufEnter.
- *ToolsChanged also fires when a project's prompt state changes.* A refresh scans every root it scanned before again,
  with or without tools. ToolsChanged then fires for a root, with an empty tool list, when its configs, its answer to
  the project prompt or its trust differ from the last scan (`tools.refresh`, `tools/init.lua:616-647`). Before this,
  an answer that changes no tool's result ("No, use my global tools" with the same versions), or a new mise config that
  pins only tools the buffer doesn't run, fired nothing. The indicator's `?` then stayed as it was. Review found it
  with a probe: after the answer, no ToolsChanged and `facts.unanswered` still true. On main, `tools.ux.status` read
  `tools.project` on every draw, so the `?` changed with the next lualine rebuild.
  The listeners of ToolsChanged that act on tools (servers, nvim-lint) filter by its tool list, so an empty list does
  nothing there. Rejected: reading `unanswered` live on each draw again. The facts then wouldn't hold everything the
  indicator shows, and a rebuild would ask tools again.
- *Running servers, defined once.* `core.lsp_servers.running(buf, name?)` (`core/lsp_servers.lua:172`) is the
  clients attached to a buffer and not stopping (`client:is_stopped()`, which `Client:stop` sets before any event,
  runtime `lua/vim/lsp/client.lua:924,1123-1125`). It lives in the module that starts and restarts the servers, the
  lsp module of the target layout. The facts list it, and `tools.lint.covered` (`tools/lint.lua:15`) skips a linter by
  it, so after `:LspStop ruff` both say ruff's linter runs again. On main, the covered check counted a stopping
  client. Step 2's `linting` plan should ask it too. The facts also leave out a client in its LspDetach: it stays in
  `attached_buffers` until `_on_detach` ends (`client.lua:1435-1468`), so LspDetach records its id and a read during
  that event leaves it out.
- *The linters running now are not a fact yet.* No segment draws them, and nvim-lint fires no event when a run starts or
  ends: its list changes in a libuv exit callback (`lint.lua:415-421`), and publishing the diagnostics is a separate
  step that can come before or after it. Once step 2's `linting` owns the runs and fires an event, they can become a
  cached fact. Rejected: a live read of nvim-lint's list in the facts (the first build). It had no caller and was the
  only place the facts knew nvim-lint's shape (review). Also rejected: caching it until DiagnosticChanged, which races
  with the exit.
- *The branch name and the diff counts stay outside the facts.* lualine's branch component reads HEAD and watches it,
  and gitsigns already caches the counts in `b:gitsigns_status_dict` (neoblocks decisions 8 and 9 read them the same
  way). The facts hold `repo`, the checkout found with `vim.fs.root(folder, ".git")` (a `.git` file too, as #22 made the
  branch's condition). Both the branch's condition and the path's project name read it.
- *The path's project is the checkout, found without a process.* On main it came from `git rev-parse --show-toplevel`
  per folder, else the cwd (`plugins/lualine.lua:78` on 30877d7). Now it is `repo`, else the cwd. They differ for a
  path reached through a symlink (git resolves it, `vim.fs.root` walks the path as named) and for a file inside `.git/`
  (git fails there, `vim.fs.root` finds the checkout above).
- *`unanswered` is a fact.* With it in the compared facts, the ToolsChanged that a changed project prompt state fires
  redraws the line, even when no tool's state changed.
- *The adapter.* Segments draw `facts.get`. The lists show the current buffer, or the last file buffer while the
  current one isn't a file, as main's cache skipped `buftype ~= ""` (`plugins/lualine.lua:108` on 30877d7). Being per
  buffer fixes main's shared cache: an LspAttach or a write in another buffer overwrote the lists shown for this one
  (`:104`). The 12 listeners become 3: FactsChanged on `facts.event`, so the typed `"ToolsChanged"` is gone by
  construction, and CursorMoved/CursorMovedI for the search count, which isn't a fact. RecordingEnter, RecordingLeave
  and Progress joined lualine's own `refresh.events`. The DirChanged root cache went.
- *`:Status`* takes its LSP and Formatters lines from the facts, so it no longer asks conform. The LSP line now names
  each server once and leaves out a stopping one. Its Linters line still lists every linter the language names: that is
  a different fact (what is configured, not what will run), so it stays.
- *`tools/lint.lua`'s `to_run`* has no caller left. It stays for step 2, which replaces that file, so the two branches
  don't conflict there.
- *Test seam.* `facts.setup({ lang = lang._from(specs) })` swaps the language registry, as `tools.setup({ backend })`
  swaps mise. `facts.setup()` runs when the module loads; it is first required when lualine loads (VeryLazy), so
  nothing is added to startup.

**Deviation: which checks changed.** The proposal counted 3 checks that read lualine (Part 4). At cf220c8 they were
`statusline_cursor`, `statusline_linters` and `tools_indicator` (`git grep -l lualine cf220c8 -- tests/regress/checks`).
Only `statusline_linters` judged what the facts now hold. It became `checks/ui_facts.lua` (the facts with real tools
and servers: a found linter runs, a missing one doesn't and its binary is missing, a linter covered by an attached
server doesn't, and the formatters are the ones conform's own `list_formatters_to_run` gives, so drift from the plugin
fails) and `checks/statusline_facts.lua` (the line draws the facts, keeps the file buffer's while a non-file buffer is
current, and redraws on FactsChanged alone, with lualine's 1 s timer stopped and DiagnosticChanged and Progress
ignored). `statusline_cursor` (cursor and search count,
drawn by Neovim's expressions) and `tools_indicator` (the wrench, its count and `?`) stay as they were.
`statusline_branch`, `statusline_palette` and `statusline_path_percent` are unchanged too.

**Cost** (principle 6). Measured warm in the regress sandbox on nightly, `app.py` with pyrefly and ruff attached, median
of 7 rounds, by a scratch check run from `work/` (`~/.cache/nvim-config/rearch/ui-facts/bench/statusline_bench.lua`).
Main is origin/main's `nvim/` run with `CFG`. Two runs each:

| µs                                          | main 30877d7   | this branch |
|---------------------------------------------|---------------:|------------:|
| lualine rebuild (`refresh`, forced)         | 213.5, 204.5   | 164.9, 169.1 |
| list update on each BufEnter, FileType, attach, detach, write | 875.6, 1000.6 (conform 610.8, 639.2; `to_run` 107.6, 133.9) | none |
| facts read, cached                          |                | 0.1, 0.1    |
| facts computed, on a change                 |                | 223.0, 214.2 (`tools.root` 154.8, 155.9) |
| checkout lookup on BufEnter                 |                | 15.1, 14.8  |

A rebuild now reads the facts and does no lookups of its own (main ran `vim.fs.root` for the branch's condition on
each one). Most of the remaining rebuild is lualine itself, so the ≤ 100 µs budget waits for neoblocks.
`tools.root` is most of a computation. It runs once per change instead of on every event.

**Tests.** `tests/unit/facts_test.lua` (fixture languages, fake backend, fake servers; 14 cases): what will run and what
is missing, a new filetype's tools, the project prompt's `?` set by a new config and cleared by an answer that change
no tool, a buffer that isn't a file following a `:cd`, a server on attach and detach and its covered linter, a server
with two clients listed once, a stopping server and one read inside LspDetach, a read with no event since serving the
facts as they were (a client attached with every event ignored stays unlisted) and fresh reads after ToolsChanged and
an attach, one FactsChanged per change and none for FileType or BufEnter that change nothing, a tool still resolving, a
refresh that finds the same tools, a rename, and the checkout (dir, `.git` file, none, `git init` then a visit).
24 sibling wrong implementations of `ui/facts.lua`, of the prompt-state event in `tools/init.lua` and of
`core.lsp_servers.running` each fail it (`~/.cache/nvim-config/rearch/ui-facts/mutants/mutants.py <worktree>`).
Three siblings are left out because they pass, and none of the three changes anything a reader can see. Two only
cost time: recomputing on ToolsChanged for any root, and on every BufEnter. The third keeps a wiped buffer's entry:
`get` answers an invalid buffer without the cache and the flush skips it (`ui/facts.lua:148-152,116`), so only the
memory shows it. The regress checks were run against configs with one bug each:
- an adapter without the FactsChanged listener fails `statusline_facts`;
- an adapter that shows the current buffer's lists in a non-file buffer fails `statusline_facts`;
- facts that run a covered linter fail `ui_facts`;
- facts whose formatters are in another order than conform's fail `ui_facts`;
- an indicator count off by one fails `statusline_facts` and `tools_indicator`.

## Step 2: format/ and lint/ (2026-10-17)

Built on `rearch/format-lint` from `origin/main` 30877d7 (step 1 included). Behaviour is unchanged; what the card in
the proposal (Part 4, "Formatting · format/" and "Linting · lint/") sketched, and what changed from it.

**Built.** `nvim/lua/format/` and `nvim/lua/linting/`, each a module with one adapter file that is the only code
knowing its plugin (`format/conform.lua`, `linting/nvim_lint.lua`). The plugin specs shrink to loading the plugin and
calling `setup()` (`plugins/conform.lua`, `plugins/nvim-lint.lua`, which keeps the `<leader>ll`/`<leader>li` maps
until step 3). Gone: `format_buffer` patched onto conform's table, the save hook and `vim.g.snacks_format_on_save` in
the snacks spec (nothing else read the flag: `grep -rn snacks_format_on_save nvim tests` finds none),
`has_formatter`'s and `has_diagnostics`'s bodies in `core/lsp.lua`, and `tools/lint.lua`.

Interfaces:

- `format.buffer(buf?, { async? })` formats with the formatters that run, else an attached server (conform's
  `lsp_format = "fallback"`), and reports once what ran, the formatter's or server's own error (the adapter turns a
  server's error table into text), or that nothing can format the buffer; it waits for binaries still being looked
  up, as conform's command did (`nvim/lua/format/init.lua:103`). `<leader>lf`, `:FormatWithConform` and the save hook
  call it; in visual mode conform formats the selection. A `range` option waits for a caller (step 3 at the earliest).
- `format.on_save` is a `{ get, set }` pair (`format/init.lua:158`), the shape the keys card's
  `toggle = format.on_save` takes; the snacks toggle row passes them through.
- `format.plan(buf)` is `{ formatters, run }`, `linting.plan(buf)` is `{ linters, run, covered }`: what the language
  names, what of it runs now (a binary still being looked up does not), and which linters an attached server covers.
  Cached per buffer (`format/init.lua:71`, `linting/init.lua:91`). A first build also had `resolving`, which only the
  tests read; review had it dropped, as `run` already leaves out what is being looked up.
- `format.has(buf, range?)` and `linting.has(buf)` are the "formatter" and "linter" needs: a formatter the language
  names, installed or not, or a server that formats (a range, with `range`); a linter the language names. These are
  the answers today's gates give (`checks/keys_format_gate.lua`, `checks/keys_diag_gate.lua` pass unchanged), and
  `core/lsp.lua`'s rows now call them.
- `linting.buffer(buf?, names?)` lints with the resolved binaries; the module lints on BufEnter, BufWritePost and
  InsertLeave as before (the BufEnter question stays open, Part 9), drops a covered linter's findings when its server
  attaches, and lints a root's buffers again on ToolsChanged with the linters that changed.

**Decisions.**

- *The module is `linting/`, not `lint/`.* nvim-lint's own Lua module is `lint` (`nvim-lint/lua/lint.lua`, with
  `lua/lint/linters/*.lua`), and the config dir comes first on the runtimepath, so a `lua/lint/init.lua` here would
  shadow it for every `require("lint")`, nvim-lint's and the checks' included. `format/` collides with nothing (no
  plugin in `tests/regress/data/nvim/lazy/*/lua/` has a `format` module).
  Rejected: `formatting/` and `linting/` for symmetry, which renames a module the task and the layout name.
- *A plan is computed from `lang.of` and the resolver, not from conform's `list_formatters_to_run`.* For a formatter
  with a catalog binary, conform's availability check is "the command is executable"
  (`conform/init.lua:755-820`), and the command is the resolved path, so "the binary is found" is the same answer.
  None of the 16 formatters the languages name has a `condition` or `require_cwd` (grep over
  `conform.nvim/lua/conform/formatters/<name>.lua` finds none). A name with no catalog binary, which only test
  languages use, asks conform (`format/conform.lua:56`). This keeps the plan readable with no plugin loaded, and costs
  a quarter of conform's list (below).
- *What drops a plan.* FileType, BufFilePost (a new root), DirChanged (a buffer that isn't a file has the cwd as its
  root), BufWipeout, ToolsChanged for the plan's root, and a lookup the plan started finishing: a lookup whose result
  did not change fires no ToolsChanged (`tools/init.lua:519-551`), so a plan made during a refresh would otherwise
  leave that tool out until the next drop. `linting.plan` is dropped on LspAttach and LspDetach too, and again on the next tick after LspDetach,
  since the detaching client counts as attached while the event runs (`vim/lsp/client.lua:1435-1469` on nightly
  0.13.0-dev-1868) and `ui.facts` can read plans from that event. A filetype set with `noautocmd` makes a new plan on
  the next read.
- *A root that moves with no event is caught where the root is found anyway.* A project marker made outside Neovim
  (`git init` in a terminal) moves a buffer's root and fires nothing. A lint finds the buffer's root before it runs,
  so it makes a new plan when the cached one was made for another root (`plan_in`, `linting/init.lua:107`), and the
  ToolsChanged relint uses the event's root. Review found the first build mixing the two: the filter passed a linter
  from the old root's plan while the wrap looked its binary up in the new root, found nothing, and ran the bare
  command from PATH with no cwd, on every BufEnter, until the next drop (probe in
  `~/.cache/nvim-config/rearch/format-lint-review/tmp/rootprobe/`, `out-main.txt` against `out-branch.txt`).
  `format.buffer` always makes a new plan. A `format.plan` or `linting.plan` read sees the new root at the next drop;
  checking the root on every read would cost `tools.root`'s 131-135 µs a read (below).
- *Servers are not cached for the format need.* A server's formatting can be registered after it attaches, and
  registration fires no autocmd (D48), so `format.has` reads `vim.lsp.get_clients({ bufnr, method })` when called;
  its language half is `lang.of`, a table lookup cached for the session. Neither half makes a plan, so a press or a
  which-key rebuild never pays the uncached plan. `linting.plan`'s `covered` is cached, since covering depends on a
  server attaching by name, which LspAttach and LspDetach report.
- *The plan watchers are made when the modules load, and `core/lsp.lua` loads them at startup.* Neovim runs an
  event's handlers in the order they were made, and `ui.facts` reads plans after its ToolsChanged and LspDetach
  handlers, so the drops must come first. `ui/facts.lua` requires both modules before it makes its handlers, so the
  order holds wherever facts loads first. The first build made them on the first read, which a statusline handler
  could be.
- *Formatter and linter definitions live in the adapters, by tool* (`definitions` in `format/conform.lua:9` and
  `linting/nvim_lint.lua:13`, with `keep_cwd` and golangci-lint's per-binary args beside them). conform and nvim-lint
  key a definition by tool name for every filetype, as the catalog keys binaries, and one tool serves several
  languages (prettierd: html, css, markdown, yaml), so no one language file owns its args. golangci-lint's args and
  `keep_cwd` are how the adapter runs nvim-lint, not language facts. Both adapters merge an entry over the plugin's
  own definition, so an entry with only `args` keeps the built-in's command and parser; the first build replaced
  nvim-lint's (raised in review).
- *The adapters keep the plugins' shapes.* `format/conform.lua` hands `format.buffer` its error as text, and
  `linting/nvim_lint.lua` answers which binary a linter runs (`M.binary`, `:68`: the catalog's, else a bare `cmd`),
  so `lint.Linter` and `lsp.ResponseError` stay out of the modules (raised in review).
  Rejected: the language files, beside each server's settings (D46): a shared tool's args would sit in one language
  and apply to the others unseen, and `lang.Formatters` would stop being a plain list of names.
- *conform still loads at VeryLazy.* It loaded there because the snacks spec required it for the save hook; the spec
  now lists only `VeryLazy`, so the save hook and conform's `formatexpr` start at the same point. A probe in the
  suite's sandbox read lazy's load reason on `main.lua`: `{ require = "conform", source = ".../plugins/snacks.lua" }`
  on main, `{ event = "VeryLazy" }` on the branch, with `formatexpr` set to conform's in both. The first build kept
  `BufWritePre` in the events too, which made a write before VeryLazy load conform, add the hook and format
  (`nvim --headless a.lua -c w`, found in review); a write before VeryLazy is again not formatted, as on main.
- *The save hook formats the written buffer (`ev.buf`)*, where it formatted buffer 0; Neovim makes the written buffer
  current for BufWritePre, so they are the same buffer.

- *A covering server counts while `core.lsp_servers.running` counts it* (`core/lsp_servers.lua:172`: attached and not
  stopping), the definition `ui.facts` uses, so `linting/init.lua` doesn't define "running" again. After `:LspStop
  ruff` the cached plan says covered until ruff's LspDetach drops it, as the facts keep listing ruff until that event.

**Deviations from the card.** `lint.running(buf)` is `linting.plan(buf).run`: one cached read gives `ui.facts`
its list and the gates `covered`, and "running" reads like nvim-lint's `get_running` (processes in flight). The unit
file is `tests/unit/linting_test.lua`, after the module.

**After step 4 (#32).** This branch was rebased onto step 4, which changed three things here:

- The facts' formatters and linters are `format.plan(buf).run` and `linting.plan(buf).run` (`ui/facts.lua`), which
  replaced its own `plan()`. A name with no catalog binary now runs when conform finds it, or when nvim-lint's bare
  command resolves, as on main, where the facts' first build counted it as always running; only test languages have
  such names. `ui_facts` still compares the formatters with conform's `list_formatters_to_run`.
- `facts.setup` lost `opts.lang`, which step 4's "Test seam" describes: the plans read the registry from
  `require("lang")`, so `tests/unit/facts_test.lua` sets `package.loaded.lang` to its `lang._from` registry, as the
  format and linting tests do. A seam only the facts saw would have given the plans another language than the facts.
- `tools/lint.lua` is gone, which step 4 left for this step, and the lualine change this branch had is dropped: step 4's
  spec draws only the facts. `:Status` already took its formatters from the facts.

**Cost.** Measured in the regress sandbox on `app.py` with pyrefly and ruff attached and every tool resolved, best of
five rounds per run, three runs (`~/.cache/nvim-config/rearch/format-lint/evidence/perf/`: `perf_needs.lua`,
`run-{1,2,3}.txt`):

| read | µs per call |
| --- | --- |
| `format.has(buf)`, `format.has(buf, true)`, `linting.has(buf)` | 1.1–2.5 |
| `format.has` on a filetype no language names, two clients attached | 1.2–2.3 |
| `format.plan(buf)`, `linting.plan(buf)`, cached | 1.2–1.9 |
| a plan made afresh (format, linting) | 132–166 |
| of which `tools.root(buf)` | 131–135 |
| conform's `list_formatters_to_run`, which main's statusline asked for its formatters | 576–637 |

A plan is made once per buffer and again only after a drop. A buffer whose language names no formatter (or linter)
skips the root lookup.

**Tests.** `tests/unit/format_test.lua` (10 cases) and `tests/unit/linting_test.lua` (11 cases) run the modules through
their interface on fixture languages (`lang._from`), the fake tool backend and fake servers, with a fake conform
(`format`) and a fake nvim-lint (`try_lint`'s filter and wrap, `get_namespace`) at the plugin boundary: the plan for a
buffer, a plan following a lookup, a refresh and ToolsChanged, the needs following attach, registration and detach,
the LSP fallback and the report, a plan following `:cd`, a rename and a project marker that appears, a covered
linter's findings dropping when its server attaches, and the relint of only the root's buffers with only the changed
linter. 32 sibling wrong implementations and a do-nothing stub of each module fail them (`~/.cache/nvim-config/rearch/format-lint/evidence/mutants/`: `unit.sh all.tsv`,
`unit-results.txt`). In the suite, `checks/format_on_save.lua` is new: writing a Lua file writes it formatted, and
after `<leader>Tf` it is written as it is (it turns formatting on save on first, so it tests the rule, not the
default); three wrong save hooks fail it (ignoring the toggle, no hook, an async
format), `save-check-results.txt` there. `checks/format_buffer.lua` changed only its call, from
`conform.format_buffer` to `format.buffer`.

**Left for later steps.** The keys stay where they are (step 3): `core/lsp.lua`'s rows, the snacks toggle row and
nvim-lint's `<leader>ll`/`<leader>li` maps call the interface above.
