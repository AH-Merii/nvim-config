-- What startup loads besides the registries: the modules that bring plugins, and the features (docs/
-- rearchitecture-decisions.md, "Step 5: features/").
--
-- A feature is a module under features/ that owns its plugins, keys, autocmds and options:
--
--   return {
--     plugins = { { "lewis6991/gitsigns.nvim", config = function() … end } }, -- lazy.nvim specs
--     setup = function() … end, -- rows, needs, autocmds and options, run once at startup
--   }
--
-- setup() runs before any plugin loads, so what needs a plugin (a Snacks toggle, gitsigns' own table) goes in that
-- plugin's spec, or in a VeryLazy callback the feature makes. The adapters and ui modules bring the plugins they
-- wrap the same way, as a `plugins` list; their setup is their own and the plugin's config calls it.
local M = {}

-- Modules whose `plugins` are collected, before the features'. Their specs come first, so a feature's spec for the
-- same plugin (trouble's snacks picker actions) merges over theirs, as lazy merges later fragments.
M.adapters = { "ui.theme", "ui.icons", "ui.snacks", "ui.statusline", "lsp", "format.conform", "linting.nvim_lint", "keys.which_key" }

-- The features, in the order their setup() runs.
M.features = {}

--- Every module's plugins, adapters first, as one list of lazy.nvim specs (core/lazy.lua).
---@return LazySpec[]
function M.plugins()
  local specs = {}
  for _, name in ipairs(M.adapters) do
    vim.list_extend(specs, require(name).plugins or {})
  end
  for _, name in ipairs(M.features) do
    vim.list_extend(specs, require("features." .. name).plugins or {})
  end
  return specs
end

--- Runs each feature's setup(), in order.
function M.setup()
  for _, name in ipairs(M.features) do
    local feature = require("features." .. name)
    if feature.setup then
      feature.setup()
    end
  end
end

return M
