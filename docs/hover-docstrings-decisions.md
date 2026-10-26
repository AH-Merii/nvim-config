# Hover docstrings: decisions

Living record of the decisions for cleaning the Python docstrings in pyrefly's hover (`K`) before Neovim draws
them. The float itself (render-markdown, its height, no spell or linting) is in
[hover-decisions.md](hover-decisions.md).
Dates are when the decision was made.

## Status

- Decided by the user (2026-10-26): D166, the markdown clean-up, tested on pydantic, torch, polars, fastapi,
  huggingface_hub and transformers.
- Built (2026-10-26) on branch `hover-docstrings`. The checks under "Tests" pass, and each fails on a do-nothing
  clean-up.

## Context

Runtime refs: `R` = nightly runtime (NVIM v0.13.0-dev-1895+g0851e7dabe), `RM` = render-markdown.nvim at 8e87953,
`P` = pyrefly at tag 1.4.0 (<https://github.com/facebook/pyrefly/tree/1.4.0>).

A study of 68 pyrefly 1.4.0 hovers from pydantic 2.14.1, torch 2.14.1+cpu, polars 2.1.0, fastapi 0.162.0,
huggingface_hub 2.3.0 and transformers 5.20.2 (50 with a docstring) found what renders wrong and why. The corpus,
its index and the findings are kept outside the repo, in `~/.cache/nvim-config/hover-docstrings/` on the machine
that made them; the code cites them as "FINDINGS §1.x" and "R<n>", listed below.

- pyrefly rewrites every docstring before sending it (`P/crates/pyrefly_python/src/docstring.rs`): each leading
  space outside its own fences becomes `&nbsp;` (`format_non_code_line`), a leading `>` is dropped, a doctest's
  `>>>` lines go in a ```` ```python ```` fence closed at the first line that isn't a prompt, so the output lands after
  it, a line ending `::` loses a colon and the more indented block after it goes in a bare ```` ``` ```` fence, and
  every line ends in a hard break (`finish`: lines joined with `"  \n"`). It doesn't know markdown fences, so an
  author's fence gets `&nbsp;` inside it and, around a doctest, a second fence.
- The hover's value is the signature fence, `---`, the docstring, maybe `---` and `**Parameter `x`**`, then the
  `Go to [...](file://...)` links (`P/pyrefly/lib/lsp/wasm/hover.rs`, `HoverValue::format`).
- Neovim then joins the contents (`R/lua/vim/lsp/buf.lua`, `M.hover`: `convert_input_to_markdown_lines`), turns any
  line that looks like a thematic break into a rule and collapses blank lines (`R/lua/vim/lsp/util.lua`,
  `_normalize_markdown`), and render-markdown sets `conceallevel` 3, which hides a concealed `&nbsp;` entirely
  (`RM/lua/render-markdown/settings.lua`, `R/doc/options.txt`, `'conceallevel'`). So the indent of every argument
  list disappears, and `----------` under a NumPy section title becomes a rule.

## D166: pyrefly's hover docstring is rewritten as markdown before Neovim draws it (2026-10-26)

**Decision.** `features/hover_docstring/` takes pyrefly's hover markdown and returns it with the docstring cleaned;
the signature, the parameter section and the `Go to` links stay as they are. `features/hover.lua` runs it on every
markdown hover result from a client named `pyrefly`, before the handler that asked for it.

The rules, in the order the findings ranked them by how many hovers they touch. Each is commented in the code with
its number.

| FINDINGS | construct (pyrefly's text) | becomes |
| --- | --- | --- |
| §1.1 | `&nbsp;` indent, 2180 lines in 42 hovers | the structure below; indent left over is U+00A0, never spaces (R1) |
| §1.3 | doctest output after pyrefly's closing fence | moved into the fence, up to the next blank line, dedented; the next doctest joins the same fence |
| §1.4 | Google section (`Args:`, `Returns:`, ...) and its `&nbsp;` items | `**Args:**` over `` - `name` (type): desc `` entries, wrapped lines two spaces in |
| §1.5 | reST directive (`.. note:` + fenced body, `.. versionchanged:: 1.24` + indented body) | a callout (`> [!NOTE] Changed in 1.24`), `math` a `latex` fence, `list-table` a list, `method`/`function` the signature as code, others `**Engine support:** in-memory` |
| §1.6 | an author's fence indented with `&nbsp;` | dedented into a real fence, `{title="a.py"}` dropped |
| §1.7 | `&nbsp;` inside an author's fence | spaces |
| §1.8 | a doctest inside an author's fence, with pyrefly's fences inside it | pyrefly's fences dropped; the author's closer stays a closer |
| §1.9 | NumPy title over `-----` (which Neovim draws as a rule) | `**Parameters**`, underline dropped, `- **name** : type` entries |
| §1.11 | `[!WARNING]` whose `>` pyrefly dropped | `> [!WARNING]`, its lines quoted up to the next blank line |
| §1.12 | Hugging Face's `<Tip>` / `<Tip warning={true}>` ... `</Tip>` | `> [!TIP]` / `> [!WARNING]` callout |
| §1.13 | MkDocs `!!! type "Title"` / `???` | `> [!TYPE] Title`, unknown types NOTE |
| §1.10 | `[...]` in prose that is no link (`Json[T]`): a shortcut link whose brackets are concealed | `\[...\]`; links, `[t][r]`, doc-builder ``[`X`]`` and `[!X]` kept |
| §1.14 | `__dunder__` in prose, drawn bold | `` `__dunder__` `` |
| §1.15 | reST link `` `text <url>`__ `` | `[text](url)` |
| §1.2 | `"  "` hard break on every line | dropped |

Left as they are (FINDINGS §2): pyrefly's signature fence and its `---`, its doctest fences, authors' column-0
fences (but §1.7 and §1.8), markdown links, ``` ``double backticks`` ```, `*optional*`, bold, doc-builder refs,
MkDocs autorefs, fastapi's `## Example`, column-0 lists, the `Go to` footer.

How it is built: two linear steps. `fences.lua` turns the docstring's lines into items, every fence resolved first,
so no later rule rewrites code (R2). `blocks.lua` writes the items out by indent: a section, an entry or a callout
writes its body one level in, so a `!!! note` inside an argument becomes a callout inside that list item; it runs
`inline.lua` on each prose line. `init.lua` finds the docstring in the hover and gives the input back unchanged when
the output's fences don't balance (R5) or anything raises. It never writes a `---`, `***` or `___` line (R4): the
NumPy underline is dropped, not kept.

**Skipped.**

- §1.2's second half, joining a paragraph's lines so they reflow: lines that carry structure would merge (R6), and
  the float wraps long lines anyway.
- §1.16 (`<Null>` shown raw, `.. math:` already fenced, pydantic's relative links): they read fine.
- Neovim's own changes (blank lines dropped after a line starting `@p`/`@r`, such as fastapi's `@app.get`, and blank
  lines collapsed inside fences): they happen after the clean-up, in `R/lua/vim/lsp/util.lua`.
- A reST link split over two lines (polars `Expr.over`): the inline rules see one line at a time.
- A `::` block inside an author's fence: pyrefly's bare fence there can't be told from the author's closer, so the
  fences can come out wrong; none is in the corpus.

**Where it hooks in.** `vim.lsp.buf.hover` sends its request with its own callback
(`R/lua/vim/lsp/buf.lua`, `M.hover`: `lsp.buf_request_all(0, 'textDocument/hover', ...)`), so a
`vim.lsp.handlers['textDocument/hover']` override is never called, and there is no middleware. `features/hover.lua`
wraps the `request` method of each pyrefly client once, at `LspAttach`: a hover request's handler gets the result
with `contents.value` cleaned, and everything after it is Neovim's own (several clients, the range highlight,
focusing with a second `K`, `fit()`, render-markdown).

- Rejected: a `K` action that requests the hover and opens the float itself. It copies the 110 lines of `M.hover`,
  and `K` is a key row in `lsp/buffer.lua` with its own echo rules (D165).
- Rejected: wrapping `vim.lsp.util.convert_input_to_markdown_lines`. It doesn't know which server answered, and
  signature help and other callers go through it.

**Only pyrefly.** The rules undo what pyrefly's `docstring.rs` does, and the docstring is found by the shape of
pyrefly's `hover.rs` (a ```` ```python ```` signature fence, then `---`). Python's other servers format docstrings
their own way, so the clean-up would guess at their text; the config names pyrefly and ruff for Python, and ruff
has no hover. Another server is added by naming its module in `CLEAN` (`features/hover.lua`). Rejected: any Python
server's markdown hover, for that reason.

**Where it lives.** `nvim/lua/features/hover_docstring/` (`init.lua`, `fences.lua`, `blocks.lua`, `inline.lua`),
beside the feature that uses it, as `features/completion_path.lua` sits beside `features/completion.lua`: a module
that serves one feature, named after it. A directory because it is about 900 lines in three steps. It is pure (a
string in, a string out, no plugins), so the unit tier tests it directly.

- Rejected: a top-level directory (`lua/docstring/`). Those are subsystems that several modules use (`tools/`,
  `lsp/`, `format/`); this serves the hover float only.
- Rejected: `lsp/`. It holds how servers are started and what they give a buffer (`lsp/buffer.lua`,
  `lsp/pyrefly.lua`); the clean-up changes only what the hover float shows, which `features/hover.lua` owns.
- Rejected: turning `features/hover.lua` into `features/hover/init.lua` with the clean-up under it. Tidier, but it
  moves a file that docs, checks and `areas.map` name, for no change in behaviour.

**Cost.** Only on a pyrefly hover, once per `K` (and the second `K` reuses the float). Measured headless on the
corpus, 50 runs each after one warm-up (`nvim --clean --headless -l`, `vim.uv.hrtime`):

| hover | size | first run | median | max |
| --- | --- | --- | --- | --- |
| transformers `TrainingArguments`, the largest | 61,547 bytes, 575 lines | 5.75 ms | 2.85 ms | 3.91 ms |
| polars `DataFrame.filter` | 6,671 bytes | 0.29 ms | 0.18 ms | 0.74 ms |
| torch `cat` | 2,826 bytes | 0.30 ms | 0.08 ms | 0.49 ms |

The first run includes requiring the modules. Nothing runs at startup or per keystroke.

## Tests

- `tests/unit/hover_docstring_test.lua`: one case per rule above, each on an excerpt of a real hover in
  `tests/unit/fixtures/hover_docstring/` (its first line names the library, version and corpus lines), the
  section-2 constructs left as they are, a fence that never closes giving the input back, and a hover with no
  docstring or not shaped like pyrefly's coming back unchanged. With the corpus on the machine, every corpus hover
  is also checked: treesitter's markdown parser reads it with no error and every fence closed, no `&nbsp;` is left
  outside code, the `Go to` line is outside any fence, and it has no more rule lines than the input. Without the
  corpus (CI) that case says it skipped.
- `tests/regress/checks/hover_docstring.lua`: `K` with a fake server named `pyrefly` shows the cleaned float (an
  entry, a quoted callout, no `&nbsp;`, the footer kept); the same hover from a server with another name is left as
  it came.

Every unit case fails on a do-nothing clean-up (returns its input), and the regress check fails with `CLEAN = {}`.
Sibling wrong versions, each with one change, fail the case named: no doctest merge (§1.3), leftover indent as spaces
(§1.1), no blank line after a callout (§1.5 in an entry), pyrefly's inner doctest fence kept (§1.8 and the corpus
check), brackets not escaped (§1.10), no fallback on an unclosed fence (R5), a wrapped entry line made a new entry or
directive options kept (§1.5 method).
