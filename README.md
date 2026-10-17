# nvim-config

My personal Neovim configuration, focused on LSP-driven development, with every language tool installed and run
through [mise](https://mise.jdx.dev). It supports Go, Rust, Python, Lua, TypeScript, C/C++ and more.

## What's in it

- **Language tools from mise.** Servers, formatters and linters are found per project (its `.venv`/`node_modules`,
  its mise config, then your global tools) and offered for install when missing. `:Tools` shows where each comes
  from.
- **Completion and LSP** with blink.cmp; formatting with conform.nvim on save, linting with nvim-lint.
- **Neovim's own UI for messages and the command line** (ui2), in place of noice.nvim.
- **snacks.nvim** for pickers, notifications, indent guides and smooth scrolling; the statusline from
  [neoblocks.nvim](https://github.com/AH-Merii/neoblocks.nvim); which-key, gitsigns, diffview, trouble, flash and
  treesitter.

## Requirements

- Neovim nightly (0.13-dev)
- [mise](https://mise.jdx.dev), for the language tools
- git, and a [Nerd Font](https://www.nerdfonts.com) for the icons

## Install

Run it alongside your own config, under its own name, with `NVIM_APPNAME`:

```sh
git clone https://github.com/AH-Merii/nvim-config ~/Projects/nvim-config
ln -s ~/Projects/nvim-config/nvim ~/.config/nvimn
NVIM_APPNAME=nvimn nvim
```

Plugins install on the first start. The leader key is `<space>`.

## Commands

| Command | What it does |
| --- | --- |
| `:Tools` | Each tool, where it comes from and its version; install, restart or rescan from there |
| `:Status` | Tooling status for the buffer: LSP, formatters, linters, treesitter |
| `:LspStatus`, `:LspInfo` | Attached language servers, briefly or in full |
| `:LspCapabilities`, `:LspDiagnostics` | A server's capabilities; a diagnostics summary |
| `:LspLog` | The LSP log, in a new tab |

## Common tasks

- **Update plugins:** `:Lazy update`.
- **Install a missing tool:** open a file it works on and accept the offer, or `:Tools install`. Update tools with
  `mise upgrade`.
- **Format and lint:** automatic, on save (conform.nvim) and on edits (nvim-lint).
- **Turn off install offers:** `vim.g.install_tools = "off"`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how the config is laid out and how to change it.
