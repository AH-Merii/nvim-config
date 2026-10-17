# File-scoped tools: dotted sub-filetypes (variants)

Use this when a tool should run on, and be offered for, only some files of a filetype. Four exist today, each declared with `match` rules:

- workflow YAML gets jactionlint and zizmor (`yaml.github-actions`, `nvim/lua/lang/yaml.lua`);
- `pyproject.toml` gets pyproject-fmt (`toml.pyproject`, `nvim/lua/lang/toml.lua`);
- Compose and Bake files get the Docker language server (`yaml.docker-compose`, `hcl.docker-bake`, `nvim/lua/lang/docker.lua`).

These files get a **dotted sub-filetype**, `<base>.<part>`, declared as a variant in a language file. One rule decides what it gets (`nvim/lua/lang/init.lua`): its base's servers and linters plus its own, and its own formatters if it names any, else its base's. Every consumer gets that answer explicitly:

| Consumer | Gets | Consequence |
|---|---|---|
| nvim-lint, conform | Their own key for the variant, with the whole list (`lang.views()`) | Their rules for dotted filetypes never decide anything |
| LSP servers | The variant in each server's `filetypes` | The base's servers keep attaching without any edit |
| treesitter | The first part | Nothing to do |
| install offer, `:Tools`, lualine, `:Status` | `lang.of(ft)` | Nothing to do |

## Steps

1. **Declare it under `variants`** in the file of the language whose tools it adds; its base (the first part) may be another language's filetype (`yaml.docker-compose` is in `docker.lua`). Give it `about`, the `match` rules for `vim.filetype.add`, and an `example` path that matches:

   - `filename` for an exact base name in any dir;
   - `pattern` for a Lua pattern matched against the full path, each with its options (`{}`, or `{ priority = 1 }` to win over another variant's pattern); escape `.` and `-` as `%.` and `%-`, and use `ya?ml` for both extensions.

   ```lua
   -- nvim/lua/lang/yaml.lua
     variants = {
       ["yaml.github-actions"] = {
         about = "GitHub workflows: jactionlint, zizmor",
         match = { pattern = { [".*/%.github/workflows/[^/]*%.ya?ml"] = { priority = 1 } } },
         example = ".github/workflows/compose.yml",
         linters = { jactionlint = {}, zizmor = {} },
       },
       ["<base>.<part>"] = {
         about = "<which files>: <tools>",
         match = { pattern = { ["<lua pattern for the full path>"] = {} } },
         example = "<a path that matches>",
         linters = { ["<nvim-lint name>"] = {} },
       },
     },
   ```

2. **Give it its tools.**
   - Linters under the variant's `linters`; the base's still run there.
   - Formatters under the variant's `formatters`, a list that replaces the base's on those files. Add none if the base formatter should still run.
   - Servers under the variant's `servers`, a list of names configured in some language's `servers` (`servers = { "docker_language_server" }`). The base's servers attach anyway.
   - A tool another sub-filetype already uses needs no new catalog entry; listing it under the variant is enough. But it runs there with the args it already has, which were chosen for the other files (`jactionlint` runs with `--profile correctness`, `lint.linters.jactionlint` in `nvim/lua/plugins/nvim-lint.lua`). Before wiring it, run it with exactly those args on a bad sample at a realistic path of the new kind (`verify.md` section 2), and check that it reports. If it reports nothing, wiring it adds an offer and no findings: tell the user what the current args do there and leave the arg choice to them.
3. **Run the unit test**: `nvim --clean --headless -l tests/unit/lang_test.lua` from `R`. It fails when the example path doesn't get the variant's filetype, or the variant loses its base's servers or linters.
4. **Check.** Pass matching paths and near misses in `FILES`, and the base and the sub-filetype in `FT`:

   ```sh
   FT="<base> <base>.<part>" FILES="<matching path> <near miss>" $R/.claude/skills/language-tools/scripts/check.sh $R
   ```

   Pass looks like this:
   - each path shows the expected filetype;
   - the sub-filetype line lists the new tool plus all of the base's servers and linters;
   - the base line does not list the new tool;
   - no `MISSING` line: a base server the sub-filetype lost shows as `sub-filetype <ft> loses <base>'s server <name>`.
5. **Tests and docs.** See `tests.md` ("Sub-filetype") and `docs.md` ("Sub-filetype"). Both have rows that apply only to sub-filetypes.
