# Agents

Before starting work in a new clone, run:

```sh
mise trust && mise run setup
```

It points git at `.githooks/`, so every push, with `git push` or `but push`, checks the formatting and scans for
secrets first; `git config core.hooksPath` prints `.githooks` once it's done. Don't skip the hook with `--no-verify`:
fix what it reports (`mise run fmt` formats the Lua).

How the config is laid out, how to change it and how to test it are in [CONTRIBUTING.md](CONTRIBUTING.md).
