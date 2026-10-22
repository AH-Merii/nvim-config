# Hover: decisions

Living record of the decisions for the LSP hover float (`K`): what the config does to it, and how it is rendered.
Dates are when the decision was made.

## Status

- Decided by the user (2026-10-22): D158 and D159, with the plugins below rejected.
- Built (2026-10-22) on branch `hover-rendering`. The four checks under "Tests" pass, and each fails on main's config
  or on a wrong implementation of the rule it checks.

## Context

Runtime refs: `R` = nightly runtime (NVIM v0.13.0-dev-1895+g0851e7dabe), `RM` = render-markdown.nvim at 8e87953,
`S` = snacks.nvim's `lua/snacks`.

- `K` calls `vim.lsp.buf.hover()` (`nvim/lua/lsp/buffer.lua:37`), which opens its float with
  `vim.lsp.util.open_floating_preview`: a scratch buffer, so `buftype=nofile` (`R/lua/vim/lsp/util.lua:1628`), given
  filetype markdown and treesitter (`util.lua:1717-1718`). The float is then shrunk by the code fence lines the
  highlighter conceals (`util.lua:1719-1726`). Signature help (`vim.lsp.buf.signature_help`, `<C-s>` in insert mode)
  opens the same kind of float (`R/lua/vim/lsp/buf.lua:516`).
- Diagnostic floats use the same function with `plaintext` (`R/lua/vim/diagnostic/_float.lua:252`), which sets no
  filetype, so neither problem below reached them. blink's documentation and signature windows have filetypes of
  their own (`blink-cmp-documentation`, `blink-cmp-signature`).
- Spell: the FileType autocmd for text filetypes in `features/editing.lua` turned spell on for markdown, so the
  hover underlined code and identifiers as misspelled. Seen in the sandbox: a hover float had `ft=markdown
  buftype=nofile spell=true`.
- Linting: `linting` lints a buffer on entering it when it changed since its last lint, and markdown names
  markdownlint-cli2 (`lua/lang/markdown.lua`), so focusing the hover (`K` again) linted it. Confirmed on main's config
  with the real markdownlint-cli2 (npm, run from a project's `node_modules`): after the second `K` it was spawned and
  the float got its findings, among them `MD041/first-line-heading` and `MD031/blanks-around-fences`. The plan for
  the float was `{ linters = { "markdownlint-cli2" }, run = { "markdownlint-cli2" } }`.
- Rendering: the ui2 decisions chose no code for LSP docs, since Neovim already conceals fences and markup
  (`docs/ui2-noice-parity-decisions.md`, "LSP docs"). D159 adds rendering on top of that.

## D158: spell and linting skip nofile buffers (2026-10-22)

**Decision.** A buffer with `buftype=nofile` gets no spell from the text-filetype autocmd and is never linted.
Exactly `nofile`, not any `buftype`: oil's buffers are `acwrite` and keep spell.

- Spell: the FileType autocmd returns before setting spell, spelllang and wrap in a nofile buffer
  (`features/editing.lua:451-466`).
- Linting: one predicate, `lintable(buf)` (`linting/init.lua:58-62`), checked in the local `lint()` that every lint
  goes through (`linting/init.lua:125-129`: entering a buffer, leaving insert mode, a write or reload, `<leader>ll` and
  ToolsChanged), and in the plan and the linter need (`linting/init.lua:67`, `:144-148`). So the statusline, `:Status`,
  `<leader>li` and `<leader>ll` name no linter in a float either.

**Why nofile.** Every float `open_floating_preview` opens is one (`util.lua:1628`), whatever opened it: hover,
signature help, a plugin's call. A nofile buffer is text no file holds, so a linter has nothing to check and a spell
mark nothing to fix.

**Rejected.**

- Any non-empty `buftype`: an oil buffer (`acwrite`) would lose spell (`checks/hover_spell.lua` fails with it).
- Guarding the BufEnter autocmd only: ToolsChanged and `<leader>ll` lint through other paths.
- Matching the hover's window variable (`lsp_floating_bufnr`, `util.lua`): a runtime detail, and only LSP floats.

**Cost.** One buffer option read per FileType of the text filetypes, per lint and per plan made (plans are cached per
buffer). Not measured: an option read is well under a microsecond.

## D159: render-markdown.nvim renders the LSP floats, and only them (2026-10-22)

**Decision.** [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) renders nofile
markdown buffers, which are the LSP floats, and never a markdown file you edit. It loads with the first such float.
`nvim/lua/features/hover.lua` owns it.

**Only nofile buffers.** Its `ignore` option "Takes buffer as input, if it returns true this plugin will not attach to
the buffer" (`RM/README.md:211-214`); the config's returns true for every buffer but a nofile one. A buffer it skips
gets no autocmds and no marks (`RM/lua/render-markdown/core/manager.lua:164-167`). Its defaults for nofile buffers stay:
every mode rendered and no signs (`overrides.buftype.nofile`, `RM/README.md:983-986`).

- The option is set in `vim.g.render_markdown_config` from the spec's `init`, before the plugin loads: its plugin file
  calls `setup()` with that variable and then attaches the current buffer (`RM/plugin/render-markdown.lua:6,10`,
  `manager.lua:20`). A `setup()` call from the spec's `setup`, which runs after the plugin file, came too late:
  loaded while a markdown file was current, the file was attached with the defaults and rendered
  (`checks/hover_render_file.lua` fails with that variant).
- Rejected: `enabled = false` with `overrides.buftype.nofile.enabled = true`. It still attaches every markdown file,
  so each gets render-markdown's cursor autocmds and has its conceal options reset on each update
  (`RM/lua/render-markdown/core/ui.lua`, `Updater:run`).

**Loaded on demand.** The spec has `phase = "on_demand"` and no command. A FileType autocmd for markdown requires
render-markdown in the first nofile buffer, which loads it through the plugin loader (`lua/app/plugins.lua`, the
package loader), then deletes itself. During a float's FileType the float is the current buffer and window (measured:
`curbuf` and `curwin` were the float's), so render-markdown attaches it as it loads; later floats it attaches from its
own FileType autocmd.

**Height.** render-markdown shrinks an LSP float itself, by the lines it conceals (`RM/lua/render-markdown/lib/
compat.lua:12-42`, `fix_lsp_window`), but doesn't count the virtual lines it adds: a table's borders, when no empty
line is there to draw them on, and wrapped table cells. A float whose markdown was only a 3-row table showed 2 of its 6
rendered rows. So after a float's first render (render-markdown's `on.render`), `fit()` sizes it to its rendered text
and places it again with `vim.lsp.util.make_floating_popup_options`, which bounds it by the room around the cursor as
Neovim did when it opened it (`util.lua:812-850`). Measured with the config (headless, 80x24, rendered rows against
the window's height):

| Float | Neovim's height | After render-markdown | Rendered rows |
| --- | --- | --- | --- |
| code block, separator, paragraph, list, code block | 16 | 14 | 14 |
| a table alone | 4 | 6 | 6 |
| a table between paragraphs | 12 | 11 | 11 |
| a table last, no empty line after it | 8 | 9 | 9 |
| a table whose padded columns are wider than the float | 3 | 7 | 7 |
| a long wrapped paragraph with links | 3 | 3 | 3 |

**Side effects, kept.**

- On first attaching, render-markdown turns off the two `conceal_lines` patterns of the markdown highlights query, for
  every buffer (`RM/lua/render-markdown/core/ts.lua:74-96`, `RM/lua/render-markdown/settings.lua:1605-1606`), and
  conceals the fences itself where it renders. `conceal_lines` needs `conceallevel` 2 or more
  (`R/doc/api.txt:3271-3276`), so a markdown file at the default 0 is unchanged; after the first hover, one with
  `<leader>Tm` on shows its fence lines again. Kept: with Neovim's fence concealing on as well, a code block's language
  line (drawn on the fence line) is hidden.
- snacks' markdown previews require render-markdown and call its `render()` themselves (`S/picker/util/markdown.lua:14,
  44-52`), which doesn't ask `ignore` (`RM/lua/render-markdown/api.lua:9-27`). So a picker preview of markdown (a
  `.md` file in the files picker, the notification history) is rendered too, and the first one loads the plugin. Kept:
  a preview is a nofile view like the hover, and snacks has no option to leave it out.

**Rejected plugins** (the options the user was shown, 2026-10-22):

- [markview.nvim](https://github.com/OXY2DEV/markview.nvim): another renderer of the same kind; one is enough.
- [hover.nvim](https://github.com/lewis6991/hover.nvim): hover from several sources, but it shows them in the same
  kind of float, so it fixes neither spell nor linting.
- [pretty_hover](https://github.com/Fildo7525/pretty_hover): reformats doc tags (`@param`, `\brief`), mostly for C and
  C++ servers.
- [lspsaga.nvim](https://github.com/nvimdev/lspsaga.nvim), [LspUI.nvim](https://github.com/jinzhongjia/LspUI.nvim):
  whole LSP UI suites, overlapping snacks' pickers and trouble.
- [nvim-docs-view](https://github.com/amrbashir/nvim-docs-view),
  [hoversplit.nvim](https://github.com/roobert/hoversplit.nvim): docs in a side panel, not a float.

**Cost.** Measured in the regress sandbox, headless, 5 rounds of 3 runs per side, the sides interleaved in each
round: A is the config without `features/hover.lua`, B with it. A fake server answers the hover at once, in a file no
other server attaches to; the time runs from `K` until the float is open (A) or holds render-markdown's marks (B),
polled every millisecond.

| Measure | A | B | Rounds B slower |
| --- | --- | --- | --- |
| startup, `--startuptime` total, no file | 82.3 ms | 81.4 ms | 2 of 5 (-2.4 to +1.9 ms) |
| first `K` of a session, warm byte-code cache | 66.8 ms | 88.0 ms | 5 of 5 (+19.4 to +23.6 ms) |
| first `K`, cold cache (fresh state dir) | 72.8 ms | 102.8 ms | 5 of 5 (+24.9 to +30.6 ms) |
| later `K`, warm cache | 29.1 ms | 28.1 ms | 2 of 5 (-2.2 to +2.0 ms) |
| later `K`, cold cache | 30.7 ms | 31.4 ms | 4 of 5 (-0.4 to +2.1 ms) |

Pooled medians. Startup is unchanged: nothing loads. The first float of a session costs about 21 ms more once
(30 ms with a cold cache); requiring the plugin is 2.2 to 2.5 ms of it with a warm cache (10 ms cold), and the rest is
its first render. Later floats cost nothing measurable, well under a frame.

## Tests

- `checks/hover_spell.lua`: a hover float has spell off; a markdown file and an oil buffer (`acwrite`) keep it.
- `checks/hover_lint.lua`: a fake markdownlint-cli2 in the fixture's `node_modules/.bin` lints a markdown file but not
  the hover float, opened or focused.
- `tests/unit/linting_test.lua`, "a nofile buffer is never linted": entering it, `linting.buffer` and ToolsChanged run
  nothing on it, and its plan and the linter need name none.
- `checks/hover_render.lua`: render-markdown isn't loaded at startup or by a markdown file; the first `K` loads it and
  renders the float; each float is as tall as its rendered text, a table's virtual border line included; markdown
  files stay unrendered.
- `checks/hover_render_file.lua`: loaded while a markdown file is current, as snacks' preview loads it, it leaves the
  file unrendered and renders an LSP float.

Each check fails on main's config. Sibling wrong versions, each with one change, fail the check named:
`setup()` from the spec instead of `init` (`hover_render_file`), no `ignore` (`hover_render`, `hover_render_file`), no
`fit()` (`hover_render`: height 13, text 14), `phase = "deferred"` (`hover_render`), spell skipped for any
non-empty `buftype` (`hover_spell`), and the linting guard in `lint()` only (the unit case).
