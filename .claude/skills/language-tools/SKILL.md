---
name: language-tools
description: Add a language to this Neovim config, or add, swap or remove a language's LSP server, formatter, linter or file-scoped tool, end to end. Covers finding the plugin's built-in definition and the tool's mise spec, every file to edit (tool catalog, lsp_servers, after/lsp, conform, nvim-lint, sub-filetypes, treesitter), verifying installs in an isolated mise, the regression checks to add and run, and updating the decisions doc and README. Use it whenever the user asks for support for a language or file type, a different language server, formatter or linter, or wants a tool to run only on certain files, even if they don't name these files.
---

# Language tools

Every LSP server, formatter and linter in this config is a binary that the resolver (`nvim/lua/tools/`) finds per project through mise. Wiring a tool takes two or three lines of Lua. The work is in choosing the right definition and spec, proving the tool runs, and recording why.

`R` is the repo root (the dir with `nvim/`, `tests/`, `docs/`); `SK=$R/.claude/skills/language-tools/scripts`; `T` is your isolated mise dir, made once (see below) and reused. Bash calls don't keep variables, so set them in each call. Quote real command output in your notes and report; the report is checked against it.

## Ground rules

- **The user's real mise is off limits.** Installs go only into an isolated mise (`$SK/iso-mise.sh <dir> ...`) or the suite's own (`suite.sh --refresh`). So no `mise use -g`, `mise install`, `mise trust` or `rustup component add` in a plain shell, and no edits to `~/.config/mise/`.
- **Scratch goes on disk.** `/tmp` is a small RAM-backed tmpfs on this machine. Make dirs with `mkdir -p ~/.cache/language-tools && T=$(mktemp -d -p ~/.cache/language-tools)`, and delete them when done.
- **Memory is shared with other sessions.** Run one heavy command at a time (the suite, a server), capped: prefix it with `systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=512M --`.
- Edit files inside `R` only. No push, no PR.

## Steps

**1. Read the plugin's built-in definition, and use its exact name.** Before writing any wiring, open the file the plugin ships for the tool (`references/choose-tool.md` 1.1):

- server: `nvim-lspconfig/lsp/<name>.lua`
- formatter: `conform.nvim/lua/conform/formatters/<name>.lua`
- linter: `nvim-lint/lua/lint/linters/<name>.lua`

Use that file's name in the config and catalog (conform calls `terraform fmt` "terraform_fmt"). Its `cmd`/`command` gives the binary, and its `args` show how the editor runs it. A definition of your own is only for a tool the plugin lacks. A second definition of a shipped tool drifts from upstream, and the audit fails on it.

**2. Find the mise spec** (`choose-tool.md` 1.2). Ask the registry first: `$SK/iso-mise.sh $T mise registry <tool>`. If it isn't there, find the upstream repo before guessing a backend. Look in the lspconfig `---@brief` URL, conform's `meta.url`, nvim-lint's README table, or the crates.io/PyPI/npm metadata. Then query `aqua:` / `github:` on that owner/repo, then `npm:` / `pypi:` / `go:`, then `cargo:`. A version printed by `mise latest <spec>` proves the spec.

**3. Install it isolated and run it the way the plugin runs it** (`references/verify.md` 1-2). Use `$SK/iso-mise.sh $T mise use -g <spec>@latest`, adding `node@lts`/`go@latest` for npm/go tools. Then:

- a server must answer `initialize` through `$SK/lsp-init.lua`;
- a formatter must fix a bad sample, and a linter must report on one.

Copy the command and args from the built-in definition you read in step 1. Don't add flags of your own: tools differ, and `--stdin-filename` is only right where the definition has it. Keep the output; the tests use it.

**4. Edit the config.** One row per kind of change; `references/edit-files.md` has each edit with before/after:

| Change | Edit |
|---|---|
| Any new binary | `nvim/lua/tools/catalog.lua`: one entry keyed by the binary, with the spec and the role names from step 1 |
| Server | its nvim-lspconfig name in `M.servers` (`nvim/lua/core/lsp_servers.lua`); `nvim/after/lsp/<server>.lua` only for settings or filetypes |
| Formatter | `formatters_by_ft` in `nvim/lua/plugins/conform.lua` (a plain list of names) |
| Linter | `linters_by_ft` in `nvim/lua/plugins/nvim-lint.lua`; `covering_server` only if a server reports the same rules |
| New language | `ensure_installed` in `nvim/lua/plugins/nvim-treesitter.lua`, if a parser exists |
| Tool for some files only | a dotted sub-filetype: `references/sub-filetypes.md`, all of it |
| Removing or replacing | `references/remove-or-replace.md` |

For a sub-filetype, two things are easy to miss. Every server of the base filetype must list the dotted name in its `after/lsp/<server>.lua` (yamlls lists `yaml.github-actions`), or it stops attaching. And a linter that already runs elsewhere must still report on the new kind of file with its existing args: run it on a sample (step 3) before wiring it.

**5. Add regression checks** (`references/tests.md`): a fixture in the `lsp_attach` list for a server, a `format_<name>.lua` or `lint_<name>.lua` check for a formatter or linter, with `@needs <binary>`. For a sub-filetype, add cases to `tools_subfiletypes.lua` plus a check that opens a matching file. Take expected output from step 3; a guessed rule id fails.

**6. Update the docs** (`references/docs.md`). Name each new tool in `docs/mise-tooling-decisions.md`: its row in "Per-language tools", an "Install specs" row with the spec, and a "Decided since:" bullet with the step 2-3 evidence. A sub-filetype also gets a "File-scoped tools" row and a mention in the README's Tier 1 sentence. `check.sh` prints any row that is missing.

**7. Run the check, then the suite.**

```sh
$SK/check.sh $R
```

It runs in seconds: the wiring audit, the docs and tests for each binary and sub-filetype your change added, and stylua. Fix each `MISSING` line until it prints `CHECK OK`. Then run the suite, in the background (`references/verify.md` 4):

```sh
cd $R/tests/regress && mkdir -p last && systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=512M -- ./suite.sh --refresh '^(startup|<your checks>)$' > last/language-tools.log 2>&1
```

`--refresh` installs each `@needs` into the suite's own mise. Then run `./suite.sh --area startup,smoke,tools,lsp,format,lint` (add `treesitter` if you touched it). Both must end with `SUITE PASS`. On a FAIL, fix the cause, never the check.

**8. Report:** the files changed, the step 2-3 commands and output, the `check.sh` and suite results, and anything left for the user, such as a version coupling or a config file the tool needs.

## What the code does for you

`tools.for_filetype` (`nvim/lua/tools/init.lua`) reads the server filetypes, `formatters_by_ft` and `linters_by_ft`. The install prompts, `:Tools`, the statusline and `:Status` all follow from it. `core/lsp_servers.lua` starts each listed server from the resolved binary with the catalog args, so `cmd` in `after/lsp/` has no effect.
