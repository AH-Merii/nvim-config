# Step 6: update the docs (with the code, not after it)

`docs/mise-tooling-decisions.md` is the living record of every tool choice, and the code and that doc change together. CONTRIBUTING.md describes how the system works; it changes only when that changes. Every claim you add carries its source: a `path:line`, or a command plus the relevant output from steps 2 and 3. `check.sh` fails while a row below is missing, and its `MISSING` line prints the row to fill in, with the spec and the language's current tools.

## Decisions doc: `docs/mise-tooling-decisions.md`

Find the four places by their anchors:

```sh
grep -n '^## Per-language tools\|^## Install specs\|^## File-scoped tools\|^Decided since:' docs/mise-tooling-decisions.md
```

1. **"Per-language tools" table** (`| Language | Language server | Formatter | Linter |`):
   - A new language gets a new row, placed near related languages.
   - A changed language gets its row edited.
   - Follow the legend above the table, "Bold = change from today. Struck = removed": write the new tool as `**name**`, and a replaced one as `~~old~~`. For example, the existing row `| YAML | yamlls | prettierd | yamllint, **jactionlint**, replaces ~~actionlint~~; **zizmor** |`.
   - Write `none` in a column with no tool.
2. **"Install specs" table** (`| Tool | Spec | Verified |`): add one row per new binary.
   - The Spec column holds the exact catalog spec, plus anything you learned about it: registry or backend, and a runtime need such as "node at runtime".
   - Write `yes` in Verified only if step 3 installed it in the isolated mise and ran it. Otherwise write what is missing.
   - Example row: `| jactionlint | \`jactionlint\` (registry: \`github:jdx/jactionlint\`; v2.1.0, static binary) | yes |`.
3. **Sub-filetype** (only if you added one): add a row to the "File-scoped tools" table, `| Files | Filetype | Extra tools |`. For example: `| \`pyproject.toml\` | \`toml.pyproject\` | pyproject-fmt (format) |`.
4. **The decision itself:** add a bullet at the top of the "Decided since:" list near the end of "Deviations in the build". The doc puts the newest entries first. Copy the shape of the existing actionlint → jactionlint bullet:

   ```markdown
   - **<what changed>** (<YYYY-MM-DD>). <Why, in one or two sentences.> Evidence and choices:
     - <the spec and how you found it: `mise registry x` printed `...`, or `mise latest aqua:o/r` printed `1.2.3`>
     - <the run: `lsp-init.lua` printed `capabilities ...`, or the linter reported `<code>` on the sample>
     - <scoping: which filetypes get it, and the `covered_by` / sub-filetype choice and why>
     - <anything left open, marked unverified>
   ```

5. **"Status" section:** if the change is a feature-sized follow-up, add it to the "Follow-ups built" line.

## CONTRIBUTING.md

Edit CONTRIBUTING.md only in these cases:

| Your change | CONTRIBUTING.md edit |
|---|---|
| Added a sub-filetype | The "Tools from mise" bullet that lists the sub-filetypes: "Workflow YAML is `yaml.github-actions`, `pyproject.toml` is `toml.pyproject`, and Compose and Bake files are ...". Add yours to that sentence |
| Changed how a tool is added (a new language file field, a new file in the recipe) | "Adding a language or a tool", "Language File Pattern" and "Formatting & Linting Chain" |
| Anything else | Nothing. The per-language tool list lives only in the decisions doc |

## Check

`$SK/check.sh $R` checks each binary and sub-filetype your change added: the "Per-language tools" table names it (the tool, its role name or its binary), the "Install specs" table has a row with it and its exact spec, and the "Decided since:" list mentions it. A sub-filetype also needs its "File-scoped tools" row and a mention in CONTRIBUTING.md. The row must also agree with the code: compare it with the `ft <filetype>:` lines `check.sh` prints for the new tool's filetypes.
