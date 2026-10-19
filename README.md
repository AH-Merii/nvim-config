# nvim-config

My personal Neovim configuration, focused on LSP-driven development, with every language tool installed and run
through [mise](https://mise.jdx.dev). It supports Go, Rust, Python, Lua, TypeScript, C/C++ and more:
[docs/languages.md](docs/languages.md) lists every language and its tools.

## What's in it

- **Language tools from mise.** Servers, formatters and linters are found per project (its `.venv`/`node_modules`,
  its mise config, then your global tools) and offered for install when missing. `:Tools` shows where each comes
  from.
- **Completion and LSP** with blink.cmp; formatting with conform.nvim on save, linting with nvim-lint.
- **Neovim's own UI for messages and the command line** (ui2), with noice.nvim's look from
  [neoblocks.nvim](https://github.com/AH-Merii/neoblocks.nvim)'s messages module: `:` in a popup near the top,
  messages as toasts, long output in a split and a message history (`<leader>n`).
- **Keys that act where they work.** which-key lists a key only where it does something; elsewhere a leader key or
  an LSP gr* key says what is missing, such as the method no server supports.
- **snacks.nvim** for pickers, notifications, indent guides and smooth scrolling; the statusline from neoblocks.nvim;
  which-key, gitsigns, diffview, trouble, flash and treesitter.
- **Treesitter parsers on demand.** Nothing installs at startup: opening a file installs its language's parser and
  the languages its injections name, nvim-treesitter's copy even where Neovim bundles one. `:Tools` lists them.

## Requirements

- Neovim nightly (0.13-dev)
- [mise](https://mise.jdx.dev), for the language tools
- git, and a [Nerd Font](https://www.nerdfonts.com) for the icons
- for treesitter parsers: the tree-sitter CLI (offered for install with mise when a parser needs it), a C compiler,
  curl and tar

## Install

Run it alongside your own config, under its own name, with `NVIM_APPNAME`:

```sh
git clone https://github.com/AH-Merii/nvim-config ~/Projects/nvim-config
ln -s ~/Projects/nvim-config/nvim ~/.config/nvimn
NVIM_APPNAME=nvimn nvim
```

The first start clones the plugins, at the revisions `nvim/nvim-pack-lock.json` pins, with Neovim's own plugin
manager (vim.pack). Coming from a lazy.nvim-era install, start from an empty data directory: move
`~/.local/share/<appname>` aside first. Its lazy.nvim plugins aren't read, and its treesitter queries link into
lazy's checkout, so they aren't reused either. The leader key is `<space>`.

## Commands

| Command | What it does |
| --- | --- |
| `:Tools` | Each tool, where it comes from and its version; install, restart or rescan from there |
| `:Status` | Tooling status for the buffer: LSP, formatters, linters, treesitter |
| `:LspStatus`, `:LspInfo` | Attached language servers, briefly or in full |
| `:LspCapabilities`, `:LspDiagnostics` | A server's capabilities; a diagnostics summary |
| `:LspLog` | The LSP log, in a new tab |

## Common tasks

- **Update plugins:** `:packupdate`, then `:write` in the list of changes to apply them (`:quit` to cancel).
  `:packupdate ++lockfile` puts every plugin back at the lockfile's revision.
- **Install a missing tool:** open a file it works on and accept the offer, or `:Tools install`. It goes into
  `~/.config/mise/conf.d/nvim-config.toml`, a global mise file of the config's own, so your `config.toml` is left
  alone; when your `config.toml` pins a version that isn't installed, that version is installed and no file changes.
  Update tools with `mise upgrade`; remove one with
  `mise unuse --path ~/.config/mise/conf.d/nvim-config.toml <tool>`. In a project you can install it for that
  project only instead: it goes into the project's `mise.local.toml`, which is added to the repo's `.gitignore`
  unless git already ignores or tracks it.
- **Format and lint:** automatic, on save (conform.nvim) and on edits (nvim-lint).
- **Turn off install offers:** `vim.g.install_tools = "off"`. It stops parser installs too.
- **A parser that failed to install:** `:Tools`, pick its row, then *Retry the install*; *Update* there updates an
  installed one.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how the config is laid out and how to change it.
