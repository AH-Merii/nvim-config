# File-scoped tools: dotted sub-filetypes

Use this when a tool should run on, and be offered for, only some files of a filetype. Two exist today:

- workflow YAML gets jactionlint and zizmor;
- `pyproject.toml` gets pyproject-fmt.

These files get a **dotted sub-filetype**, `<base>.<part>` (`yaml.github-actions`, `toml.pyproject`). Each consumer reads the dotted name in its own way (decisions doc, "File-scoped tools"):

| Consumer | Reads a dotted filetype as | Consequence |
|---|---|---|
| nvim-lint | With no key for the whole name, the union of every part's linters | Key linters by the **extra part**: `["github-actions"]` |
| conform | The whole name first, then the most specific part | A formatter keyed `["toml.pyproject"]` replaces the base's formatter on that file only |
| LSP servers | Exact match only | Every base server that should still attach must list the dotted name |
| treesitter | The first part | Nothing to do |
| install offer, `:Tools`, lualine | `tools.for_filetype`, which follows the rows above | Nothing to do |

## Steps

1. **Define it in `nvim/lua/tools/filetypes.lua`.** Edit both places in the file:
   - the description in `M.filetypes`, which the tests loop over;
   - the matcher in `vim.filetype.add`.

   Use `filename` for an exact base name in any dir. Use `pattern` for a Lua pattern matched against the full path; escape `.` and `-` as `%.` and `%-`, and use `ya?ml` for both extensions.

   ```lua
   -- before
   M.filetypes = {
     ["yaml.github-actions"] = "GitHub workflows: jactionlint, zizmor",
     ["toml.pyproject"] = "pyproject.toml: pyproject-fmt",
   }
   ...
       pattern = {
         [".*/%.github/workflows/[^/]*%.ya?ml"] = "yaml.github-actions",
       },
   -- after: one more description and one more matcher
   M.filetypes = {
     ["yaml.github-actions"] = "GitHub workflows: jactionlint, zizmor",
     ["toml.pyproject"] = "pyproject.toml: pyproject-fmt",
     ["<base>.<part>"] = "<which files>: <tools>",
   }
   ...
       pattern = {
         [".*/%.github/workflows/[^/]*%.ya?ml"] = "yaml.github-actions",
         ["<lua pattern for the full path>"] = "<base>.<part>",
       },
   ```

2. **Give the sub-filetype its tools.**
   - Linters go under the **extra part**, in `nvim/lua/plugins/nvim-lint.lua`:

     ```lua
           -- Workflow files are yaml.github-actions (lua/tools/filetypes.lua)
           ["github-actions"] = { "jactionlint", "zizmor" },
     ```

     Do not key a linter by the full dotted name. A full-name key replaces the union, so the file silently loses its base linters (yamllint on YAML), and `checks/tools_subfiletypes.lua` fails with "keeps yaml's servers and linters".
   - Formatters go under the full dotted name, in `nvim/lua/plugins/conform.lua`:

     ```lua
           toml = { "tombi" },
           ["toml.pyproject"] = { "pyproject-fmt" },
     ```

     A formatter key replaces the base's formatter on those files. Add none if the base formatter should still run.
   - A tool another sub-filetype already uses needs no new catalog entry; listing it under the new part is enough. But it runs there with the args it already has, which were chosen for the other files (`jactionlint` runs with `--profile correctness`, `nvim/lua/plugins/nvim-lint.lua:42`). Before wiring it, run it with exactly those args on a bad sample at a realistic path of the new kind (`verify.md` section 2), and check that it reports. If it reports nothing, wiring it adds an offer and no findings: tell the user what the current args do there and leave the arg choice to them.
3. **Keep the base's servers attached.** List the base filetype's servers: `FT="<base>" $SK/check.sh $R` prints them on its `ft <base>:` line. For each server, add the dotted name to `filetypes` in `nvim/after/lsp/<server>.lua`, keeping the names already there. The yamlls example lists every sub-filetype it serves:

   ```lua
   -- nvim/after/lsp/yamlls.lua
     filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab", "yaml.helm-values", "yaml.github-actions" },
   ```

   If you forget this, the server quietly stops attaching on those files.
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
