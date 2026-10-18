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
  below).
- Built: step 2, `format/` and `linting/` ("Step 2: format/ and lint/" below).
- Built: step 4b, neoblocks.nvim's statusline replaces lualine ("Step 4b: neoblocks statusline" below).
- Built: step 3, `keys/`, with D49 ("Step 3: keys/" below).
- Built: step 5, `features/`, with `lsp/`, `textobjects/` and the rest of `ui/` ("Step 5: features/" below).
- Built: step 6a, `app/` runs startup as named, timed phases, still on lazy.nvim ("Step 6a: app/" below).
- Built: step 6b, vim.pack replaces lazy.nvim (D45; "Step 6b: vim.pack" below).
- Built: D73, `docs/languages.md` generated from `lang/` by `mise run docs` ("D73: the per-language tool tables are
  generated" below).
- Decided and built (2026-10-18): D72, linting skips a BufEnter that can't find anything new (below).
- Fixed: no process a server started outlives the server or Neovim: its process group is killed when the server
  exits and again at quit ("Server children at quit" below).
- Decided and built (2026-10-18): D78, messages and the command line come from neoblocks' messages module, and
  neoblocks loads at startup (below).
- Decided (2026-10-18): D93, an amendment to D61: a one-off cost is judged by its delta, not by whether the
  total crosses ~100 ms ("D61 amendment" below).
- Fixed (D95): no linter run outlives Neovim: what is left of each is killed at quit, or when the run exits
  ("Linters at exit" below).

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
    ├── ui/             facts, statusline, theme, picker, notify; messages are neoblocks' (D78)
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
  InsertLeave as before (the BufEnter question stays open, Part 9; D72 below answers it), drops a covered linter's findings when its server
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

## Step 4b: neoblocks statusline (2026-10-17)

Built on `rearch/neoblocks-statusline` from `origin/main` 0c1277f. lualine.nvim goes; the statusline is the one from
our own plugin, [neoblocks.nvim](https://github.com/AH-Merii/neoblocks.nvim) v0.2.0 (commit db1fced, `git ls-remote
https://github.com/AH-Merii/neoblocks.nvim refs/tags/v0.2.0`). The user sees the same line.

**Context.** Step 4 made lualine an adapter over `ui/facts`, and its rebuild (164.9 and 169.1 µs) was mostly lualine
itself, so the ≤ 100 µs budget waited for neoblocks ("Cost" in step 4). neoblocks' statusline was written against
this config's lualine spec, segment by segment (neoblocks `docs/decisions/statusline.md`, "the parity target"), and
its own bench checks that both draw the same text (decision 14 there).

**Built.** `plugins/lualine.lua` becomes `plugins/statusline.lua`, an adapter that gives neoblocks the same segments:
`require("neoblocks").setup({ statusline = { color, left, right, events } })` (`plugins/statusline.lua:322`). The
lock file drops lualine and pins neoblocks.nvim at db1fced, so the test image's plugins stage installs it from the
lock with the other plugins (`tests/image/Dockerfile:116`, lazy `install`/`restore`, `tests/regress/refresh.lua:15`).

**Decisions.**

- *The config's own segments stay functions.* The path, the server, formatter and linter lists, the tools indicator
  (its click runs `:Tools`) and the pending keys are the same functions as before; neoblocks puts a function's text in
  unescaped, as lualine did (neoblocks decision 3), so the path keeps its own colour groups and `%` escaping. The
  location and progress, which were functions returning an expression, are the expressions themselves: raw `%`
  strings are drawn as they are (neoblocks decision 2).
- *lualine's components become neoblocks' built-ins:* `diagnostics`, `branch`, `diff`, `searchcount`,
  `progress_status` and `recording` (`plugins/statusline.lua:277-310`), with the same symbols, icons and colours;
  `gui = "bold"` is `bold = true`. The mode icon's colour function is `sl.mode_color` with red as the fallback
  (`:209`). The macro segment was a function returning `" @q"` (0c1277f `plugins/lualine.lua:207`); it is the
  `recording` built-in with that icon, which draws the same text (neoblocks decision 11).
- *diff* came from gitsigns already (the `source` function, 0c1277f `plugins/lualine.lua:359`); neoblocks' `diff` reads
  the same `b:gitsigns_status_dict` and redraws on `User GitSignsUpdate`, so the source function goes.
- *The search count* no longer needs the spec's CursorMoved refresh (0c1277f `plugins/lualine.lua:381-387`): neoblocks
  counts on a move only while a search is highlighted, at most once per 16 ms, and updates only the count (neoblocks
  decision 6).
- *Rebuilt on events only; no timer.* lualine also refreshed once a second. neoblocks has no timer (neoblocks decision
  5), so each thing the timer caught needs an event. The lists and the indicator: FactsChanged calls `sl.refresh()`
  (`:88-91`), as it called lualine's refresh. The branch: neoblocks watches HEAD. The search count after `:nohlsearch`:
  an expression. The path after a rename, after a `:cd` and its width after a window resize: the spec adds
  `BufFilePost`, `DirChanged` and `WinResized` to lualine's other events (`:334-335,340`). neoblocks' `branch` built-in
  also rebuilds on DirChanged (neoblocks `lua/neoblocks/statusline.lua:360`), but the path shouldn't depend on the
  branch segment being there. Typed with `:`, a rename or a resize also rebuilds the line on the ModeChanged of leaving
  the command line; from a mapping it doesn't, so `checks/statusline_events.sh` runs them from `<Cmd>` mappings
  (below). DiagnosticChanged, Progress and the recording events come with the built-ins that need them.
- *The path's colours after `:colorscheme`.* A colorscheme starts with `:hi clear`, which empties the path's groups.
  The handler that defines them again on ColorScheme had been commented out since the config was imported (104932f;
  `git log -S` on it finds only that commit and this branch's rename, and no reason is recorded). It is back (`:198`), in its own commit, since main has the same
  bug.
- *The path's colour groups are named `Statusline*`* (`:60-63`), not `Lualine*`: lualine is gone.
  Rejected: keeping the old names to leave `statusline_palette` untouched; that check read the group names, which is
  how the line is built rather than what it shows, so it now reads the drawn colours instead (below).
- *Leftovers.* README names neoblocks' statusline. onedark's `lualine = { transparent = true }` option goes from
  `plugins/colorschemes.lua`: only onedark's own lualine theme read it, and the config never used that theme.

**Parity, measured.** A scratch check, `statusline_dump.lua` (in `~/.cache/nvim-config/rearch/statusline/bench/`, run
from `work/`), drew the line with `nvim_eval_statusline(..., { highlights = true })` at 200 columns in seven states (a
Python file with pyrefly and ruff attached, diagnostics and git changes; a search on a match; recording a macro; a
progress message; Insert mode; a non-file buffer; a Lua file) and wrote each piece's text, fg and bold. main's config
and this branch's give the same output, except a progress percentage that lua_ls's own progress made differ between
runs (`diff before.txt after.txt`: one line, `󰔟 41%(2)` against `󰔟 40%(2)`). Screenshots in Ghostty (niri-screen-lab,
71 columns, `tests/regress/nv.sh nightly`) of a Python file with servers in a git repo with changes, and of a non-file
buffer, are pixel-identical between main and this branch (`magick compare -metric AE`: 0 for both); at that width
the line is cut from the left, so they show the lists and the branch. They are in
`~/.cache/nvim-config/rearch/statusline/`.

**Gaps.** None found that the user sees. Known differences that don't show: on Neovim 0.12.6 lualine showed a
progress message as `40%%(1)` and neoblocks as `40%(1)` (neoblocks decision 10); the suite and the screenshots run
nightly, where both show `40%(1)`.

**Cost** (principle 6). The step-4 bench (`statusline_bench.lua`, same fixture, `app.py` with pyrefly and ruff
attached, median of 7 rounds of 300 rebuilds) run on main's `nvim/` (lualine's `refresh({ force = true })`) and on
this branch (`require("neoblocks.statusline").refresh()`), alternating, three runs each. The machine was shared with
other agents' suites, so the bench reads this process's CPU time (`vim.uv.getrusage`) instead of the wall clock:

| µs per op                         | main 0c1277f        | this branch      |
|-----------------------------------|--------------------:|-----------------:|
| rebuild                           | 165.3, 169.7, 165.1 | 69.6, 64.6, 61.2 |
| redraw (`:redrawstatus`)          | 70.6, 83.0, 58.1    | 85.7, 53.2, 60.3 |
| spec's `config()`, median of 15 (ms, wall) | 1.42, 1.60, 1.40 | 1.44, 0.66, 0.69 |

The rebuild is within the ≤ 100 µs budget. The redraw is level within the noise: both lines are plain statusline
text that Neovim parses. The `config()` row runs the spec's config again after startup (plugin modules already
loaded), so it is the setup's own cost; neoblocks' `meta.modules()` (a runtimepath glob) is 0.19-0.21 ms of it. The
statusline loads on VeryLazy, after the first screen, so startup itself is unchanged: the `startup` check passes in
0.4-0.5 s on both (three runs each).

**Checks.** Four regress checks called `require("lualine").refresh(...)` before reading the line
(`git grep -l 'require("lualine")' 0c1277f -- tests/regress/checks`): `statusline_branch`, `statusline_cursor`,
`statusline_path_percent` and `tools_indicator`. `statusline_facts` stopped lualine's timer, and `statusline_palette`
read the path's `Lualine*` groups. The first five read the drawn line already (`nvim_eval_statusline`); now they wait
for it to follow its events instead of forcing a rebuild, which also checks that it does:
- `statusline_branch`, `tools_indicator`: the forced refresh is gone; they already waited (`wait_until`) for the line.
- `statusline_cursor`: waits for the line to show the file after `:edit`, instead of forcing it.
- `statusline_path_percent`: waits for the line to show the wanted path after the width changes (VimResized).
- `statusline_facts`: it stopped lualine's 1 s timer and checked that it found exactly one. It now pauses every
  repeating timer until the line follows the detach, then starts them again (`timer:again()`): a line redrawn by any
  timer, not only a 1 s one, would hide a missing FactsChanged listener (review found one with a 250 ms timer).
  lualine's own refresh queue was a repeating timer, so the pause comes with the swap; the test commit before it
  keeps stopping only the 1 s timer, and passes on main's lualine. It also waits, after closing the non-file window, until the line shows the file again, so no rebuild is still pending
  when ruff detaches; without that wait the rebuild the close asked for ran after the detach.
- `statusline_palette` read the `Lualine*` group names. It now draws a file two folders deep at 200 columns and
  checks the colour drawn at the project name, the folder names and the file name (`nvim_eval_statusline` with
  `highlights = true`), at startup and again after `:colorscheme onedark` (with the fix commit).

New: `checks/statusline_events.sh` runs nvim in a TUI under tmux and reads the last row. Headless, a check's
`vim.wait` fires no WinResized (review), and a `:`-typed command rebuilds the line through ModeChanged anyway. It
splits and runs `:only`, `:cd`s and renames with `nvim_buf_set_name`, each from a test `<Cmd>` mapping, and waits for
the path to follow. Typed `<C-w>v`/`<C-w>o` were tried first: with them the config without WinResized still passed,
so another event rebuilt the line there (not identified); `:only` from a mapping fires none but WinResized.

Each was run against configs with one change each from this branch's final `nvim/`
(`~/.cache/nvim-config/rearch/statusline/mutants/`, `run.sh <worktree>`; results in `mutants.log`, and `events.log` for
the final `statusline_events.sh`):
- no FactsChanged listener fails `statusline_facts`; so does no listener with a 250 ms timer calling `refresh()`;
- the current buffer's lists shown in a non-file buffer fails `statusline_facts`;
- the fallback palette instead of onedark's style fails `statusline_palette` (all six cases);
- no ColorScheme handler fails `statusline_palette`'s three cases after `:colorscheme onedark`;
- a path whose `%` is not escaped fails `statusline_path_percent`;
- no WinResized (and no VimResized with it) fails `statusline_events`' `:only` case;
- no BufFilePost fails its rename case;
- no DirChanged and no branch segment fails its `:cd` case (and `statusline_branch`).
Two pass, as expected: no DirChanged alone (the branch built-in still rebuilds on it), and no VimResized and
WinResized for `statusline_path_percent`: at 20 columns the stale full path also contains the wanted file name. That
check is about `%`, so it stays as it was on main.

## Step 3: keys/ (2026-10-17)

Built on `rearch/keys` from `origin/main` 0c1277f (steps 1, 2 and 4 included), then rebased onto 7a98192 (step 4b
and #37), to D48's interface and mechanism and D49. What was built, and where it departs from D48.

**Built.** `nvim/lua/keys/init.lua` (rows, needs, the maps, `holds`, `menu`, `list`), `keys/which_key.lua` (the only
code that knows which-key: its setup, one spec per mode and lhs, the filter) and `keys/neovim.lua` (Neovim's own keys
as rows: groups, labels for built-ins and the runtime's maps, hidden keys, the runtime ftplugins' labels). Owners
declare their rows where they live: `core/lsp.lua`, `config/keymaps.lua`, `config/textobjects.lua`, and the specs for
snacks, git, nvim-lint, nvim-treesitter, which-key and PR review (`plugins/extras.lua`). Gone: which-key's spec,
groups and filter in `plugins/which-key.lua`; core/lsp's key table, sync, `M.map`, handler wrap and K case; nvim-lint's
key gate; treesitter's per-buffer keys; gitsigns' `on_attach` maps and their `GitSignsUpdate` deletion; the snacks
toggle wiring and every `_wk` call; lazy `keys` tables; `utils.label_ftplugin_maps` and the five
`after/ftplugin/{go,markdown,php,python,rust}.lua` that only labelled the runtime's maps (`lua.lua` and `vim.lua`
keep their own maps).

Not moved, so not every mechanism D48 counts is gone: the text-object dispatch, one global expr map per key that runs
the treesitter object or the key's own meaning (`config/textobjects.lua:281-315`, labelled through `listed` rows); the
FileType `q` maps (`config/autocmds.lua:125`) and the `[Output]` buffer's `q` (`config/ui2/messages.lua:149`). Step 5
inherits them, with two more: the runtime ftplugins' labels in `keys/neovim.lua` belong in the language files under
D46, and `config/textobjects.lua` still reads which-key's presets (below).

The needs: LSP methods by short or full name (`vim.lsp.protocol.Methods`), `client:pyrefly`, and the words
`formatter`, `range formatter`, `diagnostics` (`core/lsp.lua:30-33`), `linter`, `uncovered linter`
(`plugins/nvim-lint.lua:12-13`), `git` (`plugins/git.lua:23`), `git cwd`, `git file`, `git remote`
(`plugins/snacks.lua:7-24`), `treesitter` (`plugins/nvim-treesitter.lua:117`) and `github` (`plugins/extras.lua:108`).
Each is a table lookup; what is slow (git, the remote) is cached by its owner from its own events.

**Decisions.**

- *A press:* a row that always acts is a plain map; any other slot is one expr map that returns the first acting
  row's keys, else the fallback: an echo for a leader key or an `echo` row, else the global map it took over
  (recorded when the slot is made), else the lhs, Vim's own key (`fallback` and `place` in `keys/init.lua`).
- *The echo* is `nvim_echo` with history (`M._echo` in `keys/init.lua`), not `vim.notify`: Snacks' notifier opens a float,
  which `checks/keys_diag_gate.lua` ("opens a window, want nothing") rightly failed.
- *Toggles* take a Snacks toggle (its `get`, `toggle`, `wk_desc` and icons) or a `{ get, set }` pair, for which keys
  says "Enabled/Disabled **name**" in Snacks' words; `format.on_save` is passed as such a pair.
- *One memo per popup rebuild:* the adapter wraps which-key's `Tree.clear`, which runs before each mode's rebuild,
  on every popup (`which-key/buf.lua` `Mode:update`, `which-key/state.lua` `M.start`), and starts a new memo there
  (`keys/which_key.lua:63`). A need shared by many rows is tested once, and each key's label and icon are worked out
  once, from one read of the buffer's maps (`buf_maps`, `M._label`); a toggle's label is read each time, as a press
  changes it between rebuilds (`checks/toggle_wk_specs.lua` reads it right after a flip). Review measured the first build reading labels
  unmemoized: with the review's probe (`keys-review/probes/rv_cost.lua`, 17 leader items, desc and icon read twice as
  which-key's view does) reading them took 477–569 µs before and 136–201 µs after, against 13–16 µs on main, whose
  labels were mostly static strings; a rebuild is 2.0–2.5 ms on both.
- *A spec per mode and lhs,* with desc and icon getters over the rows, because which-key calls a getter with no mode.
  A label-only row is `real` by default (listed only where something maps the key); `native = true` lists a built-in
  with no map; `group` and `hidden` are which-key's.
- *A row declared again from the same place replaces itself.* lazy unloads and runs each spec module again after an
  install or update (`lazy/core/plugin.lua:184`, called from `lazy/core/loader.lua:92` and `lazy/manage/init.lua:92`),
  so rows declared in a spec file run twice on a fresh home; appending made every such key an expr map with two rows
  (probe on a fresh sandbox home: two entries for `<leader>ff`). `keys/init.lua` keys an entry by owner, file:line and
  position, and `list()` reads the slots.
- *An owner's needs and the events that fill their caches run together.* The same re-run made snacks' git needs read
  new, empty caches that only the old autocmds, made once in its config, filled: `<leader>gf`, `<leader>gL` and
  `<leader>GB` stopped acting everywhere until a restart (found in review). The autocmds are now made beside the needs,
  at module level in a cleared augroup, and a re-run looks the open buffers up again (`plugins/snacks.lua:43-56`). The
  other owners declare their needs inside `config` or `init`, which lazy does not run again, with their caches.
  `checks/keys_spec_reload.lua` is new: it reruns the spec load as lazy does, then compares the needs that hold and
  presses `<leader>gf`; it fails on the first build ("lost: git file", "picker: nil").
- *Where a buffer's own map wins the press, the popup shows its desc,* not a global row's label or icon; a label-only
  language row labels only a buffer map with no desc, as `utils.label_ftplugin_maps` did on main. The first build
  said "Document symbols" for markdown's `gO`, which runs the ftplugin outline, where main says "Show an Outline of the
  current buffer" (found in review), and "Next heading" for `]]`, where main shows the runtime's "Jump to next
  section". Both now match main.
- *A row that takes over a Neovim default deletes it in keys/.* `keys/neovim.lua` deletes Neovim's `grn`, `gra`,
  `gri`, `grt`, `grx`, `gO` and `grr` and declares the first six as rows with Neovim's own callbacks, so the default
  is never the fallback; it loads before `core/lsp.lua`, whose `grr` row is the references picker.
- *A hidden row keeps its spec* so which-key hides the key, whoever maps it (`keys/init.lua`, `M._lists`); filtering
  the spec out listed Neovim's `]L`, `[Q`, `]%`, … and x `an`/`in`. `checks/wk_hidden.lua` is new for this: it passes
  on main and on this branch, and fails on the branch without the two lines.
- *mapleader before rows:* `init.lua` now loads `config.options` before the rows, and `keys` raises for a
  `<leader>` row added before mapleader is set.

**Departures from D48.**

- *`listed`, `echo`, `native`, `hidden`, `group`, `remap`, `silent`, `nowait` fields.* D48 named the rows' core fields;
  these carry what the replaced specs said. `listed` is a function the text objects use for "a meaning of its own
  here" (`config/textobjects.lua`, `M.shown`), a fourth kind of gate beside the three need kinds.
- *`config/textobjects.lua` still reads `which-key.plugins.presets`* for a native key's label. It is data, not
  which-key's API, but it means keys/ is not the only file that names which-key. Left for step 5.
- *The treesitter need covers four keys:* `<leader>v`, x `+` and `-`, `<leader>TT` act where a parser is attached;
  on main only `<leader>TT` was deleted when a buffer's filetype changed to one without a parser
  (`git show 0c1277f:nvim/lua/plugins/nvim-treesitter.lua`, line 165).
- *PR review asks git afresh on each `DirChanged`* and its keys don't act until git answers; main kept the previous
  cwd's map until then.

**Checks changed.** The gr* case in `checks/keys_lsp_gate.lua` (D49, in its own commit). Removing `echo = true` from
the gr* rows fails it for all six keys ("grr says it needs textDocument/references (said: "")"). Outside the D48 prep
list:

- `checks/trouble_maps.lua:56` read `require("core.lsp").keys`, which is gone; it reads `require("keys").list()`.
- `checks/lsp_codelens.lua` read `maparg("<leader>Tc").buffer == 1` and waited for a buffer `K`; it reads which-key
  (`wk_lists`, `wk_wait`). The assertions are unchanged.
- `work/keys/keys_global_regress.lua` called every global map whose desc is "Toggle X" as a toggle. Gated toggles are
  now global expr maps, whose callback returns keys; it skips expr maps, as it skipped buffer maps before. Its counts
  match main: 28 find/search maps open pickers, 11 toggles flip; "lazy keys without ft" drops from 94 to 18, as the
  snacks keys are rows now.

**What `work/keys/` shows.** All four checks pass. `whichkey_ghosts` finds no ghost and no empty group in any of its 9
buffers. The popup's leaves match main's except git: the hunk keys, `<leader>gb`, `<leader>gd` and `<leader>TG` are
listed in every buffer where gitsigns has attached (`b:gitsigns_status_dict`); main listed them in 2 or 3 of those 8
buffers, a different set in each of two runs (`main.go` and `notes.md`, then those and `index.ts`). Unverified why;
likely its `on_attach` maps were not yet set when the status the check waits for was.

**Keys whose behaviour changed.**

- `grn`, `gra`, `grr`, `gri`, `grt`, `grx` with no server: a message naming the method, not `gr{char}` (D49).
  `gO` also echoes; its suite case expects "nothing" and still passes.
- A leader key whose need fails echoes the need (D48), where main had no map: e.g. `<leader>TG` outside git,
  `<leader>ll` with no linter, `<leader>p` outside a GitHub repo.
- The map descs of `<leader>w` ("Save file" → "Write") and `<leader>q` ("Quit without saving" → "Quit") now match
  what the popup showed.
- `:map`, `maparg` and `<leader>sk` list gated keys in every buffer (D48's accepted cost).

**Cost.** Startup in the regress sandbox, headless on `main.lua`, `--startuptime`, 9 runs per round, rounds
interleaved (`~/.cache/nvim-config/rearch/keys/bench/startup.sh`): main 94.4 and 89.0 ms median, this branch 88.8 and
90.1 ms; within noise. The `require('keys…')` lines' self time is 1.66–1.67 ms median, against D48's estimate of
0.90–1.06 ms for the maps alone; it includes `keys/neovim.lua`'s rows for Neovim's own keys.

**Tests.** `tests/unit/keys_test.lua` (22 cases) drives `keys` through its interface with real presses, fake servers
and test words: fallbacks, echoes, buffer maps winning the press and the label, the global `K`, toggles, language
rows, label-only and native rows, the memo, unknown fields, `list()`, and rows declared again. 23 sibling wrong
implementations and a do-nothing stub fail it (`~/.cache/nvim-config/rearch/keys/mutants/run.py <worktree>`). Three
suite checks are new: `wk_hidden`, `keys_spec_reload` and `keys_map_desc`, which holds every global row's map to its
label as desc, so `:map` and `<leader>sk` describe gated keys too (review found no check did once the snacks keys left
lazy's `keys`). Wrong implementations for them each fail their check
(`~/.cache/nvim-config/rearch/keys/suite-mutants/run.py <worktree> <regex>`): expr maps or plain maps losing their
desc, a hidden row's spec filtered out, and the git needs' autocmds made once in config.

## Step 5: features/ (2026-10-18)

Built on `rearch/features` from `origin/main` baaae96 (steps 1 to 4b). Behaviour is unchanged. After each slice, a
dump of the sandbox's state (lazy's plugins and their resolved opts, global and buffer maps, autocmds, commands,
`keys.list()` rows, `keys.menu`, options, highlights, `vim.diagnostic.config()`, `vim.g`, namespaces) was compared
with main's. It is a scratch check run as a suite `work/` check, so it is not in the branch. The differences that
remain are listed under "What changed".

**Built.**

- `lua/features/`: one module per feature: editing, search, git, completion, folds, diagnostics, treesitter, windows,
  files, lua_dev, lsp_status, profiling.
- `lua/lsp/`: `init.lua` (was `core/lsp_servers.lua`), `buffer.lua` (was `core/lsp.lua`, now only what servers give
  a buffer) and `pyrefly.lua`.
- `lua/textobjects/`: was `config/textobjects.lua`.
- `lua/ui/`:
  - `theme.lua`: onedark and every override, and `palette()` for the statusline;
  - `icons.lua`;
  - `snacks.lua`: the picker and notifier options and patches;
  - `statusline.lua`;
  - `messages/`: was `config/ui2/`, moved as is.
- `lua/keys/languages.lua`.
- Language files now have a `keys` field. `lang/php.lua` is new and holds only php's labels.

Gone: `plugins/`, `config/autocmds.lua`, `keymaps.lua`, `helpers.lua`, `utils.lua`, `config/ui2/`,
`core/lsp.lua`, `core/lsp_servers.lua` and `after/ftplugin/`. Left: `config/options.lua` and `core/lazy.lua` (step 6).

**Decisions.**

- *A feature is `{ plugins = { lazy specs }, setup = fn }`,* as the proposal's card has it (`features/init.lua:4-13`).
  - `setup()` makes the feature's rows, needs, autocmds and options. It runs once, from `init.lua`, before
    `core.lazy`.
  - Anything that needs a plugin goes in that plugin's spec (`config` or `init`), or in a callback given to
    `require("features").at_very_lazy(fn)` (`features/init.lua:46-76`). The Snacks toggles are the main case: each
    owner declares its own (`features/windows.lua:47`).
  - Those callbacks run at `VeryLazy` after lazy's own listener, as main's snacks hook and `config.helpers` hook did,
    so the plugins that load at `VeryLazy` are loaded first: conform, diffview, flash, mini.icons, neoblocks,
    tiny-inline-diagnostic and which-key (the sandbox dump's `event` fields).
    - Listeners run in the order they were made (`:h autocmd-define`), and lazy makes its listener inside
      `lazy.setup` (`lazy/core/handler/event.lua:68`). `setup()` runs before that.
    - So `at_very_lazy` queues each callback, and `init.lua` calls `features.after_lazy()` after `core.lazy` to make
      the listeners.
    - The review's probe (`~/.cache/nvim-config/rearch/features-review/probes/verylazy.lua`, run at the end of `init.lua`) lists
      `lazy_handler_event`, then six `features.very_lazy` listeners. Main lists `lazy_handler_event`, then
      `SnacksUserAutocmds`, then `init.lua`'s helpers hook.
    - The first build made the listeners in `setup()` itself, so they ran before lazy's. Review found that.
  - Autocmds go in a `features.<name>` augroup. `lsp/init.lua` uses `lsp` and `lsp/buffer.lua` uses `lsp.buffer`.
    These replace main's `UserAutocmds`, `CursorLine`, `SnacksGitKeys`, `PRReviewKeys`, `UserTreesitter`,
    `core.lsp_servers` and `core.lsp.linked_editing`. The tmux TermOpen autocmd had no group on main and is now in
    `features.windows`.
  - Rejected:
    - Features declaring their rows at module level. `features.plugins()` requires every module to collect specs,
      so collecting would then also make keys.
    - A `keys` field per feature for a central loop. Rows that need a plugin, or need to be declared at
      `VeryLazy`, would still be made elsewhere, so the field would not be the only place.
- *Adapters bring their plugin's spec as a `plugins` field.* These are the modules that wrap a plugin:
  - `ui.theme`, `ui.icons`, `ui.snacks`, `ui.statusline`;
  - `lsp` (nvim-lspconfig);
  - `format.conform`, `linting.nvim_lint`;
  - `keys.which_key`.

  They have no `setup` in the features loop: the plugin's `config` calls theirs. `features/init.lua` lists them in
  `M.adapters`, and `features.plugins()` returns their specs first, then the features' specs. lazy merges a later
  fragment over an earlier one (`lazy/core/plugin.lua:441-453`), so diagnostics' trouble actions for the snacks
  picker merge over `ui/snacks.lua`'s opts, as they did when trouble's spec file sorted after snacks'.
- *Rows live with their owner:* in a feature's `setup()`, in a plugin's spec, in `lsp/buffer.lua`, or in a language
  file's `keys` (below).
  - The popup doesn't depend on the order rows are declared: which-key sorts by `local, order, group, alphanum, mod`,
    and `order` only applies to plugin items (`which-key/node.lua:134`).
  - A `<leader>` row still needs mapleader first (`config.options` before every row).
- *Setup order is the list order in `M.features`.* Nothing in it depends on another feature at setup, since a need is
  read when a key is used, not when it is declared (`keys/init.lua:15`). The FileType autocmds that two features make
  touch different things: editing's mail, prose and commentstring (`features/editing.lua:436-465`), and windows' `q`
  (`features/windows.lua:71`).
- *Autocmd order within an event changed in three places.* Each change is harmless; the dump sorts autocmds, so it
  can't show order, and the review's `order.lua` probe can.
  - FileType: main ran mail, then `q` close, then prose and commentstring, all from `config/autocmds.lua`. Now
    editing's three run before windows' `q`, and the `keys.language` listener follows them. They set different
    things.
  - BufReadPost: `features.git`'s file lookup now runs before `nvim.diagnostic.buf_load`. Neovim makes that listener
    when `vim.diagnostic` is first required, and on main `core/lsp.lua` required it first. The two don't share
    state.
  - Plugin-made listeners (ColorScheme's MiniIcons and the statusline groups; FileType's `lsp` and
    `features.treesitter`) follow the order lazy loads startup plugins. That is `pairs()` over its plugin table
    (`lazy/core/loader.lua:163`), and it varies from run to run on main too: three probe runs of main gave three
    ColorScheme orders.
- *`core/lazy.lua` gets one list:* `require("lazy").setup(require("features").plugins(), opts)`. Before, it imported
  `plugins/`.
  - This also removes step 3's re-run hazard. lazy reloads an imported spec module after an install or update
    (`package.loaded[modname] = nil`, `lazy/core/plugin.lua:184`), and a module that made state or autocmds made them
    twice. A table spec is parsed again without running any module code.
  - So snacks' config no longer looks up the buffers loaded before it. That lookup covered the re-run, and at
    startup no file is loaded yet: Neovim loads the windows' buffers after the user config
    (`runtime/doc/starting.txt:555-560`).
  - `checks/keys_spec_reload.lua` still passes, unedited.
  - lazy's `change_detection` would now start no timer, since it only watches imported modules
    (`lazy/manage/reloader.lua:18`, `#Config.spec.modules > 0`), so its setting is dropped from `core/lazy.lua`. On
    main it reloaded the spec when a file under `plugins/` changed. Now a spec edit takes `ZR` (`:restart`, which
    keeps the session), the safe choice anyway given the reload's re-run hazard. CONTRIBUTING says so.
  - For step 6, `features.plugins()` is the seam: an `app/` phase can hand the same list to lazy or to a vim.pack
    adapter (D45).
- *The module cache is enabled first* (`init.lua:1-3`, `vim.loader.enable()`).
  - lazy enables it in its setup (`lazy/init.lua:61-70`). On main every spec file loaded after that, byte-compiled.
    The feature modules now load before lazy's setup and were parsed from source each start: about 3 ms slower than
    main.
  - Enabling it earlier is idempotent, so lazy's own call returns early (`runtime/lua/vim/loader.lua:437-438`).
  - Rejected: requiring the features after `lazy.setup`. The specs have to be collected before it.
- *Language keys (D46).*
  - The runtime ftplugins' labels in `keys/neovim.lua` are now `keys` rows in `lang/go.lua`, `markdown.lua`,
    `php.lua`, `python.lua` and `rust.lua`. Each language's `keys.filetypes` limits its rows to the ftplugin's
    filetype.
  - `lang.views().keys` gives each filetype its rows, and variants get none (tested in `tests/unit/lang_test.lua`).
    `keys/languages.lua` passes them to `keys.language(ft)`.
  - php has no tools. Its language file exists only for these labels; the alternative was keeping a php table in
    `keys/neovim.lua`.
- *`after/ftplugin/lua.lua` and `vim.lua` are lua-dev's keys,* not language facts. They are now
  `keys.language("lua")` and `keys.language("vim")` rows in `features/lua_dev.lua`, with the same rhs, desc and
  `silent = false`.
  - Their buffer maps in a Lua buffer are identical in the dump. `keys_source_file`, `wk_ftplugin_labels` and
    `bufmaps` pass.
  - lua-dev's label-less `<leader>!` row, which only gave an icon, is dropped. The popup never showed the icon: the
    ftplugin map's own desc won both label and icon (`keys/init.lua:614-615`, and main's dump lists
    `menu n { label = "Execute current line", lhs = "<Space>!" }`).
- *textobjects asks `keys.which_key.presets()`* for which-key's preset labels (`keys/which_key.lua:109`), so
  `keys/which_key.lua` is again the only file that requires which-key.
- *ui/theme owns the colorscheme and every override.*
  - The overrides are in onedark's `highlights`, which onedark applies again on each load, `:colorscheme onedark`
    included (card 12).
  - The statusline's `Statusline*` groups stay in `ui/statusline.lua`, redefined on ColorScheme
    (`ui/statusline.lua:162`). They are the statusline's own groups, not overrides, and they read
    `ui.theme.palette()`.
  - `lsp/buffer.lua:143` makes `default = true` groups for each document colour. They are data, not theme.
- *Adjustments to the proposal's feature list.*
  - treesitter is a feature: it owns nvim-treesitter's spec, its parsers and its need.
  - The LSP keys and what servers give a buffer stay in `lsp/buffer.lua`, beside the server lifecycle, rather than
    in a feature.
  - pyrefly's type-error switch is `lsp/pyrefly.lua`. Its two callers are `lang/python.lua`'s `on_init` and the
    `<leader>Te` toggle.
  - search covers "search and jump". files covers writing, quitting, scratch buffers, renaming and the Ghostty check.
  - editing also has the todo-comments spec and the yank highlight.

**What didn't fit, kept as is.**

- *The text-object dispatch* stays a global expr map per key in `textobjects/`. A key row hides a key where its need
  fails, but a text-object key must stay listed with its own meaning there. The presses and the labels also judge
  "acts" at different precision.
- *textobjects has no `plugins` field.* It wraps `nvim-treesitter-textobjects.shared` when it loads
  (`textobjects/init.lua:161-162,256-257`), and collecting specs would load it before the plugin is on the
  runtimepath. The dependency stays in `features/treesitter.lua:59`.
- *The FileType `q` close* stays an autocmd in `features/windows.lua:72`, not language rows. The runtime's man
  ftplugin and checkhealth map `q` themselves (`runtime/ftplugin/man.vim:29`, `runtime/lua/vim/health.lua:474`), and
  the list includes non-language buffers (help, qf, lspinfo). `[Output]`'s `q` is a map on a scratch buffer in
  `ui/messages/messages.lua:149`.
- *Per-filetype options stay FileType autocmds in editing,* not language `options`.
  - Terraform's `commentstring` covers `terraform` and `hcl`, while `lang/terraform.lua` covers `terraform`,
    `terraform-vars` and `tf`, and no language has `hcl`.
  - The prose options cover gitcommit, oil, text, tex and NeogitCommitMessage, which have no language files.
  - The tsconfig and dotenv filetype rules stay in `config/options.lua` (step 6).
- *The `<leader>Te` toggle* stays in `lsp/buffer.lua`, not `lang/python.lua`. It is a Snacks toggle made at
  `VeryLazy`, which a language file's data can't hold.
- *Two unmapped helpers are kept:* `features.files.toggle_go_test()` and `features.git.copyFilePathAndLineNumber()`.
  They were unmapped on main too. Run them with `:lua`.

**What changed.**

- *lazy `init` flags:* which-key gained one, for its `<leader>?` row. origami, tmux-navigator and PR review lost
  theirs, since their options and rows moved to their features' `setup()`.
- *Augroups:* renamed as above.
  - snacks' single `VeryLazy` hook became one `features.very_lazy` listener per owner, still after lazy's.
  - `keys.language` gained the FileType autocmd for lua-dev's rows.
- *Autocmd order* within FileType and BufReadPost (above).
- *The runtimepath* no longer has `config/nvim/after`, since the directory is gone.

**Checks edited (call sites only).**

- `checks/showcmd_pending.lua`: `require("ui.messages.showcmd")`.
- `work/ui2-noice/ui2_noice.sh`: the module path.
- `tests/regress/refresh.lua`: reads `lua/features/treesitter.lua` for the parser list (infrastructure, not a check).

**Cost.** Startup in the regress sandbox, headless with no file (cwd the default fixture), `--startuptime`,
interleaved rounds of 9
(`~/.cache/nvim-config/rearch/features/bench/startup.sh`):

| Config | Pooled median | Rounds |
| --- | --- | --- |
| main | 95.1 ms | 3 × 9 |
| this branch | 83.8 ms | 3 × 9 |
| main with `vim.loader.enable()` added first | 83.6 ms | 3 × 9 |
| this branch before that line | 97.5 ms | 9 × 9, against main's 93.2 ms over 9 × 9 |

The branch matches main on equal footing, and the gain is the cache.

## Step 6a: app/ (2026-10-18)

Built on `rearch/app` from `origin/main` 2d1adef (step 5). Behaviour is unchanged; lazy.nvim stays until 6b. A dump of
the sandbox's state after VeryLazy (autocmds in their order per event, maps, commands, options, `vim.g`, lazy's
plugins, loaded modules), taken with main's config and with this branch's, differs only in the module names and the
autocmd order listed below. The dump groups autocmds by event and pattern, so order across patterns was read from the
code. The ColorScheme, LspAttach, VimResized and WinResized listeners that plugins make also came out in another order;
that order is lazy's startup load order, which comes from `pairs()` over its plugins (`lazy/core/loader.lua:163-172`)
and varies from run to run on main too ("Step 5"). The dump is a scratch script (`~/.cache/nvim-config/rearch/app/tmp/dump.lua`), not in the
branch.

**Built.**

- `init.lua` is `vim.loader.enable()`, then `require("app").start()`.
- `lua/app/init.lua`: `M.phases`, the six phases in order, and `M.start()`, which runs them. `M.times()` lists the
  phases that ran, in the order they ran, each with its milliseconds.
- `lua/app/lazy.lua`: was `core/lazy.lua`, now a `setup()` the plugins phase calls. 6b replaces it.
- `lua/options.lua`: was `config/options.lua`, now editor-wide options and the leaders only.
- `checks/app_phases.lua`: the phases are recorded once each, in order, each timed, and the deferred one waits for
  VeryLazy.

**Decisions.**

- *The proposal's six phases, in its order* (proposal Part 4, "Startup, in phases"):
  1. `options`: `options.lua`, then `ui2.enable()` and `ui.messages.setup()`;
  2. `registries`: `keys.neovim`, `keys.languages`, `lsp.buffer`, `features.setup()`;
  3. `tools`: `lang.setup()`, `tools.setup()`, `tools.ux.setup()`;
  4. `plugins`: `app.lazy.setup()`;
  5. `servers`: `lsp.setup()`;
  6. `deferred`, at `User VeryLazy`: the features' `at_very_lazy` callbacks.
  - A phase is `{ name, at?, run }` (`app/init.lua:6-9`). The list is data, so the check reads the order from
    `M.times()` and asserts it against the six names written out.
  - Main ran lang and tools first, then options, then the keys and features (`init.lua` at 2d1adef). Options first
    puts mapleader and ui2 before anything else, as the proposal has it. Nothing in lang or tools read an option or
    showed a message at setup: lang's problems are reported in `vim.schedule` (`lang/init.lua:371-373`).
  - Registries before tools moves three groups' listeners later within their events. Each pair is independent:
    - FileType: `lang`, `tools` and `tools.ux` now follow `format.plans`, `linting.plans` and `keys.language`, and
      the pattern listeners of `features.editing` (mail; gitcommit, markdown and the other prose types; terraform and
      hcl, `features/editing.lua:438-464`) and `features.windows` (help, qf and the other `q` types,
      `features/windows.lua:73`). lang sets buffer options only for lua (`lang/lua.lua:7`), which none of those
      patterns covers and the others don't read; tools starts mise queries, which call back later; tools.ux runs its
      check in `vim.schedule` (`tools/ux.lua:899-900`).
    - BufEnter: `tools.ux` now follows `features.editing`, which only removes `formatoptions` flags
      (`features/editing.lua:424-427`).
    - BufWipeout: `tools.ux` now follows `format.plans`, `linting.plans` and `features.git`. Each drops its own cache
      for the buffer.
  - Rejected: options, tools, registries, which kept main's order of those listeners. The proposal orders tools after
    the registries because the tool phase reads them, and nothing observed depends on the old order.
- *The servers phase calls `lsp.setup()`;* nvim-lspconfig's spec lost its `config` (`lsp/init.lua:302-309`). lazy
  loads the startup plugins inside `lazy.setup` (`Loader.startup()`, `lazy/init.lua:112`), so nvim-lspconfig's `lsp/*.lua` are on
  the runtimepath when phase 5 runs.
  - `lsp`'s FileType and VimLeavePre listeners are now made after every startup plugin's, not in the middle of
    lazy's load order, so they have a fixed place: last among the listeners made at startup. On main their place
    varied with that order. FileType's `lsp` still precedes `nvim.lsp.enable`, and VimLeavePre's `vim.lsp: exit handler`
    still runs first (the dump). `lsp` now follows `nvim.autoread`'s VimLeavePre listener
    (`runtime/lua/nvim/autoread.lua:167`), which stops autoread's watchers, not servers.
  - Two edge cases differ. If nvim-lspconfig is missing, each server now warns that nvim-lspconfig has no config for
    it (`lsp/init.lua:212`); on main lazy skipped the missing plugin's `config`, so servers silently didn't start.
    `:Lazy reload nvim-lspconfig` no longer runs `lsp.setup()` again.
- *The deferred phase is one listener.* It replaces the `features.very_lazy` group's one listener per callback.
  - `app.start()` makes it after the startup phases, so after lazy's own VeryLazy listener, as `features.after_lazy()`
    did. The plugins that load at VeryLazy are loaded before the callbacks run.
  - `features.very_lazy()` runs the callbacks in order, each in `xpcall`, so one that fails is reported and the rest
    still run, as with separate listeners (`features/init.lua:59-70`). `at_very_lazy(fn)` after the phase ran runs fn
    at once; before, a listener made after VeryLazy never ran. Nothing calls it that late today.
  - Its time counts from the event's first listener, which `app.start()` makes before any other, so it includes what
    lazy loads at VeryLazy. In 6b app loads those itself.
  - Rejected: keeping `after_lazy()`'s listeners and a deferred phase that only marks time. The phase would not run
    anything, and "ran once" would check a timestamp.
- *`vim.loader.enable()` stays first in `init.lua`,* before `require("app")`, so every module, app's included, loads
  byte-compiled. Step 5 measured why it must precede the requires: without it the features parse from source, 97.5 ms
  against 83.8 ms ("Step 5", Cost).
  - Rejected: calling it inside `app.start()`. `app/init.lua` would then parse from source on every start, and the
    call would sit after the first require.
- *`options.lua` holds editor-wide options only.*
  - `ui2.enable()` and `ui.messages.setup()` moved to the options phase. They are startup steps, not options, and
    the proposal puts ui2 in phase 1.
  - `vim.g.lazydev_enabled = true` moved to `features/lua_dev.lua`, which owns lazydev. It is also lazydev's default
    when unset (`lazydev/config.lua:25`).
  - The tsconfig rule (`["[jt]sconfig.*.json"] = "jsonc"`) is dropped. Neovim names those files jsonc itself
    (`runtime/lua/vim/filetype.lua:2847`, `['^[jt]sconfig.*%.json$'] = 'jsonc'`), and a user pattern is anchored the
    same way (`filetype.lua:3085`). `vim.filetype.match` gives jsonc for `tsconfig.base.json` and `jsconfig.json` on
    both main and this branch. The two patterns differ only on names with no dot before `json`.
  - The dotenv rules are gone; `.env` files get Neovim's own `env` filetype, with its syntax and ftplugin
    (`runtime/lua/vim/filetype.lua:495,1704,2785`). The user decided this once review found what the rules did:
    - No language file declares dotenv, and nothing in the config read the filetype (`grep -rn dotenv nvim/` on main
      finds only the rules).
    - The `.env.*` pattern (`["%.env%.[%w_.-]+"] = "dotenv"`) had no effect on main: `vim.filetype.match` gives `env`
      for `.env.local` there, the runtime's `^%.env%.` winning.
    - Now `.env`, `.env.local` and `foo.env` are all `env` (they were `dotenv`, `env` and `dotenv` on main). A file
      named just `env` gets no filetype (it was `dotenv`): the runtime has no rule for that name.
  - Rejected: keeping the rules in the tools phase, or a language-level `match` field in `lang.Spec` with a
    `lang/dotenv.lua`. dotenv has no tools, but `lang.of("dotenv")` would start answering, and the facts, `:Tools`,
    `:Status` and the format and lint modules read that answer. `views.filetypes` would also need an `extension`
    table, which changes the views the unit tier checks (`tests/unit/lang_test.lua:128`).
- *`app.start()` runs once per session.* Re-sourcing `init.lua` does nothing; restart with `ZR` (`:restart`)
  instead. A second run would make every phase's state, autocmds and plugin setups again, and lazy would notify that
  re-sourcing is not supported (`lazy/init.lua:41-47`).
- *Timing is on all the time.* Each phase costs two `vim.uv.hrtime()` calls and one table insert. Warm, in the regress
  sandbox, headless, from the default fixture, six runs: options 0.3 ms, registries 13 ms, tools 4 ms, plugins 45 ms,
  servers 8 ms, deferred 17 to 23 ms (after the first warm-up run). Read them with `:lua =require("app").times()`.

**Checks.** `checks/app_phases.lua` is new. It reads the timing record: each phase is recorded once, in order, each
with a time; firing VeryLazy again records nothing; and a headless nvim with no harness (which never gets VeryLazy) has
recorded the five startup phases and not the deferred one. A phase whose run() is called twice but recorded once would
pass: the check reads the record, not the calls. Five sibling wrong versions of `app/init.lua` each fail it:
`times()` returning nothing, registries and tools swapped, the deferred phase run inline, its listener without
`once`, and a phase recorded twice (`~/.cache/nvim-config/rearch/app/wrong/run.sh`). No existing check was edited.

**Cost.** Startup in the regress sandbox, headless, no file, cwd the default fixture, `--startuptime`, 5 interleaved
rounds of 3 runs per side (`~/.cache/nvim-config/rearch/app/bench/startup.sh`). One-off class, one call per felt
moment. The question was whether 6a moves startup by 3 ms or more, or past ~100 ms.

| Config | Pooled median | Rounds faster |
| --- | --- | --- |
| main | 78.3 ms | |
| this branch | 77.8 ms | 3 of 5 |

The rounds disagree on the direction (-3.7 to +7.8 ms per round), so there is no real difference, and both are under
the budget.

## Step 6b: vim.pack (2026-10-18)

Built on `rearch/vimpack`, stacked on `rearch/app` (6a). vim.pack replaces lazy.nvim (D45): `lua/app/plugins.lua`
installs every module's plugins with `vim.pack.add` and loads each in its phase. A dump of the sandbox's state after
VeryLazy, taken with 6a's config and with this branch's on the same plugin revisions (the 6a dump script, its lazy
lines swapped for `app.plugins.list()`; `~/.cache/nvim-config/rearch/vimpack6b/tmp/dump.lua`), differs in the ways
listed under Decisions; nothing else.

**Built.**

- `lua/app/plugins.lua`: the plugin shape (`app.Plugin`), `setup()` for the plugins phase, `load()`, `load_phase()`,
  `list()`, `command()` and a package loader.
- `lua/app/init.lua`: two evented phases, `buffer` and `deferred`, and `User VeryLazy`, which `app.start()` now fires
  itself. `lua/app/lazy.lua` is gone.
- `nvim/nvim-pack-lock.json` pins the 24 plugins at the commits `nvim/lazy-lock.json` had; `lazy-lock.json` is gone.
- Every spec is in the new shape. Spec `keys` with an action are key rows (flash in `features/search.lua`, trouble in
  `features/diagnostics.lua`), and trouble's picker actions reach snacks through `require("ui.snacks").extend()`.
- `<leader>sp` lists the config's plugin spec lines, as `Snacks.picker.lazy()` listed lazy's
  (`snacks/picker/source/lazy.lua`).
- The suite: `refresh.lua`'s first step is `plugins`; `startup.lua` reads `:checkhealth vim.pack`; the fresh checks
  seed `site/pack/core/opt`; `keys_spec_reload.lua` is gone (nothing runs a spec module again). New:
  `app_on_demand.lua` and `app_require_loads.lua`; `app_phases.lua` covers the buffer phase.
- The test image's plugins stage runs the `plugins` step; lua5.1 and luarocks, there for `:checkhealth lazy`, are gone.

**Decisions.**

- *The plugin shape is this config's own, small:* `{ src, name?, version?, phase?, cmd?, init?, setup?, build?, dev? }`
  (`app/plugins.lua:13-23`). `src` is `owner/repo` on GitHub or a URL, `version` is vim.pack's (`:h vim.pack.Spec`),
  `setup` is a plain function and `build(path)` runs on install and update.
  - Rejected: porting lazy's spec language (`opts`, `config`, `dependencies`, `priority`, `event`, `ft`, `keys`).
    Each is a second way to say what the phases, the list order, the key rows and plain setup calls already say.
  - Rejected: keeping `opts` functions and fragment merging. The one fragment merge, trouble's actions into snacks'
    picker, is an explicit `ui.snacks.extend()` (`ui/snacks.lua`), called in the registries phase, before snacks
    loads.
  - Rejected: a trigger per plugin (event, filetype, key). The phases plus the loader below cover every plugin;
    commands are the one trigger kept (`cmd`, below).
- *Four phases.* The plugins phase loads the startup plugins; `buffer` loads at the first `BufReadPre` or
  `BufNewFile`; `deferred` at `User VeryLazy`, after the first screen; `on_demand` plugins at their commands. Each
  phase loads its plugins in list order, adapters first (`features/init.lua` `M.adapters`), which replaces lazy's
  `priority` and `dependencies`.
  - Startup: onedark, snacks, nvim-lspconfig, plenary, todo-comments, gitsigns, friendly-snippets, blink.cmp,
    nvim-treesitter-textobjects, nvim-treesitter. They were lazy's non-lazy plugins.
  - Buffer: nvim-lint and nvim-origami. lazy loaded origami at `BufReadPre` or `BufWinEnter`, so with no file it was
    loaded at the first screen; now a session that reads no file never loads it. Its maps (`h`, `l`, `^`, `$`) and
    fold options arrive with the first file (the dump with a file matches; with none, they are absent).
  - Deferred, the default: mini.icons, neoblocks (startup since D78), conform, which-key, flash, diffview,
    tiny-inline-diagnostic, trouble, nvim-autopairs, lazydev, vim-tmux-navigator. lazy loaded autopairs at InsertEnter, lazydev at
    `FileType lua`, and trouble, diffview and tmux-navigator at their commands or keys; now they load after the first
    screen. Loading them earlier only makes their listeners earlier: autopairs' `<CR>` map and buffer listeners,
    trouble's window and colorscheme listeners, lazydev's LspAttach listener (which acts on lua_ls only) and
    tmux-navigator's commands (the dump).
  - On demand: github-pr-reviewer, at `:PRReviewMenu` or `:PRSuggestChange`, the two commands the `<leader>p` rows
    run. Its setup maps `<C-h>`, `<C-l>` and `<C-e>` globally, falling back to Neovim's own keys outside review mode
    (`github-pr-reviewer/init.lua:1397-1424`, called at `:5023`), which would replace the window keys
    (`features/windows.lua:18-21`). `app.plugins.command()` defines each command until the plugin loads; the first
    use loads it and runs the plugin's own command with the same range, bang, arguments and modifiers.
  - A deferred plugin's command would not exist before VeryLazy, so `nvim +DiffviewOpen` or `nvim +Trouble` would
    fail with E492 where lazy's stubs ran it. trouble (`cmd = { "Trouble" }`) and diffview
    (`cmd = { "DiffviewOpen", "DiffviewFileHistory" }`) get the same stubs, which load the plugin first when used
    before VeryLazy; at VeryLazy the plugins' own commands replace them (`trouble/config/init.lua:242`,
    `diffview/plugin/diffview.lua:23,27`). Coordinator decision D67, from review.
- *A module of a plugin not loaded yet loads it* (`app/plugins.lua`, the loader, last in `package.loaders`), as
  lazy loaded a plugin on require. This covers the four cross-plugin requires before VeryLazy: snacks to which-key and
  conform, blink to lazydev (`lazydev.integrations.blink`) and the picker to trouble (`trouble.sources.snacks`), and
  any row whose action requires its plugin. At startup nothing goes through it: a headless start with a file has
  loaded only the startup and buffer plugins.
- *The startup plugins' `plugin/` files run after `init.lua`.* During init `load()` uses `:packadd!`, which only adds
  the directory to the runtimepath (`:h :packadd`, `vimscript.txt:90-122`); Neovim's load-plugins step, after
  `init.lua`, sources them (`:h load-plugins`). A plain `:packadd` would source them then and again in that step.
  After init, `:packadd` sources them before `setup` runs. So a startup plugin's `setup` runs before its `plugin/`
  file: gitsigns' calls `setup()` with no options, which keeps the config's (it does not rebuild the config);
  blink's sets the `'*'` capabilities after `lsp.setup()` (`lsp_capabilities.lua` passes).
- *The runtimepath and packpath lazy set are kept* (`lazy/core/config.lua:295-313`): the config, `site`, the runtime,
  its `lib` and the config's `after/`. `/usr/share/nvim/site` (from `$XDG_DATA_DIRS`) stays off, as it holds
  ghostty's ftdetect and syntax files.
  - lazy's `disabled_plugins` become the runtime plugins' own guards: `g:loaded_gzip`, `g:loaded_tarPlugin`,
    `g:loaded_tutor_mode_plugin` and `g:loaded_zipPlugin` (`gzip.vim:10`, `tarPlugin.vim:15`, `tutor.vim:7`,
    `zipPlugin.vim:24`). Nightly's zip plugin is `zip.lua`, with another guard; lazy left it loaded too.
  - With Neovim's own load-plugins step, `plugin/*.vim` files run before `plugin/*.lua` ones, so the runtime's
    `dir.lua` now runs after netrw and clears netrw's `FileExplorer` group (`plugin/dir.lua:54`), as in
    `nvim --clean`. A directory now opens in Neovim's directory buffer (`nvim.dir`), not netrw. lazy sourced `dir.lua`
    first, so netrw kept its group. The user accepted `nvim.dir` in place of netrw (D66).
  - Filetype detection is now set up after the startup plugins, so on `BufReadPost` and `BufNewFile` gitsigns'
    attach listener runs before `filetypedetect` (the dump). gitsigns attaches asynchronously; `gitsigns.lua` passes.
- *The lockfile is vim.pack's,* committed. On the first `vim.pack` call it installs every plugin in the lockfile that
  the disk lacks, at the lockfile's revision (`runtime/lua/vim/pack.lua:1026-1122`, and `:882-883` for "Prefer
  revision from the lockfile"). It was written from `lazy-lock.json` in vim.pack's format and checked by the refresh:
  every plugin vim.pack installed is at the lockfile's revision ("plugins: 24 at the lockfile"), and a start leaves the
  file unchanged (its mtime after a start is the copy's).
  - `confirm = false`: the first start installs without asking, as lazy's `install.missing` did. The first start
    therefore clones the 24 plugins; with lazy it cloned lazy.nvim and then them.
  - A config that ran on lazy keeps its old checkouts in `~/.local/share/<appname>/lazy`; nothing reads or deletes
    them (README, Install). vim.pack's are in `site/pack/core/opt`.
  - Updates: `:packupdate` shows the changes in a buffer, `:write` applies them; `:packupdate ++lockfile` restores
    the lockfile's revisions (`:h :packupdate`). lazy's checker (it fetched in the background, with `notify = false`)
    has no counterpart; nothing checks for updates on its own.
- *nvim-treesitter's build is a `PackChanged` hook,* made before `vim.pack.add` so the first install's event reaches
  it (`:h vim.pack-events`). A build waits until its plugin has loaded. It runs `update()`, as `:TSUpdate` did, and
  first points each parser's query link in `site/queries` at this checkout: `update()` leaves a parser whose revision
  is unchanged alone (`nvim-treesitter/install.lua` `needs_update`), so the links would keep pointing into lazy's old
  checkout.
- *neoblocks' dev checkout* is `dev = true`: with `$NVIM_PLUGIN_DEV` naming a directory that holds
  `neoblocks.nvim`, that directory is prepended to the runtimepath instead of vim.pack's copy (vim.pack copies a
  local source rather than linking it, D45).
- *A plugin that fails to install stops nothing else.* `vim.pack.add` adds every plugin that is on disk, then raises
  if any install failed (`runtime/lua/vim/pack.lua:1217-1234`). Uncaught, that ended `init.lua` after the tools
  phase: no plugins, no servers (found in review). Now:
  - `app.plugins.setup()` catches it, reports it through `vim.notify` and goes on;
  - `load()` skips a plugin that is not on disk, so `list()` reports it not loaded and its setup never runs;
  - vim.pack drops the failed plugin from the lockfile and writes it before raising (`pack.lua:899-902`,
    `:1211-1213`), so each pin the file had before is put back, and the next start installs the plugin at its
    revision. vim.pack keeps the lockfile in memory (`pack.lua:1125-1127`) and its next write in the same session,
    such as `:packupdate`, drops the restored pins again; it has no way to reload it, so the notification says to
    restart Neovim before `:packupdate` (found in re-review);
  - `app.start()` runs each phase in `xpcall`: a phase that raises is reported, and the later phases still run.
  This is what users hit when a clone fails on the first start after this change, or on a new machine offline.
- *Plugin hooks report their errors* as `<name>: setup failed:` (also `init`, `build`), through `vim.notify`, and the
  rest still load. The fresh checks look for that text where they looked for lazy's "Failed to run".
- *An evented phase runs once across its events.* `once` holds per event, so `buffer` (two events) would run at a
  `BufReadPre` and again at a later `BufNewFile`; `app.start()` keeps a set of the phases that ran
  (`app_phases.lua` caught it).

**Checks.**

- `app_phases.lua`: the buffer phase is recorded once, after the others, at the first file read; a file given at
  launch records it after the startup phases.
- `app_on_demand.lua`: github-pr-reviewer is not loaded after VeryLazy and none of its global maps exist; the first
  `:2,3PRSuggestChange` loads it and runs its own command with the range 2,3. In a headless nvim that never gets
  VeryLazy, `:Trouble qflist open` opens the quickfix list in trouble: the stub passed the arguments on.
- `app_require_loads.lua`: before VeryLazy, each of the four cross-plugin requires loads its plugin and returns the
  module asked for, with the member its caller uses and its type (`new` for lazydev's blink source, the `actions`
  table for trouble's snacks source; trouble's top module answers any key with a function, `trouble/api.lua:196-202`).
- `app_install_fails.lua`: on a data dir without gitsigns and with gitsigns' source unreachable (the lockfile's and the
  spec's), every phase runs, every other plugin loads, the servers are enabled, the failure is reported naming the
  plugin, and the lockfile keeps gitsigns' pin. Its config copy also makes the options phase raise, and that error is
  reported while every later phase still runs. Against the code before the fix it failed: phases
  `options,registries,tools`, 0 servers, the pin gone. It can't tell restoring only the dropped pins from writing the
  whole old file back: that would also drop a plugin first installed in the same failed start, a case the check doesn't
  build (it needs a second source).
- Sibling wrong versions of `app/`, each with one bug, fail their check: the stub command dropping the arguments or
  the range, no stubs, on-demand plugins loaded at VeryLazy, no loader, a loader returning the top module, the buffer
  phase run twice, `vim.pack.add` uncaught, no pin restore, `load()` without the disk check, phases run without
  `xpcall`
  (`~/.cache/nvim-config/rearch/vimpack6b/wrong/run.sh`, results in `result.txt` there).
- `startup.lua` checks every plugin the config names is installed and `:checkhealth vim.pack` has no ERROR or
  WARNING; `trouble_maps.lua` loads trouble through `app.plugins.load()`. Neither changed what it asserts beyond the
  manager it reads.
- The language-tools skill's audit (`scripts/tool-audit.lua`) and eval probe no longer call `require("lazy")`; the
  plugins they need load through the loader (`AUDIT OK`, `PROBE DONE` by hand). Its references name
  `site/pack/core/opt`.
- `work/keys/keys_global_regress.lua` (not in the plain suite) lost its lazy parts: lazy's keys are key rows now
  (`keys_map_desc.lua`), and `app_on_demand.lua` covers the PR commands.

**Network.** `suite.sh --refresh-only` with `NVR_REFRESH_STEPS="plugins resolve parsers"` ran once with network: it
cloned the 24 plugins from GitHub into the suite's `data/`, downloaded blink's prebuilt library (v1.10.2) and deleted
lazy's checkouts there. The fresh checks clone from GitHub as before.

**Cost.** One-off class, one call per felt moment. The question was whether 6b moves startup by 3 ms or more, or past
~100 ms. `--startuptime`'s last line, 5 interleaved rounds of 3 runs per side, cwd the default fixture. Before is 6a's
config on lazy.nvim, on a data dir with the same plugin revisions under `lazy/` (and lazy.nvim at the old lockfile's
306a055); branch is this branch (`~/.cache/nvim-config/rearch/vimpack6b/bench/startup.sh`, `startup-tui.sh`).

| Run | Before | Branch | Rounds branch faster |
| --- | --- | --- | --- |
| headless, no file | 85.5 ms | 80.4 ms | 4 of 5 |
| headless, `main.lua` | 119.5 ms | 106.3 ms | 5 of 5 |
| Ghostty TUI, no file (niri-screen-lab), quit 300 ms after VeryLazy | 93.6 ms | 85.6 ms | 5 of 5 |

The TUI and the file runs are faster in every round (by 6 to 15 ms); the headless no-file run is not, by D61's rule.
No run is slower, and the TUI start, the real one, is under the ~100 ms budget on both sides.
Where the time went was not measured.

## D73: the per-language tool tables are generated (2026-10-18)

**Context.** Which servers, formatters and linters each language gets was kept by hand in two tables in
`docs/mise-tooling-decisions.md`, a dated decisions record: "Per-language tools" and the file-scoped (sub-filetype)
table (`git show ee67afa:docs/mise-tooling-decisions.md`, lines 111-116 and 157-177). Since step 1, `nvim/lua/lang/` is
the one source of what applies where, so the tables could only repeat it, and they drifted: the file-scoped table
listed 4 sub-filetypes, while the language files declare 9 variants (the rows of "File-scoped tools (variants)" in
`docs/languages.md`). Agents missed those rows too: skill-eval runs without the language-tools skill missed the
decisions-doc rows every time (`docs/language-tools-skill-decisions.md:33-35`).

**Decision.** `docs/languages.md` is generated from `require("lang")` (its filetypes, `of(ft)` and `views()`) and the
tool catalog, and replaces both tables:

- `docs/languages.lua` renders it: one row per language and group of filetypes with the same tools (servers,
  formatters in run order, linters with the server that covers each), one row per variant with the files that get it
  and only the tools its base lacks, and one row per binary with its mise spec or rustup component, project dirs,
  runtime and languages. Every list is sorted or in run order, so the output is deterministic. Its header says it is
  generated and to run `mise run docs`.
- `mise run docs` (`mise-tasks/docs`) rewrites it with `nvim --clean --headless -l docs/languages.lua`: no plugins,
  as the unit tier loads `lang`.
- `tests/unit/languages_doc_test.lua` fails while the committed file differs from the render, naming the first
  differing line and saying to run `mise run docs`. It also checks the render names every filetype and every server,
  formatter and linter a language uses, and, on a fixture language, a covered linter's server and a variant's own
  files and tools. CI runs the unit tier (`.github/workflows/test.yml:58`), so a stale doc fails a pull request.
- The two tables in `docs/mise-tooling-decisions.md` became dated notes that point at `docs/languages.md` and keep
  what the per-language table recorded as changes from Mason. Its "Install specs" table stays: its Verified column is
  evidence from the install runs, which the code can't give.
- The language-tools skill says to run `mise run docs` where it said to edit the rows; its `check.sh` and the
  skill evals check the generated doc is current instead of looking for hand-edited rows.

**Rejected.**

- Keep the tables by hand, with a test that compares them with `lang`: the rows were free text (bold and struck
  marks, "replaces", notes), which a test can only parse loosely, and agents would still have to write them.
- The generator in `nvim/lua/`: `lang/init.lua` loads every file in `lang/` as a language (`nvim/lua/lang/init.lua:402`),
  and nothing at run time needs it. It sits beside the file it writes instead.
- Show the tables only in Neovim (`:Tools`): they are read on GitHub and by agents that don't start the editor.

## D72: linting skips a BufEnter that can't find anything new (2026-10-18)

**Context.** `linting/` linted on every BufEnter, BufWritePost and InsertLeave (`linting/init.lua:175` on ee67afa),
so switching buffers started every linter again with nothing changed: slow ones (golangci-lint, tflint) cost CPU, and
their diagnostics could flicker. The proposal left this open (Part 9; Step 2 above). A reload from disk fires
BufReadPre, BufRead, BufReadPost, FileType and FileChangedShellPost, and no BufEnter, while `b:changedtick` goes up
(a `:checktime` probe on nightly 0.13.0-dev-1868 with `--clean`,
`~/.cache/nvim-config/lint-skip/probe/reload-events.lua`), so main did not lint a reloaded buffer until its next
BufEnter (`checks/lint_bufenter_skip.lua`'s reload case fails on main).

**Decision.** The user approved the first point up front, and the reload, FileType and LspDetach points after seeing
them (D74); FocusGained and ShellCmdPost close the gap a `git checkout` left (D75):

- BufEnter lints only when the buffer's `b:changedtick` moved, or any buffer was written, since its last lint. A
  linter that reads a whole package or module (golangci-lint, tflint) can find new things in `b.go` when `a.go` is
  written. A first entry always lints, and BufWritePost always lints (`linting/init.lua:187-204`).
- InsertLeave gets the same skip. Leaving insert mode without typing changes neither the buffer nor any file, so a
  lint then sees what the last one saw; after typing, the changedtick moved and it lints.
- A reload from disk (`:checktime`, autoread) lints on FileChangedShellPost, and counts as a write for the other
  buffers: a file changed on disk, as with a write.
- Coming back to Neovim (FocusGained, "Nvim got focus", `:h FocusGained`) and a shell command (ShellCmdPost, "After
  executing a shell command with :!cmd, :make and :grep. Can be used to check for any changed files", `:h
  ShellCmdPost`) count as writes too (`linting/init.lua:194`): a checkout or a generator most likely ran there or
  then. Neither lints by itself; the next entry does.
- A buffer's state is dropped on BufWipeout, and when what runs on it changes, so its next entry lints: FileType (other
  linters) and LspDetach (a covered linter runs again).

`checks/lint_bufenter_skip.lua` observes runs of a probe linter: an unchanged buffer entered again does not lint;
an edit, another buffer's write or reload, regained focus, a shell command, a filetype change or its covering server
leaving makes the next entry lint; a write and a reload always lint; InsertLeave lints only after typing. Nine
sibling wrong versions, each one bug off this code, each fail it: no skip, a skip ignoring writes, one ignoring the
changedtick, reloads not linted, InsertLeave always linting, state kept over LspDetach, state kept over FileType,
FocusGained not counted, ShellCmdPost not counted
(`~/.cache/nvim-config/lint-skip/wrong/run.sh`, results in `result.txt` there). `lint_compound_ft.lua` did not catch
the FileType one: its enter lint comes from the ToolsChanged relint once `sh` resolves, so the new check resolves `sh`
first.

**Cost.** Per event (D61 class, ~100 ms budget), one per BufEnter or InsertLeave: a table lookup and
`nvim_buf_get_changedtick`, against a linter spawn it saves. Not benchmarked.

**Known limit.** A file that no buffer shows, changed while Neovim keeps focus and runs no shell command (a
background job, `vim.system`, a terminal buffer), counts as no write, so a package-wide linter's findings for an open,
unchanged buffer wait for its next change, a write, a reload, a shell command or regained focus; before, the next
BufEnter caught them.

**Rejected.** Linting on every BufEnter (before). A skip on the changedtick alone: it misses package-wide findings
after another file's write. Linting only on read, write and InsertLeave (the proposal's option): entering a buffer
after another file's write would show stale package findings.
## Server children at quit (2026-10-18)

**Context.** CI run 39121923853 (PR #52, docs only) failed `format_buffer` with `leaked: tflint(1652)`; main's earlier
runs passed. #37 (a498512) and #42 (7349326) made the VimLeavePre handler in `lsp/init.lua` terminate every server it
started and wait up to 0.5 s. The suspect was nvim-lint's tflint linter, which no quit handler kills. A sweep of 30
probe checks, each opening a `.tf` file and quitting 0 to 290 ms later, leaked 7 times in 90 runs, every time
`tflint --act-as-bundled-plugin` with parent 929 (the user manager reaping orphans). A tracker that recorded each
child's parent while the probe ran showed all 7 were the plugin of `tflint --langserver`, not of the linter's
`tflint --act-as-worker`. With the linter stubbed out it leaked 1 in 90, with the tflint server disabled 0 in 90.
Started by hand, tflint's server mostly handles SIGTERM, exits 0 and stops its plugin, but once in 5 runs
SIGTERMed 30 ms after initialize it died of the signal (exit -15) and its plugin ran on. So the #42 SIGTERM can land
while tflint starts its plugin, before it handles the signal. Linters don't outlive Neovim: a stand-in yamllint that
sleeps 10 s made the quit itself take 10.4 s, so Neovim's exit waits for a running linter. (Corrected: the regress
harness waited, not Neovim, and linters do outlive it; see "Linters at exit" below.)

**Decision.** Any server can exit without stopping its children, so the rule covers every server, not tflint, and
every way a server exits, not only the quit. Each server is the leader of its own process group: `vim.lsp.rpc.start`
runs it detached unless told otherwise (runtime `lua/vim/net/_transport.lua:47-50`), and its children are born in that
group. `lsp/init.lua` records each server's pid with the leader's start time and kills (SIGKILL) what is left of the
group twice over:
- when the client sees the server exit (its `on_exit` dispatcher, wrapped in `cmd`): a restart's, `:LspStop`'s or
  the quit's. vim.system reports the exit only once the server's pipes close (runtime `lua/vim/_core/system.lua:375-416`),
  so a child that holds them delays this until the quit;
- at the end of the quit handler, after the terminate and wait, for every group not swept yet, including servers
  vim.lsp's own handler already saw exit, which waits for a numeric `exit_timeout` (runtime `lua/vim/lsp.lua:1172-1196`).

A group id is reserved while any process is in it; once it is empty, a new process can get the id and lead a group
of its own. So a group is skipped when a process with the leader's pid runs with another start time
(`/proc/<pid>/stat`, field 22). The client doesn't expose the server's pid, so `rpc_start` watches the one
`vim.system` call `vim.lsp.rpc.start` makes and keeps the pid it returns; it warns once if that stops holding.

**Rejected.**
- *Kill nvim-lint's running linters on quit*: the leaked process was the server's child, and Neovim already waits for a
  running linter before it exits (above). (Corrected: it doesn't, and D95 kills them; see "Linters at exit" below.)
- *Kill only the leader*: the leader is gone already; the orphan is the problem.
- *Only at the quit, for servers still running when it began* (this branch's first version): a server vim.lsp's
  handler waited for is gone by then, and a restarted server's children run until the quit. Review reproduced the
  first with `exit_timeout = 1000`.
- *Only on the client's exit*: a child holding the server's pipes keeps that from ever firing.
- *SIGTERM to the group*: a child may ignore it; what is left is orphaned, so there is nothing to shut down gracefully.

**Known limits.** A child that leaves the group (its own `setsid`) escapes. Without procfs (not Linux) the start time
is unknown and no group is swept. Quitting while a slow linter runs waits for it; not changed here. (Corrected: the
quit doesn't wait; see "Linters at exit" below.)

**Checks.** `lsp_exit_children.lua`: stand-in ruff servers each start a `sleep 600` child that ignores SIGTERM. One
never answers initialize, one exits on shutdown, one has `exit_timeout = 1000`, one is restarted mid-check, and its
child must be gone once its old client is. On `origin/main`'s code every child leaked; with the fix it passes.
Sibling wrong versions each fail it, every one by a leak or the restart case: no sweep, killing only the leader's pid,
SIGTERM to the group, `on_exit` not wrapped, no sweep at the quit, sweeping at the quit only leaders still running
(`~/.cache/nvim-config/linter-leak/variants/run.sh`, results in `result.txt` there). The tflint probe sweep leaked 10
of 90 runs on `origin/main`'s `lsp/init.lua` and 0 of 90 with the fix
(`~/.cache/nvim-config/linter-leak/sweep-before-fix.out`, `sweep-after-fix.out`).

The reuse guard has its own unit test, `tests/unit/lsp_test.lua`, through `M._groups` and `M._sweep`: a detached
`sleep` stands in for a server, recorded with its start time as awk reads field 22 of `/proc/<pid>/stat`; the sweep
kills it, and leaves it running when the recorded start time is another. The check above passes either way, since none
of its pids is reused. Wrong versions each fail the unit test: the guard always true, the start time read from field
21, the sweep doing nothing (`~/.cache/nvim-config/linter-leak/variants/run-guard.sh`, results in `result-guard.txt`).

The suite now prints each leaked process's pid, parent pid, age and command line under the `leaked:` line and keeps
them as `LEAK` lines in `last/`, which CI uploads, so a leak names its process without a rerun; `selftest/leak.lua`
checks it.

## D78: messages and the command line come from neoblocks' messages module (2026-10-18)

**Context.** `nvim/lua/ui/messages/` gave ui2 noice's look: `:` in a popup, messages as snacks.notifier toasts, long
output in a split, a message history and the pending keys in the statusline (`docs/ui2-noice-parity-decisions.md`).
That code moved to neoblocks.nvim as its `messages` module, released in v0.3.0 (commit bb5831c, `git ls-remote
https://github.com/AH-Merii/neoblocks.nvim refs/tags/v0.3.0`). neoblocks records what the move changed in its
`docs/decisions/messages.md`; the behaviour is the one decided in the parity doc. The module hooks ui2 when
neoblocks is set up, and neoblocks loaded at `deferred` (step 6b), after the first screen, so it has to load earlier.

**Decision.** The user's call: neoblocks loads at startup, and the config's copy goes.

- The neoblocks spec gets `phase = "startup"`, and its one `require("neoblocks").setup()` gets
  `messages = { ui2 = require("app").ui2 }` (`lua/ui/statusline.lua:9,294`). snacks comes first in the same phase
  (`M.adapters` in `lua/features/init.lua:19`), so toasts work from the moment the module hooks ui2.
- The options phase keeps its `ui2.enable(M.ui2)` (`lua/app/init.lua:15,28`): it catches the messages before the
  plugins phase, and the module's `setup()` sees ui2 on and doesn't enable it again (neoblocks
  `lua/neoblocks/messages/init.lua:104`). When the options phase raises before that call (as
  `checks/app_install_fails.lua` makes it), the module enables ui2 itself, with its `ui2` option (`:104-105`), so
  both paths get the same targets from `M.ui2`. `require("ui.messages").setup()` and `nvim/lua/ui/messages/` are gone.
- The statusline's pending keys are `Neoblocks.messages.showcmd()` (`lua/ui/statusline.lua:282`). `<leader>n` opens
  `require("neoblocks").messages.history()`, and says neoblocks.nvim isn't loaded where it failed to install or load
  (`lua/ui/snacks.lua:164-170`; `checks/history_key_without_neoblocks.lua`). The statusline needs no such guard: it is
  neoblocks', so without neoblocks Neovim's default 'statusline' draws the pending keys through `%S`. The lock file
  pins neoblocks at bb5831c (from db1fced).
- 'showcmdloc' is the module's while its pending-keys part runs: "last" while the hook is in, "statusline" while it's
  switched off or the hook failed (neoblocks `lua/neoblocks/messages/showcmd.lua`, `place()`). `options.lua:54` keeps
  setting "statusline": it applies before neoblocks loads, and in a session where neoblocks isn't installed, whose
  default 'statusline' draws pending keys through `%-10S` only with "statusline" (Neovim's default is "last";
  `nvim --clean --headless` on v0.13.0-dev-1868 prints both).
- `tests/regress/checks/showcmd_pending.lua` is gone: neoblocks' `tests/messages_spec.lua` ("pending() leaves out a
  lone key whose command runs at once...", :677) has its 25 cases, fed through ui2's `msg_showcmd` with a UI attached,
  plus one for the 10-character cut. `checks/pending_keys.sh` still checks the keys in the config's statusline in a
  TUI. `work/ui2-noice/ui2_noice.sh` probes `neoblocks.messages.cmdline`.

**Where it differs from the old code, on purpose.**

- *Reports before the plugins phase's startup plugins.* The old hooks went in at the options phase, so an error or
  warning shown before snacks was set up was kept and replayed as a toast at VeryLazy, and listed in the history
  (old `ui/messages/messages.lua:321-323,388-394`). With the hooks in the plugins phase, the reports made before
  neoblocks loads only got ui2's msg window, which clears, and `:messages` (found in review): app's failed phase,
  vim.pack's failed install (`lua/app/plugins.lua:231`, which asks the user to restart before `:packupdate`), a
  plugin given twice (`:194`), a failed `init` or setup (`:50`), and lang's mistakes in a language file
  (`lua/lang/init.lua:374`). These now go through `require("app").report()` (`lua/app/init.lua:97`), which holds a
  report made while `start()` runs its phases and sends them once the phases are done (`:139-149`), when snacks is
  `vim.notify` and the module hooks ui2: each is a toast and in the history again. `vim.schedule`, which lang used,
  is not enough: vim.pack's install turns the event loop inside the plugins phase, so a scheduled report ran before
  neoblocks loaded. `checks/app_startup_reports.sh` checks all three kinds in a TUI with a failing install: it fails
  on the code before this (every assertion), and with lang's report scheduled (its two lang assertions). If snacks
  fails to load, a held report goes to Neovim's `vim.notify`, so to ui2 or the module as any message; if neoblocks
  fails, snacks still toasts it and keeps it in its own history (`:lua Snacks.notifier.show_history()`).
  `checks/app_install_fails.lua` reads the reports from snacks.notifier's history as well as `:messages`, since
  they now reach the notifier.
- *'showcmdloc'* is set by the module, not by the config (above); `:Neoblocks messages off` turns the whole module
  back into plain ui2, with Neovim's own `%S` for the pending keys (neoblocks decisions 6).
- *The pending-keys hook is guarded at run time* like the other two parts, and `:checkhealth neoblocks` says which
  parts are on (neoblocks decisions 1). The old `showcmd.lua` had no run-time guard.
- *The early replay* runs on the tick after UIEnter, where the old one ran at VeryLazy: the same moment here, since
  `app.start()` fires VeryLazy on that tick (`lua/app/init.lua`, the UIEnter autocmd).

**Cost.** One-off class (startup, ~100 ms budget, once per start). Measured before this change against its
prototype (`~/.cache/nvim-config/neoblocks-messages/startup/`, `bench.sh` and `bench-tui.sh`, `cfgA` today's main
and `cfgB` this change; 7 rounds of 3 runs per side, interleaved): headless `NVIM STARTED` 78.7 ms against 86.1 ms
pooled, +7.4 ms, slower in 7 of 7 rounds; the plugins phase +8.4 ms (`python3 stats.py headless.txt`). Real, and
under the budget headless.

In a real terminal (a Ghostty 1.3.1 window from niri-screen-lab, nightly v0.13.0-dev-1868, `NVIM STARTED` from
`--startuptime`, the regress sandbox's config and data, no file; 5 rounds of 3 runs per side, interleaved, load
average about 2.5; `~/.cache/nvim-config/neoblocks-messages/startup/ghostty/`): origin/main 95.2 ms against this
branch 103.8 ms pooled, +8.6 ms, slower in 4 of 5 rounds; 12 of this branch's 15 runs were over 100 ms, 4 of main's
15. Taken as real: the headless rounds agree 7 of 7 on the same direction and size, though these 4 of 5 alone fall
short of D61's round rule. Unfelt, and accepted (D93, the user, 2026-10-18): about 10 ms once per start "would be
almost impossible to detect", even though it takes the total past the nominal ~100 ms ("D61 amendment" below). A
first try, while another session's cargo build held the load average near 25, gave 250 to 870 ms per start on both
sides and was dropped.

**Rejected.**

- Keep neoblocks deferred and call the module's `setup()` at the options phase: neoblocks isn't on the runtimepath
  before vim.pack loads it in the plugins phase.
- Drop the config's `ui2.enable()` and pass the targets as the module's `ui2` option: the messages of the registries
  and tools phases would then not reach ui2 at all.
- Drop `vim.o.showcmdloc = "statusline"`: without neoblocks the pending keys would show nowhere ('cmdheight' is 0).

## D61 amendment: a one-off cost is judged by its delta (2026-10-18, D93)

**Context.** D61 says what counts as a performance regression: it must be real (every interleaved round agrees on the
direction, or 7 of 8) and felt, where felt is a keystroke crossing one 8.3 ms frame or startup going past ~100 ms
(`~/.cache/nvim-config/rearch/agent-common.md:45-47`, the rules every rearchitecture agent follows; D61 has no section
of its own here). D78 moved startup in a real terminal from 95.2 to 103.8 ms (its Cost above), so by the letter of
D61 a real ~10 ms delta became "felt" only because the total crossed the line.

**Decision (D93, the user).** Budgets aren't cliffs. For a one-off cost (startup, the first use of a feature), judge
the size of the delta, not whether the total crosses ~100 ms: about 10 ms "for something that runs once ... would be
almost impossible to detect". Scrutiny stays where a cost repeats inside one felt moment: per key, per scroll and per
line drawn, with D61's frame budget. D78's startup cost is accepted on this rule.

**Rejected.** Treating ~100 ms as a hard line for one-off costs: it would turn an undetectable delta into a regression
because of where the total happened to sit.

## Linters at exit (2026-10-18)

**Context.** Saving lints the buffer (`linting/init.lua:187`), so `:wq` starts the file's linters just before Neovim
exits. nvim-lint keeps one process per buffer and linter, spawned detached (nvim-lint `lua/lint.lua:91-108,405`), and
has no public cancel-all. "Server children at quit" above says a 10 s stand-in linter made a quit take 10.4 s, so
Neovim waits for a running linter. The first question was whether that wait is real and felt.

**Measurement.** `:wq` in the TUI under a private tmux server, timed from the Enter key to the nvim process exiting, in
the regress sandbox (nightly 0.13.0-dev-1868, origin/main 743a9f9). The config as is was timed against a baseline
whose linting adapter runs nothing. Each round ran 3 timings per arm, the arms interleaved and the first arm
alternating by round, for 5 rounds. Each run waited for VeryLazy, the file's servers attached and no linter running
for 1.5 s. `:wq` is a per-event action in D61's classes, with a ~100 ms budget. Raw data is in
`~/.cache/nvim-config/lint-quit/raw/rounds-base.txt` (`summary.txt` beside it), and the scripts are in
`~/.cache/nvim-config/lint-quit/scripts/`.

| file | what ran on the save | config (median ms) | baseline | rounds with config slower |
| --- | --- | --- | --- | --- |
| `app.py` | nothing: the ruff server covers ruff (`lang/python.lua:97`, `linting/init.lua:66-68`) | 70 | 72 | 3 of 5 |
| `app.py`, ruff server off | ruff | 100 | 90 | 3 of 5, 1 tie |
| `main.tf` in a 3-file module | nothing: tflint's server covers tflint (`lang/terraform.lua:11`), and the suite has no trivy | 136 | 140 | 1 of 5 |
| `main.tf`, tflint server off | tflint | 149 | 147 | 3 of 5 |
| `config.yaml` | yamllint 1.38.0, from the project's `.venv` | 70 | 70 | 3 of 5 |
| `config.yaml`, stand-in yamllint that ignores SIGTERM and sleeps 10 s | the stand-in | 72 | 66 | 3 of 5 |

No case is real by D61's rule, since in each one the rounds disagree on the direction. Every pooled difference is
10 ms or less, against the 100 ms budget. Even the stand-in, which still has about 10 s to run when the quit starts,
does not hold the quit. Neovim does not wait for processes started with `vim.uv.spawn`: a `nvim --clean` that spawns a
detached `sleep 10` reading its pipes exits in 11-12 ms, startup included (`raw/clean-exit.txt`). The TUI's embedded
server exits within 1 ms of the client (`raw/server-exit.txt`). golangci-lint and trivy were not timed, because the
suite has neither. The stand-in covers them too: a quit does not wait for any linter, however long it runs.

The 10.4 s that #55's section reports came from the regress harness. Before quitting, it waited up to 15 s for
nvim-lint's running linters, so that only real leaks remained (`tests/regress/harness.lua:272-278` on 743a9f9). A
probe check that wrote a buffer with the stand-in took 10.4 s in the suite, while its body ended 7 ms after the write
(`raw/harness-wait.txt`).

So nothing waits at the quit, and a linter still running then is orphaned and runs to its end. The stand-in was still
alive 3 s after each of its 15 quits, while the real ruff, tflint and yamllint runs had all gone by then (0 of 45). A
linter that runs for long (golangci-lint on a big package, say; unmeasured) keeps running after the quit and spends
CPU on output that nobody reads. This is the leak "Server children at quit" fixed for servers.

**Decision (D95, approved by the user).** Kill what is left of every linter run, for every linter, with what #55
built for servers: at VimLeavePre for the runs still going, and as each run's own process exits.

- *The process group.* nvim-lint spawns each linter detached, so the run's pid leads the group its children join.
  nvim-lint doesn't expose that pid, so `linting/nvim_lint.lua` watches the `vim.uv.spawn` calls its `try_lint` makes
  (nvim-lint's `uv` is `vim.loop`, the same table), as `lsp/init.lua` watches `vim.lsp.rpc.start`'s one `vim.system`
  call. Each run's group is recorded when it starts.
- *The kill and the pid-reuse guard.* Both move from `lsp/init.lua` to `tools.proc` (`groups()`: `add`, `forget`,
  `kill`, `kill_all`), shared by the servers and the linters, each with its own set. A kill sends SIGKILL to the
  group and forgets it, and skips a group whose leader's pid now runs with another start time.
- *When a run exits, its group goes too.* Nothing reads a child that outlives its run. This matters for the runs
  nvim-lint cancels for a newer one: it sends SIGINT, then SIGKILLs only the run's own pid 10 s later
  (`lint.lua:297-313`), so a child that ignores SIGINT lived on, past the quit. Review reproduced it
  (`~/.cache/nvim-config/lint-quit-review/scripts/cancel_orphan.sh`: the child `sleep 600` was alive after the quit,
  reparented to the user manager). A cancelled run whose process still runs at the quit is still recorded, so the
  quit kills it.
- *Nothing else kills a run.* Closing a window, unloading or deleting a buffer kills nothing: the buffer's findings
  still matter while Neovim runs, and nvim-lint already cancels a buffer's run when it lints that buffer again.

A daemon a linter starts survives its run if it leaves the group, as daemons started from Node do. core_d, the daemon
launcher prettierd 0.29.0 bundles, spawns its server with `detached: true` (`core_d/lib/launcher.js:42-43,69-70`
in the user's mise install), and Node makes such a child "the leader of a new process group and session"
(<https://nodejs.org/api/child_process.html#optionsdetached>). A `sleep` started that way by node 24.18.0 had its
own pgid and sid (`~/.cache/nvim-config/lint-quit/raw/node-detached.txt`). No linter in `lang/` starts a daemon.

**Rejected.**
- *Read nvim-lint's `running_procs_by_buf`* (a private local in `lint.lua:91-108`, reachable only through the debug
  library): it ties the config to nvim-lint's internals. It also drops a run as soon as nvim-lint cancels it, so the
  run opening the file started would be missed when the write starts another. `get_running()` gives only names.
- *Call nvim-lint's public `lint()` per linter instead of `try_lint`, keeping the returned procs*: the config would
  then redo `try_lint`'s per-buffer bookkeeping (cancelling the previous run of a linter in that buffer).
- *Kill on BufDelete, BufUnload or WinClosed*: it would cut short runs whose results are still wanted.
- *SIGTERM*: a linter may ignore it (the stand-in does), and its output goes nowhere.
- *Forget a run's group when its process exits* (this branch's first version): a cancelled run's children outlived
  the quit, as above.
- *Keep a run's group recorded while it has members* (`vim.uv.kill(-pid, 0)`), and kill it only at the quit: its
  children would run on, unread, until then.

**Known limits.** A child that leaves the group (its own `setsid`) escapes. A daemon that a linter starts inside the
group dies with the run, so it would start again on every lint. Without procfs the start time is unknown and no
group is killed. The watch stops working if nvim-lint stops spawning through `vim.loop.spawn`; `lint_quit_kill`
then fails.

**The harness's wait.** Before it quits, the regress harness waits up to 15 s for nvim-lint's runs
(`tests/regress/harness.lua:272-279`). It stays; its comment and `tests/regress/README.md` now give the reason.
Without it, the quit would kill the runs a check leaves going, so the suite's leak detection would catch a regression
of this fix in every check that lints. But an error a run reports late (a parser error in `:messages`, an ERROR
notification) would no longer reach the harness's MSG and NOTIFY lines, which it reads after the wait. The wait costs
nothing unless a run is still going. In a full `suite.sh -v` run on this branch, which prints every INFO line, none
says "linters still running at exit" (`grep -c` gives 0 in `~/.cache/nvim-config/lint-quit/full-suite-fix.log`).
`lint_quit_kill` drives its own nvim over a socket, so the wait can't hide an orphan there.

**Checks.** `lint_quit_kill.sh`: a stand-in yamllint ignores SIGTERM and SIGINT; on one buffer it sleeps in a child,
on another it reports a finding after 2 s.

- `:wq` with two runs going (the one opening the file started and the one the write started) exits within 5 s, and
  none of their processes is alive 3 s later.
- While Neovim runs, nothing but the quit kills a run: `:wq` that closes one window of three, `:bunload` and
  `:bdelete` each leave the buffer's newest run going, and the other buffer's lint, running at the `:wq`, still
  reports its finding.
- Two writes cancel two runs; once nvim-lint has SIGKILLed their own pids, the quit leaves none of their processes.

On main (c7db37e) the quit cases fail, with the runs' yamllint and sleep alive. Sibling wrong versions each fail
it: no kill; the kill on BufDelete instead of at the quit; the kill on WinClosed; the kill at the quit plus on
BufDelete; the kill at the quit plus on BufUnload; SIGTERM to the group; forgetting a run's group when it exits
(`~/.cache/nvim-config/lint-quit/variants/run.sh`, results in `result.txt` there). SIGKILL to the leader only at the
quit now passes: the leader's exit then kills its group. It is no longer a wrong version, so it isn't counted.
`tests/unit/linting_test.lua` checks that a raising nvim-lint call leaves `vim.uv.spawn` as it was; a version without
the `pcall` fails it (`variants/result-unit.txt`). `lsp_exit_children` and `tests/unit/lsp_test.lua` pass unchanged
after the move to `tools.proc`.
