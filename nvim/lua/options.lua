-- Editor-wide options and the leaders, the first startup phase (lua/app/): every <leader> key row needs mapleader

-- 🏁 Leader Keys
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Remote-plugin hosts: no installed plugin ships an rplugin/ dir, and looking for a python3 host when the first Python
-- buffer opens ($VIMRUNTIME/ftplugin/python.vim asks has('python3')) costs about 55 ms
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0

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
-- Partial commands in the statusline. neoblocks' messages module owns it once it loads (lua/ui/statusline.lua): "last"
-- while its hook draws them, "statusline" otherwise. This covers the time before, and a session where neoblocks
-- isn't installed, whose default 'statusline' draws %S only with "statusline" (Neovim's default is "last")
vim.o.showcmdloc = "statusline"

-- Floats that set no border of their own (LSP hover and signature help, diagnostic floats, ui2's
-- message window) get a rounded one. blink, gitsigns and snacks also fall back to it where this
-- config sets no border (blink's signature window).
vim.o.winborder = "rounded"

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
