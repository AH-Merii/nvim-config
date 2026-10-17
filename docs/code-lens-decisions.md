# Code lens decisions

Code lenses on for every language server that has them: "if an lsp supports it I want it, if it doesn't then I
don't" (the user, 2026-10-17).

## How Neovim draws them

Neovim nightly (`$VIMRUNTIME/lua/vim/lsp/`, v0.13.0-dev-1868):

- Off per buffer unless enabled (`_capability.lua:244-248`), and requested only from clients that support
  `textDocument/codeLens` (`_capability.lua:182`, `client.lua:1234-1241`).
- Requested on attach and on each `didChange` (`_capability.lua:271`, `codelens.lua:63-64,115-123`), drawn as
  `virt_lines` above the line by a decoration provider's `on_win`, for the visible rows only
  (`codelens.lua:174-177,233-235`). Scrolling sends no request.
- `grx` runs the lens on the cursor line from a fresh request (`codelens.lua:419-431`).

## Decisions

### Enable drawing globally, toggle per buffer

- Decision: `vim.lsp.codelens.enable(true)` once in `config/autocmds.lua` (now `lsp/buffer.lua`), next to
  `vim.lsp.document_color`. `<leader>Tc` hides or shows the lenses of the current buffer
  (`vim.lsp.codelens.enable(state, { bufnr = 0 })`).
- Why: a server that has none is never asked, so the global switch costs nothing there. The key is gated on
  `textDocument/codeLens` in `core/lsp.lua` (now `lsp/buffer.lua`), like `<leader>Th` on inlay hints, so it only
  exists where it does something.
- Key: `c` for code lens; free in the `<leader>T` group, which uses t G h e f T i s w L d l m g D H
  (`plugins/snacks.lua`, `plugins/git.lua`, `plugins/nvim-treesitter.lua`, `plugins/colorschemes.lua`; now
  each owner's file under `features/`, `lsp/buffer.lua`, `ui/snacks.lua` and `ui/theme.lua`).
- Rejected: per-server `on_attach` enables, as nvim-lspconfig does for terraformls only
  (`nvim-lspconfig/lsp/terraformls.lua:44-46`); a new server would need a line each.

### pyrefly: Run and Test lenses, run by the config

- pyrefly advertises `codeLensProvider` but returns none unless `python.pyrefly.runnableCodeLens` is true
  (pyrefly 1.4.0 `lsp/non_wasm/workspace.rs:258,592-593`; the VS Code setting defaults to false,
  `lsp/package.json:389-393`).
- Its lenses name client commands, `pyrefly.runMain` and `pyrefly.runTest` (`lsp/non_wasm/code_lens.rs:44-77`),
  which pyrefly's VS Code extension implements (`lsp/src/code-lens.ts`); without them `grx` only warns that the
  server does not support the command (`runtime/lua/vim/lsp/client.lua:1147-1155`).
- Decision: `after/lsp/pyrefly.lua` (since D46, `lua/lang/python.lua`) turns the setting on and implements both
  commands the way the extension does:
  the file with the project's Python, `python -m unittest <module>.<Class>.<test>` for unittest tests and
  `python -m pytest <file>::<Class>::<test>` otherwise, in a terminal split. The Python is the nearest `.venv`,
  then `$VIRTUAL_ENV`, then `python3`.
- When that Python can't import pytest, a pytest lens warns, naming the Python and `uv add --dev pytest`, instead
  of opening a terminal on "No module named pytest" (the user read that as a bug in a file that imports
  unittest). The extension shows an error the same way (`lsp/src/code-lens.ts`, `canImportModule`).
- pyrefly answers a lens request that arrives before it applies the client's settings with none, and sends no
  `workspace/codeLens/refresh` afterwards (lsp.log of `tests/regress/checks/pyrefly_codelens.lua`: request 4
  answered `result = {}`, then "Client configuration applied"). The config re-requests lenses after each
  `workspace/configuration` it answers.

## Cost

`j` then `:redraw`, 6 passes over each file, headless nightly (80x24 grid), the full config; median of three runs'
medians, µs per key (`~/.cache/nvim-config/codelens/bench/measure.lua`):

| file | lenses | on | off | difference |
| --- | --- | --- | --- | --- |
| Go, 183 lines, 30 tests (gopls) | 30 | 413 | 392 | +21 |
| Lua, 125 lines, 30 functions (lua_ls) | 30 | 359 | 340 | +19 |
