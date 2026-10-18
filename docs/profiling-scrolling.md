# Profiling scrolling

Why scrolling in `nvimn` felt sluggish, measured on 2026-10-14, and what was changed to fix it while keeping every
plugin's features (see "Fixes applied").

## Setup

- Neovim nightly v0.13.0-dev-1808+g561857c4a8 through `nvimn`, on `nvim/lua/core/lsp.lua` (247 lines, lua_ls
  attached, 33 diagnostics).
- A normal Ghostty window on the main display (DP-1, 3840x2160 at 120 Hz, scale 1.25), nvim at 115x62. Keys were fed
  inside nvim (`nvim_input` from a timer, started over `--listen` RPC), so no keyboard injection.
- Held keys repeat at 25 Hz, niri's default; `~/.config/niri/config.kdl` sets no `repeat-rate`.
- The probe (`~/.cache/nvim-config/probe/scroll.lua`) records per key:
  - **cpu**: nvim server CPU (`getrusage`) from the key until it next went idle, so deferred work such as
    animations counts;
  - **lag**: time from the key being due to nvim taking it; it grows when keys queue up;
  - **settle**: time from the key to the last `WinScrolled` before the next key, i.e. when the view stops moving;
  - **frames**: `WinScrolled` events per key.
- Each run starts at the top (`gg`) or bottom (`G`). An early batch of runs didn't and walked off the end of the
  file, so its falling numbers were bogus; those runs are discarded.

## Results

Cumulative: each row also has everything above it switched off (means; `j` is 150 keys held, `C-d`/`C-u` 6 presses
at 2 per second).

| switched off                    | `j` cpu/key | `C-d` busy | `C-u` busy | `C-d` settle mean / p90 |
| ------------------------------- | ----------- | ---------- | ---------- | ----------------------- |
| nothing (base)                  | 10.0 ms     | 38%        | 45%        | 224 / 321 ms            |
| nvim-highlight-colors           | 7.5 ms      | 30%        | 27%        | 192 / 228 ms            |
| + snacks indent scope animation | 7.9 ms      | 34%        | 20%        | 228 / 398 ms            |
| + statuscolumn                  | 6.3 ms      | 28%        | 13%        | 202 / 287 ms            |
| + lualine                       | 4.5 ms      | 12%        | 14%        | 177 / 178 ms            |
| + tiny-inline-diagnostic        | 4.4 ms      | 25%        | 11%        | 205 / 290 ms            |

"busy" is nvim's CPU as a share of wall time over the run. With 6 presses a run, the `C-d` columns are noisy (one
slow press moves p90).

Other measurements:

- **Held `j` doesn't queue.** Lag stays at p90 0.3 ms at 25 Hz, so `j` keeps up; it just costs about 10 ms of CPU
  per line.
- **`C-d`/`C-u` are animated by snacks scroll.** Its default is 200 ms in 10 ms steps
  (`snacks.nvim/lua/snacks/scroll.lua:28-31`), about 29 redraws per press. With the config as is, presses settle
  after 224-232 ms on average, and p90 is 321-337 ms: slow frames stretch the animation past 200 ms. With the cheap
  config (row "+ lualine") they settle in a steady 177 ms.
- **Without the animation, a jump is expensive.** `Snacks.scroll.disable()` makes a `C-d` settle in 3.5 ms, but
  each one costs 36-40 ms of CPU.
  - Turning off snacks indent's scope animation alone cuts that to 18.6 ms. After every jump, the scope animation
    redraws for up to 500 ms (`snacks.nvim/lua/snacks/indent.lua:41-49`).
  - Turning off indent entirely cuts it to 14.7 ms.
- **The snacks profiler (`<leader>Pp`), 150 held `j` presses.** It inflates code that makes many small calls, so
  read it for ranking only:
  - snacks.nvim 711 ms, of which `snacks.statuscolumn.get` is 461 ms (13 373 calls, about 89 per key);
  - nvim-highlight-colors 659 ms, of which `highlight_with_lsp` is 259 ms and `get_positions_by_regex` 151 ms;
  - lualine 317 ms, with the statusline drawn 159 times;
  - tiny-inline-diagnostic 124 ms.
- **tiny-inline-diagnostic is cheap.** The profile that started this (`extmarks.clear` 9.6 ms over 259 calls) is
  about 0.1 ms per cursor move. Turning it off alone changed nothing measurable.

## Causes, biggest first

1. **nvim-highlight-colors re-renders on every scroll.** It hooks `WinScrolled` (`nvim-highlight-colors/init.lua:298-304`).
   With `scrolloff = 999` (`nvim/lua/options.lua:34`), every `j` scrolls the window, so each `j` does all of
   this:
   - re-scans the visible rows with its regexes;
   - calls `vim.version()` once per LSP client (`utils.lua:206`). On nightly that builds the whole `api_info()`
     table (`runtime/lua/vim/version.lua:515`) and costs 1.72 ms per call, measured with 20 calls in the running
     nvim;
   - sends a `textDocument/documentColor` request.

   `lsp.lua` ends up with no color marks at all: 0 extmarks in its namespace. Nightly also has built-in LSP
   document colors (a `nvim.lsp.document_color` namespace exists in the same buffer). Cost: about 2.5 ms per `j`,
   and a third of the busy time during `C-d`.
2. **The smooth scroll animation is the delay you feel on `C-d`/`C-u`.** The view only arrives after 200 ms by
   design. Slow frames from the costs below stretch it further, to 320+ ms for one press in ten.
3. **lualine redraws on every cursor move.** About 1.8 ms per `j`.
4. **The snacks statuscolumn is evaluated for every visible row on every move.** That's because `relativenumber`
   changes all of them. About 1.2 ms per `j`.
5. **snacks indent's scope animation.** It adds up to 500 ms of redraws after each jump, about 18 ms of CPU per
   `C-d`.

What's left with all of these off is about 4.4 ms per `j`. That's treesitter, the rest of snacks
(words, scope, indent guides) and nvim's own redraw. Turning those off one at a time didn't move it beyond noise.

## Fixes applied

Each keeps the plugin's feature; one commit each on `perf/scrolling-profile`, with a regression check in
`tests/regress/checks/`.

| change | what you keep | what differs |
| --- | --- | --- |
| nvim-highlight-colors: language server colors come from the built-in `vim.lsp.document_color`; color lookups and each line's scan are cached (`plugins/extras.lua`) | every color preview, drawn the same way: the symbol at the line's end in the color | server colors redraw on edits, not on scroll (the built-in's rule) |
| lualine: no rebuild on `CursorMoved`; location and progress are statusline expressions; searchcount refreshes on moves while a search is highlighted (`plugins/lualine.lua`) | the same text: `11:4`, `Top`/`Bot`/`11%`, `[2/3]` | none seen |
| snacks scroll: `outCubic` over 120 ms instead of linear over 200 ms (`plugins/snacks.lua`) | smooth scrolling | it starts fast and eases in: half the distance in about 19 ms, settled at about 75 ms |
| snacks indent: the scope animation takes 150 ms instead of 500, and plays only after a key pressed on its own (`plugins/snacks.lua`) | the animation on single moves and jumps | while keys repeat (a held `j` or `C-d`), the scope is drawn at once |
| snacks statuscolumn: rows are cached without their number for 200 ms; the number is put back in each time (`plugins/snacks.lua`) | the same column: signs, marks, folds, numbers as snacks draws them | a new sign or mark shows up to 200 ms late, on the next redraw (snacks: 50 ms) |

Before and after, on `core/lsp.lua` in a 71x38 hidden lab window: CPU numbers there matched the main display's
within 1 ms (10.8 vs 10.0 per `j`), but its half page is 19 lines, not 31. Means of two runs; "half" and "settled"
are timed from the key to the `WinScrolled` events of the animation.

| step | held `j` cpu/key | `C-d`/`C-u` busy | `C-d` half / settled |
| --- | --- | --- | --- |
| before | 9.6 ms | 25-31% | 85 / 180-207 ms |
| + highlight-colors | 8.35 ms | 21% | |
| + lualine | 7.55 ms | 18.5% | 83 / 178 ms |
| + scroll and indent timing | 6.3 ms | 13% | 19 / 75 ms |
| + scope animation only after a key on its own | 5.0 ms | 12-13% | |
| + statuscolumn cache | 4.3 ms | 12% | 19 / 76 ms |

Held `j` costs 55% less CPU, and `C-d`/`C-u` are half done in a quarter of the time. For comparison, with
highlight-colors off entirely `j` measured 8.5 ms against 8.2-8.5 with its fix, and with no statuscolumn 3.7 ms
against 4.3.

Easings tried for `C-d` (half / settled): linear 100 ms 48 / 94; outQuad 150 ms 38 / 129; outCubic 150 ms 30 / 104;
outCubic 120 ms 19 / 79; outQuart 150 ms 21 / 87; outExpo 150 ms 11 / 77. outExpo covers almost the whole distance
in its first frame, which reads as a jump; outCubic at 120 ms still glides. These timings come from the hidden lab,
so the choice wasn't checked by eye on the display.

Left as is:

- **`scrolloff = 999`.** It makes every `j` a scroll, which is what fed the `WinScrolled` costs above; with those
  fixed, it's a feel choice.
- **tiny-inline-diagnostic.** About 0.1 ms per move.
- **What remains, about 4.3 ms per `j`.** snacks indent guides (about 1.3 ms), treesitter (about 1 ms), the
  statuscolumn's per-row call (about 0.6 ms) and nvim's redraw.

## Not covered

- **Smoothness on screen.** These numbers are nvim CPU. Ghostty's own cost and frame pacing on the display weren't
  measured.
- **Other files.** Bigger files and other filetypes (more treesitter work, more color matches) will cost more.
- **Mouse wheel.** It was only measured in the hidden lab (17 ms CPU per wheel step, all features on). snacks scroll
  doesn't animate it (`snacks/scroll.lua:280-286`).
