# Replacing or removing a tool or a language

To **replace** a tool, remove the old one (this file) and add the new one (`edit-files.md`), in the same change. Real example: actionlint was replaced by jactionlint.

1. The catalog swapped `actionlint` for `jactionlint = { spec = "jactionlint", linters = { "jactionlint" } }`.
2. nvim-lint had no jactionlint, so `lint.linters.jactionlint` was defined inline in `nvim-lint.lua`.
3. The name was swapped in `["github-actions"]`.
4. `checks/lint_jactionlint.lua` (`@needs jactionlint`) replaced the deleted `lint_actionlint_paths.lua`.
5. The decisions doc got a "Decided since" bullet quoting mise's deprecation warning.

## Removal checklist

Find every mention first, so nothing is left behind:

```sh
grep -rn -i "<binary>\|<server name>\|<formatter name>\|<linter name>" nvim/lua nvim/after tests/regress/checks tests/regress/work tests/regress/fixtures docs README.md
```

Then remove, and tick off each item:

1. The catalog entry in `nvim/lua/tools/catalog.lua`, unless another entry lists it in `requires`. Example: shellcheck stays, because bash-language-server requires it.
2. The server name in `M.servers` in `nvim/lua/core/lsp_servers.lua`, and any `roots.<name>`.
3. `nvim/after/lsp/<server>.lua`. Delete it, or `checks/lsp_configs.lua` keeps checking a server that is no longer used.
4. The `formatters_by_ft` and `opts.formatters.<name>` entries in `conform.lua`. A filetype left with no formatter falls back to LSP formatting.
5. The `linters_by_ft` entries in `nvim-lint.lua`, plus its `covering_server`, `keep_cwd` and any custom `lint.linters.<name>`.
6. A sub-filetype that only existed for this tool: its `M.filetypes` description and matcher in `nvim/lua/tools/filetypes.lua`, its dotted names in `after/lsp/*` filetypes, and its cases in `checks/tools_subfiletypes.lua`.
7. In tests: every `@needs` naming the binary, because `--refresh` fails on a need missing from the catalog. Also the fixture file, its entry in the `lsp_attach.lua` file list, and checks that only tested it.
8. Docs: strike the tool in the per-language table (`~~name~~`, with "replaces" or "dropped" and why), and add a "Decided since" bullet.

Some things are not tool wiring, so leave them unless the user asks: `nvim/after/ftplugin/<lang>.lua` keymap labels and treesitter parsers. When PHP was dropped, `after/ftplugin/php.lua` stayed.

Nothing is uninstalled from the user's mise. The user runs `mise uninstall` themselves if they want to. The suite's mise never uninstalls either (`tests/regress/README.md`, "Refresh").

Verify with `$SK/check.sh $R`: it lists each removed binary, and fails while a check still lists it in `@needs` or the decisions doc doesn't strike it (`~~name~~`). Pass `FT="<the language's filetypes>"` to see that the old tool is on no `ft` line. Then run the suite (SKILL.md step 7).
