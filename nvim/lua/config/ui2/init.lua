-- noice-like behaviour on top of Neovim's built-in ui2 (:h ui2):
-- - cmdline.lua: ':' and input() in a command palette popup, '/' and '?' stay at the bottom;
-- - messages.lua: messages as snacks.notifier toasts, long output in a split;
-- - history.lua: a message history picker (<leader>n).
-- ui2 is private (vim._core); each module checks the internals it hooks and falls back to plain ui2.
local M = {}

--- Call right after require("vim._core.ui2").enable(). ui.cmd and ui.msg only exist once enable() ran
--- with a UI attached (R/lua/vim/_core/ui2.lua:217-219,234-235), so headless this installs nothing.
function M.setup()
  local ok, ui = pcall(require, "vim._core.ui2")
  if not (ok and type(ui) == "table" and ui.cmd and ui.msg) then
    return
  end
  for _, name in ipairs({ "cmdline", "messages" }) do
    -- setup() returns false when a ui2 internal it hooks is missing (renamed in a nightly): say so too.
    local loaded, res = pcall(function() return require("config.ui2." .. name).setup(ui) end)
    if not loaded or res == false then
      local why = loaded and "a ui2 internal it hooks is missing, using plain ui2" or tostring(res)
      vim.schedule(function() vim.notify(("config.ui2.%s: %s"):format(name, why), vim.log.levels.WARN) end)
    end
  end
end

return M
