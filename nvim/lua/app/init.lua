-- Startup, as named phases in a fixed order (docs/rearchitecture-decisions.md, "Step 6a: app/"). init.lua calls
-- M.start() once. Each phase runs once, in the order of M.phases, and is timed: M.times() lists the phases that ran,
-- with their milliseconds (`:lua =require("app").times()`).
local M = {}

---@class app.Phase
---@field name string
---@field at? string the User event it waits for; without one it runs inside start()
---@field run fun()

---@type app.Phase[]
M.phases = {
  {
    -- The leaders and editor-wide options first: every <leader> key row needs mapleader. Then Neovim's built-in
    -- message and cmdline UI (:h ui2), before any message can be lost. ui.messages hooks it to behave like noice did:
    -- ':' in a popup near the top, messages as snacks.notifier toasts, long output in a split (lua/ui/messages/).
    -- Until snacks is set up, and for anything the hooks pass on, these targets apply: messages go to the msg window
    -- (bottom-right float, cleared after the 'messagesopt' timeout) and output of a typed command to the cmdline. g<
    -- opens the pager with the whole history. Does nothing headless (no UI attached).
    name = "options",
    run = function()
      require("options")
      require("vim._core.ui2").enable({
        msg = { targets = { default = "msg", typed_cmd = "cmd" } },
      })
      require("ui.messages").setup()
    end,
  },
  {
    -- Plain data, no plugin loaded: Neovim's keys as rows, before lsp.buffer, whose grr replaces Neovim's; each
    -- language file's key rows (lua/lang/); then each feature's rows, needs, autocmds and options (lua/features/)
    name = "registries",
    run = function()
      require("keys.neovim")
      require("keys.languages")
      require("lsp.buffer")
      require("features").setup()
    end,
  },
  {
    -- The languages' variant filetypes and buffer options, then the tool resolver and its prompts and :Tools, before
    -- plugins: conform (BufWritePre) and nvim-lint (BufReadPre) look tools up through it
    name = "tools",
    run = function()
      -- .env files are dotenv, which no language file declares; the runtime would name them env
      vim.filetype.add({
        extension = { env = "dotenv" },
        filename = { [".env"] = "dotenv", ["env"] = "dotenv" },
        pattern = { ["%.env%.[%w_.-]+"] = "dotenv" },
      })
      require("lang").setup()
      require("tools").setup()
      -- prompts need a UI and vim.g.install_tools ~= "off"
      require("tools.ux").setup()
    end,
  },
  {
    name = "plugins",
    run = function() require("app.lazy").setup() end,
  },
  {
    -- One vim.lsp.config per server a language names, then vim.lsp.enable; nvim-lspconfig's configs are on the
    -- runtimepath by now
    name = "servers",
    run = function() require("lsp").setup() end,
  },
  {
    -- After the first screen: lazy fires VeryLazy once the UI is up (lazy/core/util.lua:167-195), and loads its
    -- VeryLazy plugins in its own listener, made in the plugins phase; this phase's listener is made after it, so the
    -- features' callbacks find those plugins loaded
    name = "deferred",
    at = "VeryLazy",
    run = function() require("features").very_lazy() end,
  },
}

local times = {} ---@type { name: string, ms: number }[]
local did_start = false

---@param phase app.Phase
---@param started integer hrtime
local function finish(phase, started) times[#times + 1] = { name = phase.name, ms = (vim.uv.hrtime() - started) / 1e6 } end

--- Runs the phases in order. A phase with `at` (they come last) runs at that User event, once; its time counts from the
--- event's first listener, made here before any other, so it holds what lazy loads at that event too. Runs once per
--- session: re-sourcing init.lua does nothing (restart with ZR instead), since the phases make state, autocmds and
--- plugin setups that a second run would duplicate.
function M.start()
  if did_start then
    return
  end
  did_start = true
  local group = vim.api.nvim_create_augroup("app", { clear = true })
  local began = {} ---@type table<app.Phase, integer> hrtime its event began
  for _, phase in ipairs(M.phases) do
    if phase.at then
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = phase.at,
        once = true,
        callback = function() began[phase] = vim.uv.hrtime() end,
      })
    end
  end
  for _, phase in ipairs(M.phases) do
    if not phase.at then
      local started = vim.uv.hrtime()
      phase.run()
      finish(phase, started)
    end
  end
  for _, phase in ipairs(M.phases) do
    if phase.at then
      vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = phase.at,
        once = true,
        callback = function()
          local started = began[phase] or vim.uv.hrtime()
          phase.run()
          finish(phase, started)
        end,
      })
    end
  end
end

--- The phases that ran, in the order they ran, with how long each took.
---@return { name: string, ms: number }[]
function M.times() return vim.deepcopy(times) end

return M
