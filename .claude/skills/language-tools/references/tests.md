# Regression checks (SKILL.md step 5)

The suite lives in `tests/regress/`; its rules are in `tests/regress/README.md`, "Add a check". Before writing a new check, load the `shoop:writing-tests` skill if it is available. The rules that matter most here:

- Keep a check only if it goes red on a real regression and stays green under any valid alternative implementation. Asserting that a table holds a value is not a check: assert behaviour (attaches, formats, reports a finding).
- Wait on events (`wait_attach`, `wait_diagnostics`, `wait_until`), never fixed sleeps.
- `@needs` lists **catalog binaries** (catalog keys, not plugin names). The check fails before its body if one does not resolve, and `suite.sh --refresh` installs them into the suite's own mise.

## What to add, per change

| Change | Add | Run (by name filter) |
|---|---|---|
| New server | A small valid source file in `tests/regress/fixtures/default/` (one file per language: `main.lua`, `app.py`, `hello.c`, ...). Its path goes in the `files` list in `checks/lsp_attach.lua` (line 6-7), and its binary in that file's `@needs` (line 5). If the server needs a project file to find its root, add that file to the fixture as well | `lsp_attach`, `lang_views`, `startup` |
| New server settings in a language file | Nothing new. `checks/lang_views.lua` checks that every server's fields reach `vim.lsp.config` | `lang_views` |
| New formatter | A format check from the template below | it, plus `format_buffer` |
| New linter | A lint check from the template below | it, plus `lint_compound_ft` |
| Sub-filetype | Cases in `checks/tools_subfiletypes.lua` (see below), plus a lint or format check proving the tool reports on a matching file | `tools_subfiletypes`, `tools_prompts`, and the new check |
| Tool or language removed | Remove its name from every `@needs` (`grep -rn "@needs.*<binary>" tests/regress`), and remove its fixture file and its entry in the `lsp_attach` file list. Delete checks that only tested it | `lsp_attach`, `startup` |

Every row also runs `startup`. It fails on any warning or error a user would see at startup, such as a server name missing from the catalog.

Put new checks straight in `tests/regress/checks/<name>.lua`, since they land with the change. Name them `lint_<linter>.lua` or `format_<formatter>.lua`.

## Lint check template

This template was tried against jactionlint, and both checks passed. Fill in the `<...>` parts.

Take the finding's `code` from the real output you got in `verify.md` section 2. Do not guess it: a guessed rule id (`runner-label` instead of `unknown-runner-label`) fails the check. The namespace is the nvim-lint name from step 1.

```lua
-- @desc     <linter> findings appear on a <filetype> buffer, from the binary the resolver finds
-- @areas    lint tools
-- @budget   20
-- @needs    <catalog binary>
local ns = require("lint").get_namespace("<nvim-lint name>")
vim.fn.writefile({ "<line>", "<line with a known finding>" }, "<sample file name>")
vim.cmd.edit("<sample file name>")
local buf = vim.api.nvim_get_current_buf()
check("the sample is <filetype>", vim.bo[buf].filetype == "<filetype>", vim.bo[buf].filetype)
wait_diagnostics(buf, function() return #vim.diagnostic.get(buf, { namespace = ns }) > 0 end, 10000)
local diags = vim.diagnostic.get(buf, { namespace = ns })
check("<linter> reports the <code> finding", vim.iter(diags):any(function(d) return d.code == "<code>" end),
  vim.inspect(vim.tbl_map(function(d) return d.code end, diags)))
```

- For a file-scoped linter, create the sample at a matching path, with `vim.fn.mkdir(<dir>, "p")` first.
- Add a second buffer at a near-miss path, and check that it gets the base filetype and no diagnostics in `ns`. `checks/lint_compound_ft.lua` shows this negative pattern; it waits a bounded `wait_until` before asserting none.
- A linter with `covered_by` is skipped while its server is attached. Its check must therefore run without that server, or assert through the server instead.

## Format check template

This template was tried against stylua, and it passed.

```lua
-- @desc     formatting a <filetype> buffer through conform runs <formatter> and leaves it formatted
-- @areas    format
-- @budget   15
-- @needs    <catalog binary>
vim.fn.writefile({ "<badly formatted line>" }, "<sample file name>")
vim.cmd.edit("<sample file name>")
local buf = vim.api.nvim_get_current_buf()
local conform = require("conform")
local names = vim.tbl_map(function(f) return f.name end, conform.list_formatters_to_run(buf))
check("<formatter> is planned for <filetype>", vim.list_contains(names, "<formatter>"), table.concat(names, ","))
local ok, err = pcall(conform.format, { bufnr = buf, async = false, timeout_ms = 10000 })
check("conform.format runs", ok, err)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
check("the buffer is formatted", vim.deep_equal(lines, { "<expected line>" }), table.concat(lines, " | "))
```

Take the expected lines from the formatter's real output in `verify.md` section 2.

## Sub-filetype: `checks/tools_subfiletypes.lua`

1. Add path cases to the `cases` list at the top: `{ "<path>", "<expected filetype>" }`. Include each path that should match (both `.yml` and `.yaml` if the pattern allows both) and at least one near miss that must keep the base filetype.
2. Read the existing cases. One may already name your file with its **old** filetype as a near miss; change its expected value to the new sub-filetype.
3. The loop after the cases runs on every `M.filetypes` entry by itself. It fails unless all of these hold:
   - the sub-filetype has tools of its own, keyed by its full name or extra part;
   - the base does not need those tools;
   - the base has at least one server;
   - the sub-filetype keeps the base's servers and linters, and keeps the base's formatters unless it sets its own.

   A failure there means the wiring is wrong. Fix the config, not the check.

## Run them

`check.sh` (SKILL.md step 7) fails while a new binary is in no check's `@needs`, or a new sub-filetype has no `tools_subfiletypes.lua` case or no check that opens a matching file. Then run them in the suite (`verify.md` section 4): `suite.sh --refresh '^(startup|<the Run column's checks>|<your new checks>)$'`, then the area run.
