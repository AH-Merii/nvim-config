# Step 6: update the docs (with the code, not after it)

Three files change with the code:

- `docs/languages.md` lists what each language and variant runs. It is generated: run `mise run docs` from the repo root after editing the language files or the catalog, and commit it with them. Never edit it by hand.
- `docs/mise-tooling-decisions.md` is the record of why each tool was chosen.
- CONTRIBUTING.md describes how the system works; it changes only when that changes.

Every claim you add carries its source: a `path:line`, or a command plus the relevant output from steps 2 and 3. `check.sh` fails while `docs/languages.md` is out of date or a row below is missing, and its `MISSING` line says what to add.

## Generated tables: `docs/languages.md`

```sh
mise run docs        # rewrites docs/languages.md from nvim/lua/lang/ and nvim/lua/tools/catalog.lua
```

It has one row per language (servers, formatters in run order, linters with the server that covers each), one row per variant (the files that get it and the tools its base lacks), and one row per binary (its mise spec, project dirs, runtime). `git diff docs/languages.md` should show exactly the rows your change meant to change; anything else means the language file says something you didn't intend. `tests/unit/run.sh languages_doc` fails while the file is out of date. A tool that was replaced or dropped just leaves the generated tables; record why in "Decided since:" below.

## Decisions doc: `docs/mise-tooling-decisions.md`

Find the places by their anchors:

```sh
grep -n '^## Install specs\|^Decided since:\|^## Status' docs/mise-tooling-decisions.md
```

The per-language and file-scoped tables that used to be here moved to `docs/languages.md` (D73 in `docs/rearchitecture-decisions.md`); don't add rows for them here.

1. **"Install specs" table** (`| Tool | Spec | Verified |`): add one row per new binary.
   - The Spec column holds the exact catalog spec, plus anything you learned about it: registry or backend, and a runtime need such as "node at runtime".
   - Write `yes` in Verified only if step 3 installed it in the isolated mise and ran it. Otherwise write what is missing.
   - Example row: `| jactionlint | \`jactionlint\` (registry: \`github:jdx/jactionlint\`; v2.2.0, static binary) | yes |`.
2. **The decision itself:** add a bullet at the top of the "Decided since:" list near the end of "Deviations in the build". The doc puts the newest entries first. Copy the shape of the existing actionlint → jactionlint bullet:

   ```markdown
   - **<what changed>** (<YYYY-MM-DD>). <Why, in one or two sentences.> Evidence and choices:
     - <the spec and how you found it: `mise registry x` printed `...`, or `mise latest aqua:o/r` printed `1.2.3`>
     - <the run: `lsp-init.lua` printed `capabilities ...`, or the linter reported `<code>` on the sample>
     - <scoping: which filetypes get it, and the `covered_by` / sub-filetype choice and why>
     - <anything left open, marked unverified>
   ```

3. **"Status" section:** if the change is a feature-sized follow-up, add it to the "Follow-ups built" line.

## CONTRIBUTING.md

Edit CONTRIBUTING.md only in these cases:

| Your change | CONTRIBUTING.md edit |
|---|---|
| Added a sub-filetype | The "Tools from mise" bullet that lists the sub-filetypes: "Workflow YAML is `yaml.github-actions`, `pyproject.toml` is `toml.pyproject`, and Compose and Bake files are ...". Add yours to that sentence |
| Changed how a tool is added (a new language file field, a new file in the recipe) | "Adding a language or a tool", "Language File Pattern" and "Formatting & Linting Chain" |
| Anything else | Nothing. The per-language tool list is `docs/languages.md`, generated |

## Check

`$SK/check.sh $R` checks that `docs/languages.md` matches the language files, and for each binary and sub-filetype your change added: the "Install specs" table has a row with it and its exact spec, and the "Decided since:" list mentions it. A sub-filetype also needs a mention in CONTRIBUTING.md. For a removed binary, "Decided since:" must name it.
