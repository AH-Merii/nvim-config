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
    ├── lint/           lint, what runs, nvim-lint adapter
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

