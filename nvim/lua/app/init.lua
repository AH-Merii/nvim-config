-- Startup, as named phases in a fixed order (docs/rearchitecture-decisions.md, "Step 6a: app/"). init.lua calls
-- M.start() once. Each phase runs once, in the order of M.phases, and is timed: M.times() lists the phases that ran,
-- with their milliseconds (`:lua =require("app").times()`).
local M = {}

---@class app.Phase
---@field name string
---@field event? string|string[] the event it waits for, once; without one it runs inside start()
---@field pattern? string the event's pattern (User VeryLazy)
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
      require("lang").setup()
      require("tools").setup()
      -- prompts need a UI and vim.g.install_tools ~= "off"
      require("tools.ux").setup()
    end,
  },
  {
    -- vim.pack installs what is missing, then the startup plugins load (lua/app/plugins.lua)
    name = "plugins",
    run = function() require("app.plugins").setup(require("features").plugins()) end,
  },
  {
    -- One vim.lsp.config per server a language names, then vim.lsp.enable; nvim-lspconfig's configs are on the
    -- runtimepath by now
    name = "servers",
    run = function() require("lsp").setup() end,
  },
  {
    -- The plugins that serve files (nvim-lint, origami), before the first one's FileType; never, in a session that
    -- reads no file
    name = "buffer",
    event = { "BufReadPre", "BufNewFile" },
    run = function() require("app.plugins").load_phase("buffer") end,
  },
  {
    -- After the first screen: start() fires User VeryLazy once the UI is up, as lazy.nvim did
    -- (lazy/core/util.lua:167-195). The deferred plugins load first, then the features' callbacks, which need them
    name = "deferred",
    event = "User",
    pattern = "VeryLazy",
    run = function()
      require("app.plugins").load_phase("deferred")
      require("features").very_lazy()
    end,
  },
}

local times = {} ---@type { name: string, ms: number }[]
local did_start = false

--- Runs phase and records its time. An error is reported and the later phases still run, so a failed plugin install
--- or a broken module does not leave the session without servers or keys.
---@param phase app.Phase
---@param started integer hrtime
local function run(phase, started)
  local ok, err = xpcall(phase.run, debug.traceback)
  times[#times + 1] = { name = phase.name, ms = (vim.uv.hrtime() - started) / 1e6 }
  if not ok then
    vim.notify(("app: the %s phase failed:\n%s"):format(phase.name, err), vim.log.levels.ERROR, { title = "app" })
  end
end

--- Runs the phases in order. A phase with an event (they come last) runs at that event, once; its time counts from
--- the event's first listener, made here before any other of this config's, so it holds the listeners before it too.
--- Then fires VeryLazy once the UI has entered. Runs once per session: re-sourcing init.lua does nothing (restart
--- with ZR instead), since the phases make state, autocmds and plugin setups that a second run would duplicate.
function M.start()
  if did_start then
    return
  end
  did_start = true
  local group = vim.api.nvim_create_augroup("app", { clear = true })
  local began = {} ---@type table<app.Phase, integer> hrtime its event began
  local ran = {} ---@type table<app.Phase, true> once is per event: a phase with two runs at the first of them
  for _, phase in ipairs(M.phases) do
    if phase.event then
      vim.api.nvim_create_autocmd(phase.event, {
        group = group,
        pattern = phase.pattern,
        once = true,
        callback = function() began[phase] = began[phase] or vim.uv.hrtime() end,
      })
    end
  end
  for _, phase in ipairs(M.phases) do
    if not phase.event then
      run(phase, vim.uv.hrtime())
    end
  end
  for _, phase in ipairs(M.phases) do
    if phase.event then
      vim.api.nvim_create_autocmd(phase.event, {
        group = group,
        pattern = phase.pattern,
        once = true,
        callback = function()
          if ran[phase] then
            return
          end
          ran[phase] = true
          run(phase, began[phase] or vim.uv.hrtime())
        end,
      })
    end
  end
  -- After the first screen, as lazy.nvim timed it: UIEnter, then the next turn of the event loop
  vim.api.nvim_create_autocmd("UIEnter", {
    group = group,
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.v.exiting ~= vim.NIL or vim.g.did_very_lazy then
          return
        end
        vim.g.did_very_lazy = true
        vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
      end)
    end,
  })
end

--- The phases that ran, in the order they ran, with how long each took.
---@return { name: string, ms: number }[]
function M.times() return vim.deepcopy(times) end

return M
