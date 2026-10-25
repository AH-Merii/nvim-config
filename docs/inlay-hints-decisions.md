# Inlay hints: decisions

Living record of the decisions for LSP inlay hints. Dates are when the decision was made.

## Status

- Decided by the user (2026-10-25): inlay hints on by default where a server has them (D162).
- Built (2026-10-25) on branch `inlay-hints`. `checks/lsp_inlay_hints.lua` passes, and fails on main's config.

## Context

Runtime refs: `R` = nightly runtime (NVIM v0.13.0-dev-1895+g0851e7dabe), `$VIMRUNTIME/lua/vim/lsp/`.

- Hints were off: nothing called `vim.lsp.inlay_hint.enable`, and only `<leader>Th` (`Snacks.toggle.inlay_hints`,
  `need = "inlayHint"`, `nvim/lua/lsp/buffer.lua:79`) turned them on in a buffer.
- `vim.lsp.inlay_hint.enable(true)` with no filter sets the global marker; a buffer falls back to it unless it has its
  own, and `enable(false, { bufnr })` sets one (`R/_capability.lua`, `M.is_enabled` and `M.enable`). Only clients
  that support `textDocument/inlayHint` are asked (`M.enable`, `supports_method`).
- Hints are requested on attach, on `BufWinEnter` and on every `didChange` (`R/inlay_hint.lua`, `InlayHint:new`,
  `on_attach`, `on_change`; `R/_capability.lua`, the `LspNotify` handler), one request for the whole buffer, the
  stale one cancelled.

## D162: inlay hints on in every buffer whose server has them (2026-10-25)

Decision:

- `vim.lsp.inlay_hint.enable(true)` once in `lsp/buffer.lua` (what a server gives a buffer), next to
  `vim.lsp.codelens.enable(true)`, as the code lens decision did (`docs/code-lens-decisions.md`). `<leader>Th` stays the
  per-buffer toggle; its label reads the buffer's state, so it says "Hide Inlay Hints" from the start.
- Which hints a server sends is its own setting, in its language file. Each enabled server, checked in the sandbox with
  the config's settings by asking it for hints on a small sample (`textDocument/inlayHint` over the whole buffer;
  a scratch check under `tests/regress/work/`, not kept), or by `lsp-init.lua`'s capability list for the servers the
  suite doesn't install:

  | Server | Hints with no setting of ours | Setting | Probe output (line:label) |
  |---|---|---|---|
  | lua_ls | parameter names | none: nvim-lspconfig sets `hint.enable = true` (`lsp/lua_ls.lua:90`; LuaLS's own default is false, `script/config/template.lua:388` in 3.19.1) | `2:a: 2:b:` |
  | tsc | parameter names (literals), parameter, variable, return types | none: nvim-lspconfig sets `js/ts.inlayHints` (`lsp/tsc.lua:72-80`) | `1:: number 2:: number 2:a: 2:b:` |
  | pyrefly | inferred variable and return types; parameter names off (pyrefly's IDE docs, `analysis.inlayHints`) | `python.analysis.inlayHints.callArgumentNames = "all"` (`lang/python.lua:40`) | before `1: -> int 5:: int`; after `1: -> int 5:: int 5:a=  5:b=  6:*values= ` |
  | gopls | none: `hints` defaults to `{}` (gopls' `doc/settings.md:550-556`, golang/tools master), and `go.lua` set them all false | `parameterNames`, `assignVariableTypes`, `rangeVariableTypes`, `functionTypeParameters` on (`lang/go.lua:22`) | before none; after `8:int 8:a: 8:b: 10:a...: 9:int 9:int` |
  | clangd | parameter names | none | `3:a: 3:b:` |
  | rust_analyzer | variable types, parameter names | none | `3:: i32 3:a: 3:b:` |
  | tinymist | parameter names | none | `2:a: 2:b: 3:a: 3:b:` |
  | fish_lsp | exit status descriptions after `return` and `exit` (its `inlayHint` handler is on unless `fish_lsp_disabled_handlers` names it, README) | none | `2: → General error 4: → Command not found` |
  | tombi | resolved dependency versions in `Cargo.toml` and `pyproject.toml` (`dependency-version`, `ToggleFeatureDefaultTrue` in SchemaStore's `tombi.json`) | none | none on the fixture's `pyproject.toml`, which has no lock file |
  | docker_language_server | a Dockerfile image's Docker Hub info; overridden values in Compose files (its README) | none | `1:(last pushed 6 months ago)` on `FROM alpine:3.20` |
  | ruff, bashls, yamlls, marksman, terraformls, tflint, html, cssls, neocmake, biome | no `inlayHintProvider` | none | |

- Left off: gopls' `compositeLiteralFields`, `compositeLiteralTypes` and `constantValues` (struct literals are keyed in
  idiomatic Go, and a constant's value is on its line already); pyrefly's `pytestParameters` (no effect yet, its docs).
  The servers that send hints by default keep their defaults.
- `checks/lsp_inlay_hints.lua` (clangd): hints show in a buffer without a key press, `<leader>Th` hides them in that
  buffer only and shows them again, and its label follows. It fails on main's config (6 of its 10 assertions).

Rejected:

- Enabling per buffer on `LspAttach` (`enable(true, { bufnr })` when the client supports the method): the same
  result with an autocmd, and a buffer the user turned off would come back on when a second server attached.
- Per-server `on_attach` enables: a new server would need a line each (as for code lenses).
- Turning every hint kind on for every server: gopls' composite literal hints and pyrefly's names on every builtin
  call are noise the user didn't ask for.

Known effects:

- docker-language-server's Dockerfile hint comes from Docker Hub, so a Dockerfile's hints need the network (the probe's
  hint names how long ago the tag was pushed). Off with `<leader>Th`.
- pyrefly's `callArgumentNames = "all"` names builtin parameters too (`*values=` on `print(x)`).

## Cost

Per keystroke in insert mode: every `didChange` sends one inlay hint request for the whole buffer and cancels the one
in flight (`R/inlay_hint.lua`, `InlayHint:refresh`). Measured in the sandbox (`tests/regress/nv.sh nightly`) with a
UI attached, so drawing counts: a child nvim in a 120x36 terminal opened a copy of `nvim/lua/lsp/buffer.lua` (lua_ls,
211 hints), then typed 60 characters on a new line, 50 ms apart; the cost is the child's CPU time (`getrusage`) over
the typing and 500 ms after, divided by 60. Hints on (this branch) against off (`vim.lsp.inlay_hint.enable(false)`,
as on main), 3 runs per side per round, interleaved, 5 rounds (2026-10-25,
`~/.cache/nvim-config/followups/bench/`, not kept):

| round | on, µs per key | off, µs per key | on - off |
|---|---:|---:|---:|
| 1 | 23809 | 23716 | 93 |
| 2 | 22081 | 21489 | 592 |
| 3 | 21957 | 20921 | 1036 |
| 4 | 22488 | 21025 | 1463 |
| 5 | 22512 | 21444 | 1068 |
| all 15 runs | 22161 | 21255 | 906 |

- Hints cost about 0.9 ms of CPU per key, more in all 5 rounds: about 11% of D61's 8.3 ms frame, logged and not acted
  on. The inlay hint handler itself took a median 7.8 µs per key: lua_ls answered only 1 to 9 of the 60 requests per
  run, since each new change cancelled the one before, so the rest is sending and cancelling the requests and drawing.
- Both sides spend about 21 ms of CPU per typed key in this file, most of it outside inlay hints (completion,
  treesitter, diagnostics; not broken down here).
