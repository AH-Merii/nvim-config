-- What startup loads besides the registries: the modules that bring plugins, and the features (docs/
-- rearchitecture-decisions.md, "Step 5: features/").
--
-- A feature is a module under features/ that owns its plugins, keys, autocmds and options:
--
--   return {
--     plugins = { { src = "lewis6991/gitsigns.nvim", phase = "startup", setup = function() … end } }, -- app.Plugin
--     setup = function() … end, -- rows, needs, autocmds and options, run once at startup
--   }
--
-- setup() runs before any plugin loads, so what needs a plugin (a Snacks toggle, gitsigns' own table) goes in that
-- plugin's setup, or in a callback it gives M.at_very_lazy. The adapters and ui modules bring the plugins they
-- wrap the same way, as a `plugins` list. Their setup is their own: the plugin's setup calls it, or for lsp the
-- servers phase (lua/app/init.lua). lua/app/plugins.lua documents the plugin shape (app.Plugin).
local M = {}

-- Modules whose `plugins` are collected, before the features'. Each phase loads its plugins in this order, so the
-- theme and snacks load first.
M.adapters = { "ui.theme", "ui.icons", "ui.snacks", "ui.statusline", "lsp", "format.conform", "linting.nvim_lint", "keys.which_key" }

-- The features, in the order their setup() runs.
M.features = { "editing", "search", "git", "completion", "folds", "diagnostics", "treesitter", "windows", "files", "lua_dev", "lsp_status", "profiling" }

--- Every module's plugins, adapters first, as one list (app/plugins.lua).
---@return app.Plugin[]
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

local later = {} ---@type function[]?

--- Runs fn once the deferred phase (lua/app/) runs, at VeryLazy after the plugins that load then (snacks' toggles need
--- snacks), in the order given; fn given after that runs at once.
---@param fn function
function M.at_very_lazy(fn)
  if later then
    table.insert(later, fn)
  else
    fn()
  end
end

--- Runs the callbacks at_very_lazy was given, in order, once; app's deferred phase calls it. A callback that fails is
--- reported and the next one still runs, as when each had its own listener.
function M.very_lazy()
  local fns = later or {}
  later = nil
  for _, fn in ipairs(fns) do
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      vim.notify("features: a VeryLazy callback failed: " .. err, vim.log.levels.ERROR)
    end
  end
end

return M
