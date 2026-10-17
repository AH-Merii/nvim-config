# Replacing or removing a tool or a language

To **replace** a tool, remove the old one (this file) and add the new one (`edit-files.md`), in the same change. Real example: actionlint was replaced by jactionlint.

1. The catalog swapped `actionlint` for `jactionlint = { spec = "jactionlint", linters = { "jactionlint" } }`.
2. nvim-lint had no jactionlint, so it got a definition of its own (now `definitions.jactionlint` in `nvim/lua/linting/nvim_lint.lua`).
3. The name was swapped in the workflow files' linters (now the `yaml.github-actions` variant in `nvim/lua/lang/yaml.lua`).
4. `checks/lint_jactionlint.lua` (`@needs jactionlint`) replaced the deleted `lint_actionlint_paths.lua`.
5. The decisions doc got a "Decided since" bullet quoting mise's deprecation warning.

## Removal checklist

Find every mention first, so nothing is left behind:

```sh
grep -rn -i "<binary>\|<server name>\|<formatter name>\|<linter name>" nvim/lua nvim/after tests/regress/checks tests/regress/work tests/regress/fixtures docs README.md CONTRIBUTING.md
```

Then remove, and tick off each item:

1. The catalog entry in `nvim/lua/tools/catalog.lua`, unless another entry lists it in `requires`. Example: shellcheck stays, because bash-language-server requires it.
2. The server under `servers` in its language file (`nvim/lua/lang/<lang>.lua`), with its settings, any variant's `servers` list naming it, and any `roots.<name>` in `nvim/lua/core/lsp_servers.lua`.
3. The formatter in the language's `formatters` (and a variant's), and any `definitions.<name>` in `nvim/lua/format/conform.lua`. A filetype left with no formatter falls back to LSP formatting.
4. The linter in the language's `linters` (and a variant's), plus any `keep_cwd` entry and `definitions.<name>` in `nvim/lua/linting/nvim_lint.lua`.
5. A variant that only existed for this tool: its entry under `variants`, and its cases in `checks/tools_subfiletypes.lua`.
6. A whole language: its file in `nvim/lua/lang/`. Its `parsers` go with it; keep a parser you still want by moving it to another language or to `ensure_installed` in `nvim-treesitter.lua`.
7. In tests: every `@needs` naming the binary, because `--refresh` fails on a need missing from the catalog. Also the fixture file, its entry in the `lsp_attach.lua` file list, and checks that only tested it.
8. Docs: strike the tool in the per-language table (`~~name~~`, with "replaces" or "dropped" and why), and add a "Decided since" bullet.

Some things are not tool wiring, so leave them unless the user asks: `nvim/after/ftplugin/<lang>.lua` keymap labels, and a language's `parsers` and `options` when only a tool goes. When PHP was dropped, `after/ftplugin/php.lua` stayed.

Nothing is uninstalled from the user's mise. The user runs `mise uninstall` themselves if they want to. The suite's mise never uninstalls either (`tests/regress/README.md`, "Refresh").

Verify with `nvim --clean --headless -l tests/unit/lang_test.lua` (it fails while a language names a tool the catalog lost) and `$SK/check.sh $R`: it lists each removed binary, and fails while a check still lists it in `@needs` or the decisions doc doesn't strike it (`~~name~~`). Pass `FT="<the language's filetypes>"` to see that the old tool is on no `ft` line. Then run the suite (SKILL.md step 7).
