# Path completion: decisions

Living record of the decisions for completing file paths in insert mode (blink.cmp's path source). Dates are when the
decision was made.

## Status

- Decided by the user (2026-10-25): the hybrid below (D163).
- Built (2026-10-25) on branch `path-completion`. `checks/completion_path.sh` passes, and fails on main's config (6 of
  its 10 assertions).

## Context

Refs: `B` = blink.cmp v1.10.2's `lua/blink/cmp/sources/path/`.

- The config set `get_cwd = function(_) return vim.fn.getcwd() end` (`nvim/lua/features/completion.lua:26-28` before
  this change), under a comment that sat in the lazydev provider. blink's default is the buffer's folder
  (`B/init.lua:26`).
- blink calls `get_cwd(context)` for every path it recognises, but uses the result only for a path that starts with
  `./` or `../` (`B/lib.lua:17-22`), and for one starting with `/` when `ignore_root_slash` is set. `~/`, `$VAR/` and
  absolute paths resolve on their own (`B/lib.lua:23-45`).
- A relative path with no `./` in front (`src/`, `docs/`) is never listed, whatever `get_cwd` returns: the text up to its
  first `/` ends in a letter and a slash, which blink skips as part of a URL (`prefix:match('%a/$')`, `B/lib.lua:32`).
  Seen in the sandbox with the config's options, calling `lib.dirname` on a buffer in `sub/`: `./` gave the cwd
  (`.../fix-path_probe`, not its `sub/`), `src/`, `see src/` and `"src/` gave `nil`, `./src/` the cwd's `src`.
- The context blink passes holds the line, the cursor (`cursor[2]` the byte column), the keyword bounds and the buffer
  (`blink/cmp/completion/trigger/context.lua:4-27`), so the folder can be chosen on the path being completed.

## D163: `./` and `../` from the file's folder, other relative paths from the project root (2026-10-25)

Decision:

- `./` and `../` resolve from the file's folder: the config drops its `get_cwd`, so blink's default applies. In a
  buffer that isn't a file, blink's default gives the cwd.
- Any other relative path (`src/`, `docs/`, quoted or not) resolves from the project root, `tools.root(buf)`
  (`nvim/lua/tools/init.lua:576-579`: the project's marker dir or git root, else the file's folder, else the cwd for a
  buffer that isn't a file). Since blink never lists those, the path provider is a wrapper of blink's source,
  `nvim/lua/features/completion_path.lua`: for such a path it lists the folder with blink's own item builder
  (`lib.candidates`, so items, sorting, trailing slashes and the preview are blink's); for anything else it calls
  blink's `get_completions` unchanged. Absolute paths, `~/`, `$VAR/` and URLs (any path holding `:`) stay blink's.
- The path being completed is the text before the cursor back to whitespace, a quote, a bracket, `=`, `,` or `;`. A
  folder that isn't there (`and/or` in prose) lists nothing.
- The comment that sat under the lazydev provider now describes the path provider.

Rejected:

- `get_cwd` alone choosing per path: blink only consults it for `./` and `../`, so `src/` would still list nothing.
- Changing blink (an upstream option to resolve bare relative paths from `get_cwd`): the user's choice to make;
  the wrapper can go once blink has one.
- A second provider beside blink's path source: two entries in `sources.default` and the menu's source column for one
  kind of item, where the wrapper keeps one `path` provider.

Known effects:

- The wrapper uses blink's `lib.candidates`, a module of its path source rather than its documented API; the lockfile
  pins blink 1.10.2, and `checks/completion_path.sh` fails if an update moves it.

## Tests

`tests/regress/checks/completion_path.sh` types into a headless nvim over its socket (a check body can't stay in
insert mode: `nvim_feedkeys` with `x!` waits for more keys) and reads the path items blink lists, in a buffer in `sub/`
of the fixture, whose root and `sub/` each hold a `src/` with a different file: `./`, `../`, `./src/`, `src/`, `"src/`,
an absolute path, a URL (nothing listed), then `src/` and `./` in a `nofile` buffer, and no error in `:messages`. On
main's config `./`, `../`, `./src/`, `src/`, `"src/` and the `nofile` buffer's `src/` fail.

## Cost

Per completion request: blink asks the path source on each trigger (`/`, `.`, a new keyword), not on each key typed
within the same keyword. Measured in the sandbox (`tests/regress/nv.sh nightly --headless`, a buffer on
`nvim/lua/features/completion.lua` in this repo, project root 3 levels up), 2000 calls per run, 3 runs per round,
5 rounds, µs per call (2026-10-25, `~/.cache/nvim-config/followups/bench/path_bench.lua`, not kept):

| call | runs (15) | median |
|---|---|---:|
| `project_dir` on `src/` (the wrapper's extra work: `tools.root`) | 208.8 to 263.0 | 224 |
| `project_dir` on `./` (returns at once; blink's source runs as before) | 0.28 to 0.32 | 0.29 |
| blink's own `lib.dirname` on `./`, for scale | 17.3 to 18.2 | 17.8 |

- A bare relative path costs about 0.22 ms more per request, in every run, 2.7% of D61's 8.3 ms frame; listing the
  folder is blink's async scan, as for any path. Every other request costs 0.3 µs more. Not acted on.
