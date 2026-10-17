-- Neovim's byte-compiled module cache, before the first require. lazy.nvim enables it too, in setup
-- (lazy/init.lua:61-70), but the features and the modules that bring plugins load before that.
vim.loader.enable()

-- The languages' variant filetypes and buffer options, then the tool resolver, before plugins: conform (BufWritePre) and
-- nvim-lint (BufReadPre) look tools up through it
require("lang").setup()
require("tools").setup()
-- Install prompts, :Tools and the statusline indicator; prompts need a UI and vim.g.install_tools ~= "off"
require("tools.ux").setup()
-- Options first: the key rows below read mapleader. Neovim's keys before lsp.buffer, whose grr replaces Neovim's
require("config.options")
require("keys.neovim")
-- Each language file's key rows (lua/lang/)
require("keys.languages")
require("lsp.buffer")
-- Each feature's rows, needs, autocmds and options (lua/features/)
require("features").setup()

require("core.lazy")
-- The features' VeryLazy callbacks, after lazy's own VeryLazy listener
require("features").after_lazy()
