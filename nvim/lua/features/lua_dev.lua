-- Lua and Neovim config development: lazydev's completion and types for Neovim's and the plugins' Lua
local M = {}

M.plugins = {
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {},
  },
}

function M.setup()
  -- Debug helpers for :lua, once snacks is loaded: dd(...) inspects its arguments, bt() shows a backtrace
  require("features").at_very_lazy(function()
    _G.dd = function(...) Snacks.debug.inspect(...) end
    _G.bt = function() Snacks.debug.backtrace() end
  end)
end

return M
