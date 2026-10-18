-- Neovim's byte-compiled module cache, before the first require, so every module, app's included, loads from it
vim.loader.enable()

-- Startup, in phases (lua/app/)
require("app").start()
