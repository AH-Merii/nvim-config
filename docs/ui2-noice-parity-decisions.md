# ui2 with noice behaviour: decisions

Living record of the decisions for making Neovim's built-in ui2 behave like the old noice.nvim setup.
Built in the `nvimt` test slot (`~/Projects/nvim-config-t`, branch `nvimt/ui2`). Dates are when the decision
was made.

## Status

- Decided: every behaviour below (2026-10-12).
- Built (2026-10-12) in `nvim/lua/config/ui2/`. Full suite 40/40 PASS on nightly. The new tmux check
  `tests/regress/work/ui2-noice/ui2_noice.sh` passes, and fails when the hooks are off. One niri-screen-lab
  pass covered all six behaviours.
- Follow-ups (2026-10-12): routine errors time out; the split measures a typed command's output as a whole and
  other messages one at a time. The tmux check covers both.

## Context

- `nvimt/ui2` (07d2b9a) replaced noice with ui2. Its commit message lists what ui2 lacks: the cmdline popup
  (command_palette), long_message_to_split, noice's markdown overrides for LSP docs, and errors that aren't from a
  typed command vanishing after 4s.
- The old noice config used the presets `bottom_search`, `command_palette`, `long_message_to_split` and
  `lsp_doc_border`, plus `lsp.override` for markdown (`git show 07d2b9a~1:nvim/lua/plugins/noice.lua`).
- ui2's public options only choose a target per message kind (`cmd`, `msg`, `pager`) and window heights
  (runtime `lua/vim/_core/ui2.lua`, doc block at the top). The cmdline window is pinned to the bottom
  (`ui2.lua:88-92`, `relative = 'laststatus'`). So noice behaviour needs hooks on ui2 internals, e.g.
  `ui2/messages.lua:466` `msg_show` and `ui2/cmdline.lua:96` `cmdline_show`.

## Decisions (2026-10-12)

| Area | Decision | Rejected |
|---|---|---|
| `:` cmdline | noice command_palette popup: bordered float near the top-centre, title/icon per cmdline type, completion menu attached under it, lualine stays visible | vertically centred popup; keeping ui2's bottom line |
| `/` `?` search | stays at the bottom (noice bottom_search); search count stays in lualine | same popup as `:` |
| Messages | routed to snacks.notifier toasts, like noice (which sent them through `vim.notify` to snacks) | keeping ui2's bottom-right msg float |
| Errors | stay until dismissed, except routine search and navigation errors (E486, E384/E385, E42, E553, ...), which time out after snacks' 3s like noice (2026-10-12) | ui2's 4s timeout; every error timing out, as under noice |
| Long output | opens in a split (long_message_to_split). A typed command's output is measured as a whole; other messages one at a time, so a burst of short async messages stays toasts (2026-10-12) | truncated float / toast; measuring a whole batch of async messages |
| LSP docs | markdown rendering like noice's `lsp.override` (highlighted code blocks, concealed markup), only what 0.13 and blink lack natively | |
| History | a filterable picker over all messages, like `:Noice history`; `g<` keeps working | only the `g<` pager |
| Unchanged | LSP progress stays silent (lualine only); prompts and confirm dialogs keep ui2's dialog window | |

Constraints:

- ui2 is experimental and private (`vim._core`): hooks stay minimal, guarded (fall back to plain ui2 if an
  internal moved), and comment the runtime `path:line` they depend on.
- Known pitfalls from the first ui2 pass: requiring snacks' notifier in a fast event raised E5560; headless has no
  UI attached, so ui2 does nothing there; the regress harness reads snacks.notifier's history.

## Design (2026-10-12)

Runtime refs: `R` = nightly runtime (NVIM v0.13.0-dev-1808+g561857c4a8), `N` = noice.nvim's `lua/noice`,
`S` = snacks.nvim's `lua/snacks`, `B` = blink.cmp 1.10.2's `lua/blink/cmp`.

### How the hooks attach

- ui2 looks up each event's handler from its module tables every time (`R/lua/vim/_core/ui2.lua:159,238`), so
  assigning wrappers to `ui.cmd.cmdline_show`, `ui.cmd.cmdline_hide` and `ui.msg.msg_show` is enough.
- `ui.cmd` and `ui.msg` only exist with a UI attached (`ui2.lua:217-219,234-235`). Headless, nothing is
  installed, so the headless suite and harness see plain behaviour.
- ui2 reschedules fast events (`ui2.lua:242-243`), so the wrappers never run in a fast event. They can still run
  under textlock, so window work is scheduled.
- Guards: each module checks the internals it needs. On a missing internal or an error, it puts the original
  handler back and warns once, and that piece falls back to plain ui2.

### Modules

| File | Does |
|---|---|
| `ui/messages/init.lua` | Called from `options.lua` right after `ui2.enable()`. Returns early with no UI; runs each module's `setup(ui)` in pcall and warns if one fails or returns false |
| `ui/messages/cmdline.lua` | `:` and `input()` popup; `/` `?` at the bottom |
| `ui/messages/messages.lua` | Routes messages to toasts or the split; keeps a ring of every message |
| `ui/messages/history.lua` | `<leader>n` picker over the ring plus `vim.notify` history |
| `plugins/snacks.lua` | `notifier.keep` keeps errors; `<leader>n` history, `<leader>N` dismiss; removed the `vim._print` → `dd` override, which sent every `:lua =expr` to a debug toast |

### `:` popup (cmdline.lua)

- Mirrors noice's command_palette: row 3, centred, min width 60, rounded, titles and icons per type
  (`N/config/preset.lua:65-98`, `N/config/init.lua:24-31`). Titles: Cmdline, Lua, Help, Filter, Calculator, Input.
- Reuses ui2's own cmd window: ui2 still draws the text, highlighting and cursor; the wrapper only moves the window
  and resets ui2's `cmdheight` bump (`R/.../ui2/cmdline.lua:27-33`), so lualine keeps the last row.
- blink's menu sits under the popup through `vim.g.ui_cmdline_pos` (`B/config/completion/menu.lua:49-56`); no blink
  config change.
- Goes to the popup: `:`, `=` (nested `<C-r>=`), and every `input()` prompt (`hl_id == 0`).
  Stays plain ui2: `confirm()` and `:s///c` (they keep ui2's dialog), block mode, and Ex-mode variants.
- `/` and `?`: the cmd window moves to the last row over the statusline with `cmdheight` 0, like noice's
  bottom_search, so the layout doesn't shift (review fix F5).
- On hide, the window is closed and ui2's `check_targets()` recreates its default one.

### Messages (messages.lua)

- Wraps `ui.msg.msg_show` (`R/.../ui2/messages.lua:466`). Messages are batched per event-loop tick with
  `vim.schedule`.
- Left to ui2: `confirm`, `search_cmd`, `search_count`, `empty`, `wildlist`, dialog prompts, block mode, and
  anything before snacks is set up. Errors and warnings from before setup are replayed as toasts at VeryLazy.
- Dropped (still in `:messages`), as noice dropped them (`N/config/routes.lua:79-96`): `progress` (lualine shows it),
  `undo`, `quickfix`, `completion`, `verbose`, `shell_cmd`. `shell_ret` is kept: it's how a failed `:!cmd` shows.
- Toasts: errors and warnings get one toast each; errors use `timeout = 0`, so they stay until dismissed. Info
  messages merge into one toast that replaces the last. The title is the typed command, or noice's
  Error/Warning/Messages.
- Routine errors: the `routine` table in `messages.lua` lists the "nothing found or at the edge" codes: search
  (E486, E384/E385, E35, E348/E349), quickfix and location lists (E42, E553, E776, E380/E381), tags, include
  search, change list, marks, folds, `:next`/`:bnext` ends and `gf`, each with its `:h` source. A toast whose
  errors are all routine gets snacks' default 3s timeout (`S/notifier.lua:113`), which noice's notify view also
  used (no `timeout` in `N/config/views.lua:66-72`). It is passed as `routine = true`; `plugins/snacks.lua`'s
  `notifier.keep`, which holds every other error (including `vim.notify` ones), skips it.
- Split: when the rows a toast would need (counted the way snacks sizes it, `S/notifier.lua:513-517,588-603`) pass
  `min(20, 0.6*lines - 2)`, the message opens a non-entered `[Output]` split; `q` closes it. 20 is noice's
  `min_height` (`N/config/preset.lua:99-106`), a per-message filter (`N/message/filter.lua:98-100`).
- What is measured: the messages of one typed command (trigger `typed_cmd` with the cmdline closed, e.g. many
  `print()` lines from one `:lua`) count as one message, since ui2 delivers them as separate
  `msg_show` events. Every other message is measured on its own, so a burst of short async messages in one tick
  (22 nvim-treesitter "Downloading tree-sitter-X..." lines on first start) stays a toast, while one tall async
  message still splits. Only the tall ones go to the split; the rest of the batch stays toasts.
- Toasts use `history = false`, since snacks keys its history by id (`S/notifier.lua:404-406`); the ring is the history.

### LSP docs

No code. 0.13's `open_floating_preview` already sets markdown, conceal and treesitter
(`R/lua/vim/lsp/util.lua:1632-1637,1714-1718`). Fences, escapes, entities and links are concealed natively; blink
renders its own docs. Only noice's `<pre>` → fence conversion is missing; add a wrapper on
`vim.lsp.util.convert_input_to_markdown_lines` if a server ever shows raw `<pre>`.

### History

`<leader>n` opens a snacks picker (format `notification`) over `Snacks.notifier.get_history()` plus the
message ring, newest first, with a preview. `g<` and `:messages` keep ui2's pager.

### Known differences from noice

- `:lua `, `:help `, `!` and input prompts stay visible. Concealing more than the 1-char `firstc` misplaces the
  terminal cursor by the concealed width (measured), so it was rejected.
- blink's labels sit one cell right of the typed text.
- Long `:!` output shows only when the command finishes (batching), not streamed.
- Errors inside a typed command's output that goes to the split are not sticky toasts.
- `confirm()` and `:s///c` use ui2's bottom dialog, not noice's confirm popup.
- `:messages`/`g<` use ui2's pager float, not noice's split.
- Toast and split colours/icons need a Nerd Font; the history picker pads titles to 15 cells but doesn't cut them.
