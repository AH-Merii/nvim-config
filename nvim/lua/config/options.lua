-- 🏁 Leader Keys
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Enable Lazydev for vim globals
vim.g.lazydev_enabled = true

-- ⚙️ General Settings
vim.opt.termguicolors = true
vim.opt.fileencoding = "utf-8"
vim.opt.confirm = true -- Confirm before exiting modified buffer
vim.opt.timeoutlen = 500 -- How much time nvim waits for the next command
vim.opt.jumpoptions = "view" -- Restores both cursor and window view (scroll, folds, etc.) between jumps
vim.opt.autoread = true -- Auto-reload files
vim.opt.inccommand = "split" -- Live preview for substitutions %s/text/new_text/

-- 💾 Files, Backup & Undo
vim.opt.undofile = true

-- 📋 Clipboard & Mouse
vim.opt.clipboard = "unnamedplus"
vim.opt.mouse = "a" -- enable mouse in (a)ll modes

-- 🧭 UI & Appearance
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.numberwidth = 4
vim.opt.scrolloff = 999
vim.opt.sidescrolloff = 8
vim.opt.virtualedit = "block" -- Block mode cursor positioning
vim.opt.list = true
vim.opt.listchars = {
  space = "·",
  tab = "->",
  trail = "󰄛",
  eol = "¶",
  extends = "»",
  precedes = "«",
  nbsp = "󰛗",
  lead = ".",
}

vim.opt.cmdheight = 0
vim.o.showcmd = true
vim.o.showcmdloc = "statusline" -- show partial commands in the statusline

-- Floats that set no border of their own (LSP hover and signature help, diagnostic floats, ui2's
-- message window) get a rounded one. blink, gitsigns and snacks also fall back to it where this
-- config sets no border (blink's signature window). lazy.nvim's backdrop float would get
-- one too, but it only opens when Normal has a background, and onedark is transparent here.
vim.o.winborder = "rounded"

-- Neovim's built-in message and cmdline UI (:h ui2), enabled before plugins so it sees every message.
-- config.ui2 then hooks it to behave like noice did: ':' in a popup near the top, messages as
-- snacks.notifier toasts, long output in a split (lua/config/ui2/). Until snacks is set up, and for
-- anything the hooks pass on, these targets apply: messages go to the msg window (bottom-right float,
-- cleared after the 'messagesopt' timeout) and output of a typed command to the cmdline. g< opens the
-- pager with the whole history. Does nothing headless (no UI attached).
require("vim._core.ui2").enable({
  msg = { targets = { default = "msg", typed_cmd = "cmd" } },
})
require("config.ui2").setup()

-- make the hidden chars foreground color more subtle
vim.cmd([[
highlight NonText guifg=#cccccc ctermfg=lightgray
highlight SpecialKey guifg=#cccccc ctermfg=lightgray
]])

-- 󰞷 Editing & Indentation
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.smartindent = true
vim.opt.breakindent = true
vim.opt.wrap = false

--  Search
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.ignorecase = true
vim.opt.smartcase = true

--  Splits & Windows
vim.opt.splitbelow = true
vim.opt.splitright = true

-- 🗂 Filetype Detection
vim.filetype.add({
  extension = { env = "dotenv" },
  filename = { [".env"] = "dotenv", ["env"] = "dotenv" },
  pattern = {
    ["[jt]sconfig.*.json"] = "jsonc",
    ["%.env%.[%w_.-]+"] = "dotenv",
  },
})
