# Unit tests

Fast in-process tests of the config's deep modules, each through its interface, with no plugins. A file runs in
milliseconds; the whole tier in seconds. The regression suite (`tests/regress`) stays the gate for the whole config.

## Run

```sh
mise run test:unit                 # every tests/unit/*_test.lua
tests/unit/run.sh tools            # files whose name matches a regex
tests/unit/run.sh -v               # print each file's output too
nvim --clean --headless -l tests/unit/tools_test.lua   # one file alone, from the repo root
```

`run.sh` runs each file in its own `nvim --clean --headless` with throwaway `XDG_*` and `TMPDIR` dirs, prints
PASS or FAIL per file with its time and a failing file's output, and exits non-zero on any failure. It uses the
suite's nightly Neovim when it is installed, else `nvim`; `NVIM=/path/to/nvim` picks another.

## Writing a test

- One file per module, `tests/unit/<module>_test.lua`.
- Its first lines put `nvim/lua` (and `tests/unit`, for the helpers) on `package.path`, relative to the file:

  ```lua
  local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
  package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")
  ```

- It loads no plugins, and fails by raising an error, so `nvim -l` exits non-zero.
- It keeps its writes in throwaway dirs (`helper.tmpdir()`), so it is safe to run alone, outside `run.sh`.

## Helpers

- `helper.lua`: `case(name, fn)` runs one case and records a failure without stopping the file; `eq`, `ok`;
  `await(fn)` waits for a callback; `tmpdir`, `write`, `bin` (an executable whose `--version` prints a version);
  `finish()` ends the file, raising when a case failed or none ran.
- `fake_backend.lua`: a tool backend for `require("tools").setup({ backend = … })`, with global tools and a
  project's mise pins from a table; it records the installs asked of it.
- `fake_server.lua`: a language server started through the real `vim.lsp` with a Lua `cmd`: the test sets its
  capabilities, registers more later, and reads the requests it received.
