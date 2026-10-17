# Verifying a language change

Sections 1-2 belong to SKILL.md step 3, sections 3-4 to step 7. Start every Bash call with:

```sh
R=<repo root>; SK=$R/.claude/skills/language-tools/scripts
```

## 1. Install into an isolated mise

`scripts/iso-mise.sh <dir> <command...>` runs one command with a mise that lives entirely in `<dir>`. What it does, so you can trust and debug it:

- It refuses a relative dir, and any dir inside the user's own mise dirs.
- It unsets the shell's `MISE_*` and `__MISE_*` variables, and points `MISE_DATA_DIR`, `MISE_CACHE_DIR`, `MISE_STATE_DIR`, `MISE_CONFIG_DIR`, `MISE_GLOBAL_CONFIG_FILE` and `TMPDIR` into `<dir>`.
- It sets `MISE_CEILING_PATHS=$HOME`; without that, mise reads `~/.config/mise/config.toml` as a project config.
- It removes the user's mise installs, mise shims and the old Mason bin from PATH. A bare `command -v stylua` in a normal shell finds a stale Mason copy, so don't trust PATH lookups outside the script.
- It exports `NVIM_BIN`, the nightly nvim, by absolute path, and runs the command with `<dir>` as the cwd, so pass absolute paths.

Make one dir on disk (`/tmp` is RAM-backed here) and reuse it for the whole task:

```sh
mkdir -p ~/.cache/language-tools && T=$(mktemp -d -p ~/.cache/language-tools); echo $T   # later calls set T=<that path>
$SK/iso-mise.sh $T mise use -g <spec>@latest      # several at once is fine
$SK/iso-mise.sh $T mise exec -- <binary> --version
$SK/iso-mise.sh $T mise which <binary>            # must print a path under $T/data/installs
```

`mise use -g` is safe here only because `MISE_GLOBAL_CONFIG_FILE` points into `$T`; its output line names `$T/config/config.toml`.

**npm and go tools need their runtime in the same isolated config.** Without node, `mise exec -- bash-language-server --version` fails with `exec: node: not found` (exit 127):

```sh
$SK/iso-mise.sh $T mise use -g node@lts npm:<package>@latest   # or go@latest go:<module>@latest
```

A `pypi:` tool may need `uv` or python, and a `cargo:` tool needs rust. If an install fails for that reason, add the runtime the error names to the same command (not yet tried in this repo).

Delete `$T` when the task is done: `rm -rf $T`.

## 2. Run the tool the way the plugin runs it

The command and args come from the built-in definition you read in step 1 (`choose-tool.md` 1.1), not from memory or from another tool. Tools differ: one reads stdin with `-`, another with `--stdin`, another needs `--stdin-filename <path>` because it picks rules from the file name. Copy what the definition has, and only that. For a definition you wrote yourself, run exactly what it will run.

**A server must answer `initialize`.** Use the args from the catalog `servers` table:

```sh
$SK/iso-mise.sh $T bash -c "mise exec -- \"\$NVIM_BIN\" --clean --headless -l $SK/lsp-init.lua <binary> <args...>"
```

Pass: exit 0 and a `capabilities ...` line, e.g. `lsp-init.lua bash-language-server start` printed `capabilities codeActionProvider completionProvider definitionProvider ...`. `serverInfo nil` is fine. `FAIL no answer in 20s` or a non-zero exit means the binary or the args are wrong. Run it capped, as SKILL.md says: servers can be large.

**A formatter must change a badly formatted sample.** conform's `stylua.lua` has `args = { "--search-parent-directories", "--respect-ignores", "--stdin-filepath", "$FILENAME", "-" }`, so:

```sh
$SK/iso-mise.sh $T bash -c 'printf "local   x=1\n" | mise exec -- stylua --search-parent-directories --respect-ignores --stdin-filepath ~/.cache/language-tools/x.lua -'
# printed: local x = 1
```

**A linter must report a finding on a bad sample**, in the format its parser reads. nvim-lint's `shellcheck.lua` has `args = { "--format", "json1", <file or "-"> }`, so:

```sh
$SK/iso-mise.sh $T bash -c 'printf "#!/bin/sh\necho \$1\n" | mise exec -- shellcheck --format json1 -'
```

Pass: `{"comments":[{... "code":2086,"message":"Double quote to prevent globbing and word splitting." ...`. Keep the exact output: the regression check (`tests.md`) uses the finding's code or the formatted lines.

**A linter reused on a new kind of file** (a sub-filetype) runs with the args it already has. Run it that way on a bad sample of the new file, at a realistic path, and check that it reports. If it reports nothing there, the wiring is not enough: tell the user what the args are and what it would take, rather than changing args the other files rely on.

## 3. `check.sh`: the wiring, docs and tests (seconds)

```sh
$SK/check.sh $R                                  # FT="<fts>" FILES="<paths>" also print what those get
```

It compares the change with the base commit (the merge-base with the branch's upstream; `BASE=<ref>` overrides it) and prints `CHECK OK`, or one `MISSING` line per gap:

- **The audit** (`scripts/tool-audit.lua`, in the suite's sandboxed Neovim with a copy of `$R/nvim`). It checks that every server a language names has a catalog entry and an nvim-lspconfig config, and every catalog server is named. conform's `formatters_by_ft` (built from the languages) must hold plain lists, and every formatter and linter name must have a catalog entry and a definition. No definition of the config's own may replace or duplicate a built-in one: same name, or same command. Every sub-filetype must keep its base's servers and linters. It reads config, not binaries.
- **For each new binary:** mise knows its spec (`mise latest` in an isolated mise), the decisions doc names it (with the rows to add when it doesn't), and a check lists it in `@needs`.
- **For each new sub-filetype:** the File-scoped tools row, CONTRIBUTING.md, a "Decided since" entry, cases in `tools_subfiletypes.lua`, and another check that opens a matching file.
- **stylua** on the Lua you changed under `nvim/`.

## 4. The regression suite

The suite's tools live in `tests/regress/data/mise`, which is gitignored and separate from the user's mise. Runs over about 30 s go in the background (Bash `run_in_background: true`), capped, with the log in `last/`; read it with `tail`/`grep` (`tests/regress/README.md`, "Agents running the suite"):

```sh
cd $R/tests/regress && mkdir -p last && systemd-run --user --scope -q -p MemoryMax=2G -p MemorySwapMax=512M -- \
  ./suite.sh --refresh '^(startup|<checks>)$' > last/language-tools.log 2>&1
```

1. **`--refresh` with your checks.** It installs every check's `@needs` into the suite's mise, then syncs plugins and parsers. Without `tests/regress/data/mise` (a fresh clone) it installs every tool and can take 15 minutes. `tools: X is in a check's @needs but not in the catalog` means the catalog key and the `@needs` name differ. `./suite.sh --refresh-dry-run` previews the install list.
2. **The areas your change touches:** `./suite.sh --area startup,smoke,tools,lsp,format,lint`, plus `treesitter` if you edited a language's `parsers`. Those are the areas `tests/regress/areas.map` gives the catalog, `lsp_servers.lua` and `lua/lang/`. `--changed` would miss new untracked files.

Pass: `SUITE PASS`, with `PASS the user's mise config, mise installs and rustup toolchains unchanged` in the hygiene block. The hygiene block also watches the live nvim dirs, which the user's own Neovim writes to: a `FAIL live nvim dirs changed` line naming a file your run can't have touched (an editor's server log under `~/.local/share/nvim/`) comes from outside. Say so in the report, with the line, rather than counting it as your failure. On a FAIL, the reason is under the check's line and its output is in `last/nightly/<check>.out`. Fix the cause, rerun the failed checks by name, then the area run again.

The full plain `./suite.sh` is for the end of a branch. Say in the report that it has not been run, unless the user asked for it.
