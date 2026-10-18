-- Lua and Neovim config development: lazydev's completion and types for Neovim's and the plugins' Lua
local M = {}

M.plugins = {
  -- after the first screen; it attaches to the Lua servers already running (lazydev/buf.lua:45-50), and blink's
  -- lazydev source loads it earlier when it is required first (lua/app/plugins.lua)
  { src = "folke/lazydev.nvim", setup = function() require("lazydev").setup({}) end },
}

function M.setup()
  -- lazydev on for every Lua project; it is also lazydev's default when unset (lazydev/config.lua:25)
  vim.g.lazydev_enabled = true

  -- Debug helpers for :lua, once snacks is loaded: dd(...) inspects its arguments, bt() shows a backtrace
  require("features").at_very_lazy(function()
    _G.dd = function(...) Snacks.debug.inspect(...) end
    _G.bt = function() Snacks.debug.backtrace() end
  end)

  local keys = require("keys")
  -- Run the Lua being written: its line or selection, or the whole file
  keys.language("lua", { silent = false })({
    { "<leader>!", ":.lua<CR>", label = "Execute current line" },
    { "<leader>!", ":lua<CR>", mode = "x", label = "Execute current selection" },
    { "<leader>%", "<cmd>source %<CR>", label = "Source current file" },
  })
  keys.language("vim", { silent = false })({
    { "<leader>%", "<cmd>source %<CR>", label = "Source current file" },
  })
end

return M
