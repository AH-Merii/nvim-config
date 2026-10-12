# language-tools skill: decisions

Record of the decisions for the project skill `.claude/skills/language-tools`, which walks an agent through adding a
language, or adding, swapping or removing a language's LSP server, formatter, linter or file-scoped tool, on top of the
mise tooling (`docs/mise-tooling-decisions.md`). Dates are when the decision was made.

## Status

- Built (2026-10-13) in the `nvimt2` slot, branch `nvimt2/language-tools-skill`, stacked on `nvimt2/mise-tooling`.
- Evaluated (2026-10-13) against no skill; kept because it passed where no skill didn't (see "Evaluation").

## Decisions (2026-10-13)

| Area | Decision | Rejected |
|---|---|---|
| Scope | One skill for every tool change, with the steps in `SKILL.md` and the detail in `references/` | a skill per tool kind |
| Verification | `scripts/check.sh` checks the change in seconds (spec known to mise, docs rows, a check in `@needs`), then the suite runs the named checks | the old `task.sh`, which ran the whole suite each time |
| Installs | only into an isolated mise (`scripts/iso-mise.sh`) or the suite's own | the user's real mise |
| Machine | scratch under `~/.cache`, heavy commands one at a time under `systemd-run ... MemoryMax=2G` | `/tmp` (RAM-backed), parallel suites |
| Evals | outside the skill, in `.claude/skill-evals/language-tools`, so a run with the skill can't read its own grader | evals inside the skill dir |
| Grading | deterministic check scripts, PASS/FAIL per check, proven to fail on an untouched clone and on one-bug variants and to pass on a reference solution (`validation/`) | a model grading against a rubric; Likert scores |
| Safety gate | `seed.sh` records the user's mise config and installs before a run; the gate compares against that | a fingerprint hard-coded once, which any later install broke |

## Evaluation (2026-10-13)

Three tasks, each run with and without the skill by Claude Sonnet 5.5 on low effort, in fresh clones: e1 add Zig
(zls, zig fmt), e2 add selene for Lua, e3 lint `.github/dependabot.yml` with jactionlint only. Checks passed per run:

| Eval | With skill | Without |
|---|---|---|
| e1 Zig (7 checks) | 7, 7, 7, 7, 6 | 5, 5, 5, 5, 5, 5 |
| e2 selene (6 checks) | 6, 6, 6, 6, 6 | 4, 4, 4, 4, 4, 5 |
| e3 Dependabot (7 checks) | 7, 7, 7, 7, 7, 7 | 0, 0, 0 |

- With the skill, 15 of 16 runs passed every check; without, none of 15 did. Without the skill, runs missed the
  regression check and the decisions-doc rows every time, and on e3 read the task as "lint this file now" and changed
  nothing.
- Excluded: two with-skill runs (e1, e2) that answered a message relayed from another session instead of doing the
  task, and changed nothing.
- Cost: a with-skill run used about 1.2-1.4x the input tokens of a run without on e1 and e2 (0.43M vs 0.30M, 0.54M vs
  0.45M on average).
- Earlier versions of the skill were measured with Haiku and model-graded checks, so they aren't compared here.
