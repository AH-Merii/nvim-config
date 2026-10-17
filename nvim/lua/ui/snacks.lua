local keys = require("keys")

-- The git needs, cached by the events that change them: a need is read on each press and popup rebuild
local cwd_repo = {} ---@type table<string, boolean> cwd -> in a repo; emptied when the cwd changes
local file_repo = {} ---@type table<integer, { file: string, repo: boolean, remote?: boolean }> by buffer, for its file
-- The cwd is in a repo: the pickers act on it
keys.need("git cwd", function()
  local cwd = vim.fn.getcwd()
  if cwd_repo[cwd] == nil then
    cwd_repo[cwd] = Snacks.git.get_root(cwd) ~= nil
  end
  return cwd_repo[cwd]
end)
-- The buffer's file is in a repo; that repo has a remote
keys.need("git file", function(buf)
  local f = file_repo[buf]
  return f ~= nil and f.file == vim.api.nvim_buf_get_name(buf) and f.repo
end)
keys.need("git remote", function(buf)
  local f = file_repo[buf]
  return f ~= nil and f.file == vim.api.nvim_buf_get_name(buf) and f.remote == true
end)

---@param buf integer
local function look_up_file(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  local root = vim.bo[buf].buftype == "" and file ~= "" and Snacks.git.get_root(file) or nil
  local entry = { file = file, repo = root ~= nil }
  file_repo[buf] = entry
  if root then
    vim.system({ "git", "-C", root, "remote" }, { text = true }, function(out) entry.remote = out.code == 0 and vim.trim(out.stdout) ~= "" end)
  end
end

local function look_up_loaded()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      look_up_file(buf)
    end
  end
end

-- The events that fill the caches are made here with the needs, not in config: lazy runs this module again after an
-- install or update (lazy/core/plugin.lua:184), and the needs then read the new caches, which only these autocmds
-- fill. The group is cleared, so the last run's autocmds are the only ones.
local git_group = vim.api.nvim_create_augroup("SnacksGitKeys", { clear = true })
vim.api.nvim_create_autocmd("DirChanged", { group = git_group, callback = function() cwd_repo = {} end })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufFilePost" }, {
  group = git_group,
  callback = function(ev) look_up_file(ev.buf) end,
})
vim.api.nvim_create_autocmd("BufWipeout", { group = git_group, callback = function(ev) file_repo[ev.buf] = nil end })
-- run again by lazy: the open buffers' files, for the new cache (on the first run snacks' config does this)
if package.loaded.snacks then
  look_up_loaded()
end

local function icon(glyph, color) return { icon = glyph, color = color } end
keys.feature("snacks")({
  { "<leader>f", group = "Find", icon = icon("󰈞", "blue") },
  { "<leader>s", group = "Search", mode = { "n", "x" }, icon = icon("󰞷", "cyan") },
  { "<leader>T", group = "Toggle Features", icon = icon("", "yellow") },
  { "<leader>P", group = "Profiler", icon = icon("󰓅", "orange") },

  --   File Pickers: Access files, buffers, and projects quickly
  { "<leader>ff", function() Snacks.picker.smart() end, "Find Files", icon = icon("󰈞", "blue") },
  { "<leader>fb", function() Snacks.picker.buffers() end, "Buffers", icon = icon("", "grey") },
  { "<leader>fp", function() Snacks.picker.projects() end, "Projects", icon = icon("", "grey") },
  { "<leader>fr", function() Snacks.picker.recent() end, "Recent Files", icon = icon("", "yellow") },

  -- 󰞷  Search: Grep and search across files and buffers
  { "<leader>/", function() Snacks.picker.grep() end, "Grep", icon = icon("󰞷", "cyan") },
  { "<leader>sB", function() Snacks.picker.grep_buffers() end, "Grep (Open Buffers)", icon = icon("󰱼", "cyan") },
  { "<leader>sw", function() Snacks.picker.grep_word() end, "Grep word or selection", mode = { "n", "x" }, icon = icon("", "cyan") },
  { "<leader>sb", function() Snacks.picker.lines() end, "Grep (Buffer Lines)", icon = icon("", "cyan") },

  -- 󱦞 Search: System & Editor: Inspect commands, diagnostics, and help
  { '<leader>s"', function() Snacks.picker.registers() end, "Registers", icon = icon("󰌓", "grey") },
  { "<leader>sa", function() Snacks.picker.autocmds() end, "Autocommands", icon = icon("󰆍", "grey") },
  { "<leader>s:", function() Snacks.picker.command_history() end, "Command History", icon = icon("", "yellow") },
  { "<leader>sc", function() Snacks.picker.commands() end, "Commands", icon = icon("󰘳", "grey") },
  { "<leader>sD", function() Snacks.picker.diagnostics() end, "Diagnostics (Workspace)", icon = icon("", "orange") },
  { "<leader>sh", function() Snacks.picker.help() end, "Help Pages", icon = icon("󰘥", "grey") },
  { "<leader>sH", function() Snacks.picker.highlights() end, "Highlight Groups", icon = icon("", "yellow") },
  { "<leader>si", function() Snacks.picker.icons() end, "Icons", icon = icon("", "grey") },
  { "<leader>sj", function() Snacks.picker.jumps() end, "Jump List", icon = icon("󱞰", "yellow") },
  { "<leader>sk", function() Snacks.picker.keymaps() end, "Keymaps", icon = icon("󰌌", "cyan") },
  { "<leader>sl", function() Snacks.picker.loclist() end, "Location List", icon = icon("", "yellow") },
  { "<leader>sm", function() Snacks.picker.marks() end, "Marks", icon = icon("󰈿", "red") },
  { "<leader>sM", function() Snacks.picker.man() end, "Man Pages", icon = icon("󰮳", "grey") },
  { "<leader>sp", function() Snacks.picker.lazy() end, "Plugins (Lazy)", icon = icon("󰏖", "purple") },
  { "<leader>sq", function() Snacks.picker.qflist() end, "Quickfix List", icon = icon("", "yellow") },
  { "<leader>sR", function() Snacks.picker.resume() end, "Resume", icon = icon("󰑖", "orange") },
  { "<leader>su", function() Snacks.picker.undo() end, "Undo History", icon = icon("󰕍", "yellow") },
  { "<leader>sC", function() Snacks.picker.colorschemes() end, "Colorschemes", icon = icon("󰏘", "purple") },
  { "<leader>ss", function() Snacks.scratch.select() end, "Scratch Buffers", icon = icon("󰎕", "grey") },

  -- Misc
  { "<leader>n", function() require("ui.messages.history").open() end, "Message History", icon = icon("󰂚", "yellow") },
  { "<leader>N", function() Snacks.notifier.hide() end, "Dismiss Notifications", icon = icon("󰎟", "yellow") },
  { "<C-W>z", function() Snacks.zen() end, "Toggle Zen Mode", icon = icon("󰫢", "yellow") },
  { "<C-W>Z", function() Snacks.zen.zoom() end, "Toggle Zoom", icon = icon("󰘖", "yellow") },
  { "<leader>.", function() Snacks.scratch({ ft = "markdown" }) end, "Toggle Scratch Buffer", icon = icon("󰎕", "grey") },
  { "<leader>lR", function() Snacks.rename.rename_file() end, "Rename File", icon = icon("󰑕", "green") },

  -- Profiler
  { "<leader>Pp", function() Snacks.profiler.toggle() end, "Toggle Profiler" },
  { "<leader>Ps", function() Snacks.profiler.scratch() end, "Profiler Scratch" },
  { "<leader>Ph", function() Snacks.profiler.highlight() end, "Profiler Highlight" },
})

--   Git Tools: Interact with branches, logs, and diffs
-- These act on the repo of the cwd
keys.feature("snacks git", { need = "git cwd" })({
  { "<leader>gB", function() Snacks.picker.git_branches() end, "Branches", icon = icon("", "grey") },
  { "<leader>gl", function() Snacks.picker.git_log() end, "Log", icon = icon("", "orange") },
  { "<leader>gs", function() Snacks.picker.git_status() end, "Status", icon = icon("󰊢", "cyan") },
  { "<leader>gS", function() Snacks.picker.git_stash() end, "Stashes", icon = icon("󰀼", "grey") },
  { "<leader>gD", function() Snacks.picker.git_diff() end, "Diff (Hunks)", icon = icon("", "cyan") },
})
-- These act on the buffer's file
keys.feature("snacks git", { need = "git file" })({
  { "<leader>gL", function() Snacks.picker.git_log_line() end, "Log (Line)", icon = icon("", "yellow") },
  { "<leader>gf", function() Snacks.picker.git_log_file() end, "Log (File)", icon = icon("", "blue") },
})
-- This needs a remote on the buffer's repo
keys.feature("snacks git")({ "<leader>GB", function() Snacks.gitbrowse() end, "Open in Git Browser", need = "git remote", icon = icon("󰖟", "grey") })

local spec = {
  "folke/snacks.nvim",
  priority = 1000,
  lazy = false,

  ---@type snacks.Config
  opts = {
    bigfile = { enabled = true },
    profiler = { enabled = true },
    dashboard = { enabled = false }, --
    explorer = { enabled = false }, --
    indent = {
      enabled = true,
      -- The scope grows out from the cursor in 150 ms rather than snacks' 500 (20 ms a line): a jump settled sooner
      -- and redrew for half as long (docs/profiling-scrolling.md)
      animate = { duration = { step = 10, total = 150 } },
    },
    input = { enabled = true },
    picker = {
      enabled = true,
      win = {
        input = {
          keys = {
            -- Navigation
            ["<C-h>"] = { "focus_list", mode = { "n", "i" } },
            ["<C-l>"] = { "focus_preview", mode = { "n", "i" } },
            ["<C-k>"] = { "focus_list", mode = { "n", "i" } },
            ["<C-j>"] = { "focus_preview", mode = { "n", "i" } },
          },
        },
        list = {
          keys = {
            -- Navigation
            ["<C-h>"] = { "focus_input", mode = { "n" } },
            ["<C-l>"] = { "focus_preview", mode = { "n" } },
            ["<C-k>"] = { "focus_input", mode = { "n" } },
            ["<C-j>"] = { "focus_preview", mode = { "n" } },
          },
        },
        preview = {
          keys = {
            -- Only map "go back to picker" keys; C-l/C-j are no-op (already at destination)
            ["<C-h>"] = { "focus_list", mode = { "n" } },
            ["<C-k>"] = { "focus_list", mode = { "n" } },
          },
        },
      },
    },
    notifier = {
      enabled = true,
      -- Errors stay until dismissed (<leader>N), like ui2 message errors, except the routine ones
      -- ui/messages/messages.lua marks (a search that found nothing); the rest is snacks' default keep
      -- (snacks/notifier.lua:131-133).
      keep = function(n) return n.level == "error" and not n.routine or vim.fn.getcmdpos() > 0 end,
    },
    quickfile = { enabled = true },
    scope = { enabled = true },
    scroll = {
      enabled = true,
      -- Front-loaded, so C-d/C-u cover half the distance in about 20 ms, and done in about 80 ms; snacks' default
      -- is linear over 200 ms, halfway at about 85 ms (docs/profiling-scrolling.md)
      animate = { duration = { step = 10, total = 120 }, easing = "outCubic" },
    },
    statuscolumn = {
      enabled = true,
      folds = {
        open = true, -- show open fold icons
        git_hl = false, -- use Git Signs hl for fold icons
      },
    },
    words = { enabled = true },
  },

  config = function(_, opts)
    require("snacks").setup(opts)

    -- Nightly names its built-in modules "@vim/loader", without ".lua", and the profiler reads that path as a file
    local loc = require("snacks.profiler.loc")
    local ts_locs = loc.ts_locs
    loc.ts_locs = function(file)
      for _, f in ipairs({ file, file .. ".lua", file .. "/init.lua" }) do
        if vim.fn.filereadable(f) == 1 then
          return ts_locs(f)
        end
      end
      return {}
    end

    -- The indent scope animates after a key pressed on its own, not while keys repeat (a held j or C-d): each of
    -- those started another 150 ms of redraws for a scope the cursor then left (docs/profiling-scrolling.md). Keys,
    -- not cursor moves, since a smooth scroll's frames move the cursor too; and only typed ones, since the frames run
    -- `normal!` and mappings expand. A buffer variable, which snacks reads before the global one.
    local last_key = 0
    vim.on_key(function(_, typed)
      if not typed or typed == "" then
        return
      end
      local now = vim.uv.hrtime()
      if now - last_key > 150e6 then
        vim.b.snacks_animate_indent = nil
      else
        vim.b.snacks_animate_indent = false
      end
      last_key = now
    end, vim.api.nvim_create_namespace("config.indent_at_rest"))

    -- snacks caches each row of the statuscolumn by its relative number too, which with 'relativenumber' changes for
    -- every row on every j, and empties the cache every 50 ms. Rows are cached here around their number, which is
    -- put back in each time the way snacks picks it (absolute on the cursor line, relative elsewhere), for 200 ms:
    -- signs and marks show at most that late (docs/profiling-scrolling.md).
    local stc = require("snacks.statuscolumn")
    local stc_get = stc.get
    local rows = {} ---@type table<string, string[]> the row before and after its number, or the whole row
    local wins = {} ---@type table<integer, boolean[]> each window's 'number' and 'relativenumber'
    assert(vim.uv.new_timer()):start(200, 200, function()
      rows, wins = {}, {}
    end)
    vim.api.nvim_create_autocmd("OptionSet", {
      pattern = { "number", "relativenumber" },
      callback = function()
        rows, wins = {}, {}
      end,
    })
    stc.get = function()
      local win = vim.g.statusline_winid
      local buf = vim.api.nvim_win_get_buf(win)
      local w = wins[win]
      if not w then
        w = { vim.wo[win].number, vim.wo[win].relativenumber }
        wins[win] = w
      end
      local nu, rnu = w[1], w[2]
      local num = (nu or rnu) and vim.v.virtnum == 0 and ((rnu and not (nu and vim.v.relnum == 0)) and vim.v.relnum or vim.v.lnum)
      local key = ("%d:%d:%d:%d:%s:%s"):format(win, buf, vim.v.lnum, vim.v.virtnum ~= 0 and 1 or 0, nu, rnu)
      local row = rows[key]
      if not row then
        -- snacks writes the number as "%=<number> "; found by its shape, since snacks' own cache can hand back a
        -- row drawn just before 'number' or 'relativenumber' changed
        local s = stc_get()
        local from, to = s:find("%%=%d+ ")
        row = from and { s:sub(1, from - 1), s:sub(to + 1) } or { s }
        rows[key] = row
      end
      if not row[2] then
        return row[1]
      end
      return num and (row[1] .. "%=" .. num .. " " .. row[2]) or (row[1] .. row[2])
    end

    look_up_loaded()
  end,

  init = function()
    local autocmd = vim.api.nvim_create_autocmd
    local augroup = vim.api.nvim_create_augroup
    local user_group = augroup("SnacksUserAutocmds", { clear = true })

    -- Defer setup until all lazy-loaded plugins are ready
    autocmd("User", {
      group = user_group,
      pattern = "VeryLazy",
      desc = "Initialize Snacks toggle keymaps after LazyVim startup",
      callback = function()
        -- debug helpers
        _G.dd = function(...) Snacks.debug.inspect(...) end
        _G.bt = function() Snacks.debug.backtrace() end

        local function indent_view_toggle(n_wide, n_compact)
          -- defaults if not provided
          n_wide = n_wide or 8 -- wide visual tab view
          n_compact = n_compact or 2 -- canonical indent

          return Snacks.toggle({
            name = "Indent View (tabstop)",
            get = function() return vim.bo.tabstop == n_wide end,
            set = function(state)
              if state then
                vim.bo.tabstop = n_wide
              else
                vim.bo.tabstop = n_compact
              end

              -- keep semantics stable
              vim.bo.shiftwidth = n_compact
              vim.bo.softtabstop = n_compact

              vim.notify(
                string.format("Indent View: tabstop=%d (shiftwidth=%d, softtabstop=%d)", vim.bo.tabstop, vim.bo.shiftwidth, vim.bo.softtabstop),
                vim.log.levels.INFO,
                { title = "Snacks" }
              )
            end,
          })
        end

        -- Toggles: a press flips one, says so, and its label in the popup follows it (lua/keys/)
        local toggle = require("keys").feature("toggles")
        local hide_show = { enabled = "Hide ", disabled = "Show " }
        toggle({
          { "<leader>Ts", toggle = Snacks.toggle.option("spell", { name = "Spell Checking" }) },
          { "<leader>Tw", toggle = Snacks.toggle.option("wrap", { name = "Wrap" }) },
          { "<leader>TL", toggle = Snacks.toggle.option("relativenumber", { name = "Relative Number" }) },
          { "<leader>Td", toggle = Snacks.toggle.diagnostics({ wk_desc = hide_show }) },
          { "<leader>Tl", toggle = Snacks.toggle.line_number() },
          {
            "<leader>Tm",
            toggle = Snacks.toggle.option("conceallevel", {
              name = "Markup Details",
              off = 0,
              on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2,
              wk_desc = { enabled = "Conceal ", disabled = "Show " },
            }),
          },
          { "<leader>Th", toggle = Snacks.toggle.inlay_hints({ wk_desc = hide_show }), need = "inlayHint" },
          {
            "<leader>Tc",
            toggle = Snacks.toggle.new({
              name = "Code Lens",
              get = function() return vim.lsp.codelens.is_enabled({ bufnr = 0 }) end,
              set = function(state) vim.lsp.codelens.enable(state, { bufnr = 0 }) end,
              wk_desc = hide_show,
            }),
            need = "codeLens",
          },
          {
            "<leader>Te",
            toggle = Snacks.toggle.new({
              name = "Type Errors",
              get = function()
                local client = vim.lsp.get_clients({ bufnr = 0, name = "pyrefly" })[1]
                return client ~= nil and require("config.utils").pyrefly_type_errors(client)
              end,
              set = function(state)
                for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0, name = "pyrefly" })) do
                  require("config.utils").pyrefly_type_errors(client, state)
                end
              end,
              wk_desc = hide_show,
            }),
            need = "client:pyrefly",
          },
          { "<leader>Tg", toggle = Snacks.toggle.indent() },
          { "<leader>TD", toggle = Snacks.toggle.dim() },
          { "<leader>TH", toggle = Snacks.toggle.option("list", { name = "Hidden Chars" }) },
          { "<leader>Ti", toggle = indent_view_toggle() },
        })
      end,
    })
  end,
}

return { plugins = { spec } }
