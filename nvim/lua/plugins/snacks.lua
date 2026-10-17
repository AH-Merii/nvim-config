--   Git Tools: Interact with branches, logs, and diffs
-- These act on the repo of the cwd
local git_pickers = {
  { "<leader>gB", function() Snacks.picker.git_branches() end, desc = "Branches" },
  { "<leader>gl", function() Snacks.picker.git_log() end, desc = "Log" },
  { "<leader>gs", function() Snacks.picker.git_status() end, desc = "Status" },
  { "<leader>gS", function() Snacks.picker.git_stash() end, desc = "Stashes" },
  { "<leader>gD", function() Snacks.picker.git_diff() end, desc = "Diff (Hunks)" },
}
-- These act on the buffer's file
local git_file_logs = {
  { "<leader>gL", function() Snacks.picker.git_log_line() end, desc = "Log (Line)" },
  { "<leader>gf", function() Snacks.picker.git_log_file() end, desc = "Log (File)" },
}
-- This needs a remote on the buffer's repo
local git_browse = {
  { "<leader>GB", function() Snacks.gitbrowse() end, desc = "Open in Git Browser" },
}

---@param keys table[]
---@param on boolean
---@param buf? integer
local function set_keys(keys, on, buf)
  for _, key in ipairs(keys) do
    if on then
      vim.keymap.set("n", key[1], key[2], { buf = buf, desc = key.desc })
    else
      pcall(vim.keymap.del, "n", key[1], { buf = buf })
    end
  end
end

local function map_git_pickers() set_keys(git_pickers, Snacks.git.get_root(vim.fn.getcwd()) ~= nil) end

---@param buf integer
local function map_git_file_keys(buf)
  local file = vim.api.nvim_buf_get_name(buf)
  local root = vim.bo[buf].buftype == "" and file ~= "" and Snacks.git.get_root(file) or nil
  set_keys(git_file_logs, root ~= nil, buf)
  if not root then
    set_keys(git_browse, false, buf)
    return
  end
  vim.system({ "git", "-C", root, "remote" }, { text = true }, function(out)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == file then
        set_keys(git_browse, out.code == 0 and vim.trim(out.stdout) ~= "", buf)
      end
    end)
  end)
end

return {
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
      -- config/ui2/messages.lua marks (a search that found nothing); the rest is snacks' default keep
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

  keys = {
    --   File Pickers: Access files, buffers, and projects quickly
    { "<leader>ff", function() Snacks.picker.smart() end, desc = "Find Files" },
    { "<leader>fb", function() Snacks.picker.buffers() end, desc = "Buffers" },
    { "<leader>fp", function() Snacks.picker.projects() end, desc = "Projects" },
    { "<leader>fr", function() Snacks.picker.recent() end, desc = "Recent Files" },

    -- 󰞷  Search: Grep and search across files and buffers
    { "<leader>/", function() Snacks.picker.grep() end, desc = "Grep" },
    { "<leader>sB", function() Snacks.picker.grep_buffers() end, desc = "Grep (Open Buffers)" },
    { "<leader>sw", function() Snacks.picker.grep_word() end, desc = "Grep word or selection", mode = { "n", "x" } },
    { "<leader>sb", function() Snacks.picker.lines() end, desc = "Grep (Buffer Lines)" },

    -- 󱦞 Search: System & Editor: Inspect commands, diagnostics, and help
    { '<leader>s"', function() Snacks.picker.registers() end, desc = "Registers" },
    { "<leader>sa", function() Snacks.picker.autocmds() end, desc = "Autocommands" },
    { "<leader>s:", function() Snacks.picker.command_history() end, desc = "Command History" },
    { "<leader>sc", function() Snacks.picker.commands() end, desc = "Commands" },
    { "<leader>sD", function() Snacks.picker.diagnostics() end, desc = "Diagnostics (Workspace)" },
    { "<leader>sh", function() Snacks.picker.help() end, desc = "Help Pages" },
    { "<leader>sH", function() Snacks.picker.highlights() end, desc = "Highlight Groups" },
    { "<leader>si", function() Snacks.picker.icons() end, desc = "Icons" },
    { "<leader>sj", function() Snacks.picker.jumps() end, desc = "Jump List" },
    { "<leader>sk", function() Snacks.picker.keymaps() end, desc = "Keymaps" },
    { "<leader>sl", function() Snacks.picker.loclist() end, desc = "Location List" },
    { "<leader>sm", function() Snacks.picker.marks() end, desc = "Marks" },
    { "<leader>sM", function() Snacks.picker.man() end, desc = "Man Pages" },
    { "<leader>sp", function() Snacks.picker.lazy() end, desc = "Plugins (Lazy)" },
    { "<leader>sq", function() Snacks.picker.qflist() end, desc = "Quickfix List" },
    { "<leader>sR", function() Snacks.picker.resume() end, desc = "Resume" },
    { "<leader>su", function() Snacks.picker.undo() end, desc = "Undo History" },
    { "<leader>sC", function() Snacks.picker.colorschemes() end, desc = "Colorschemes" },
    { "<leader>ss", function() Snacks.scratch.select() end, desc = "Scratch Buffers" },

    -- Misc
    { "<leader>n", function() require("config.ui2.history").open() end, desc = "Message History" },
    { "<leader>N", function() Snacks.notifier.hide() end, desc = "Dismiss Notifications" },
    { "<C-W>z", function() Snacks.zen() end, desc = "Toggle Zen Mode" },
    { "<C-W>Z", function() Snacks.zen.zoom() end, desc = "Toggle Zoom" },
    { "<leader>.", function() Snacks.scratch({ ft = "markdown" }) end, desc = "Toggle Scratch Buffer" },
    { "<leader>lR", function() Snacks.rename.rename_file() end, desc = "Rename File" },

    -- Profiler
    { "<leader>Pp", function() Snacks.profiler.toggle() end, desc = "Toggle Profiler" },
    { "<leader>Ps", function() Snacks.profiler.scratch() end, desc = "Profiler Scratch" },
    { "<leader>Ph", function() Snacks.profiler.highlight() end, desc = "Profiler Highlight" },
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

    local git_group = vim.api.nvim_create_augroup("SnacksGitKeys", { clear = true })
    vim.api.nvim_create_autocmd("DirChanged", { group = git_group, callback = map_git_pickers })
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufFilePost" }, {
      group = git_group,
      callback = function(ev) map_git_file_keys(ev.buf) end,
    })
    map_git_pickers()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        map_git_file_keys(buf)
      end
    end

    -- Try to register icons with which-key
    local ok, wk = pcall(require, "which-key")
    if ok then
      wk.add({
        -- Groups
        { "<leader>f", group = "Find", icon = { icon = "󰈞", color = "blue" } },
        { "<leader>s", group = "Search", mode = { "n", "x" }, icon = { icon = "󰞷", color = "cyan" } },
        { "<leader>T", group = "Toggle Features", icon = { icon = "", color = "yellow" } },
        { "<leader>P", group = "Profiler", icon = { icon = "󰓅", color = "orange" } },

        -- find
        { "<leader>ff", icon = { icon = "󰈞", color = "blue" } },
        { "<leader>fb", icon = { icon = "", color = "grey" } },
        { "<leader>fp", icon = { icon = "", color = "grey" } },
        { "<leader>fr", icon = { icon = "", color = "yellow" } },

        -- git
        { "<leader>gB", icon = { icon = "", color = "grey" }, real = true },
        { "<leader>gl", icon = { icon = "", color = "orange" }, real = true },
        { "<leader>gL", icon = { icon = "", color = "yellow" }, real = true },
        { "<leader>gf", icon = { icon = "", color = "blue" }, real = true },
        { "<leader>gs", icon = { icon = "󰊢", color = "cyan" }, real = true },
        { "<leader>gS", icon = { icon = "󰀼", color = "grey" }, real = true },
        { "<leader>gD", icon = { icon = "", color = "cyan" }, real = true },

        -- Grep-in
        { "<leader>/", icon = { icon = "󰞷", color = "cyan" } },
        { "<leader>sB", icon = { icon = "󰱼", color = "cyan" } },
        { "<leader>sw", mode = { "n", "x" }, icon = { icon = "", color = "cyan" } },
        { "<leader>sb", icon = { icon = "", color = "cyan" } },

        -- Search
        { '<leader>s"', icon = { icon = "󰌓", color = "grey" } },
        { "<leader>sa", icon = { icon = "󰆍", color = "grey" } },
        { "<leader>s:", icon = { icon = "", color = "yellow" } },
        { "<leader>sc", icon = { icon = "󰘳", color = "grey" } },
        { "<leader>sd", icon = { icon = "", color = "orange" }, real = true },
        { "<leader>sD", icon = { icon = "", color = "orange" } },
        { "<leader>sh", icon = { icon = "󰘥", color = "grey" } },
        { "<leader>sH", icon = { icon = "", color = "yellow" } },
        { "<leader>si", icon = { icon = "", color = "grey" } },
        { "<leader>sj", icon = { icon = "󱞰", color = "yellow" } },
        { "<leader>sk", icon = { icon = "󰌌", color = "cyan" } },
        { "<leader>sl", icon = { icon = "", color = "yellow" } },
        { "<leader>sm", icon = { icon = "󰈿", color = "red" } },
        { "<leader>sM", icon = { icon = "󰮳", color = "grey" } },
        { "<leader>sp", icon = { icon = "󰏖", color = "purple" } },
        { "<leader>sq", icon = { icon = "", color = "yellow" } },
        { "<leader>sR", icon = { icon = "󰑖", color = "orange" } },
        { "<leader>su", icon = { icon = "󰕍", color = "yellow" } },
        { "<leader>sC", icon = { icon = "󰏘", color = "purple" } },
        { "<leader>ss", icon = { icon = "󰎕", color = "grey" } },
        { "<leader>sS", icon = { icon = "󱔁", color = "purple" }, real = true },

        -- LSP
        { "gd", icon = { icon = "󰊕", color = "purple" }, real = true },
        { "gD", icon = { icon = "󱈸", color = "purple" }, real = true },
        { "grr", icon = { icon = "", color = "purple" }, real = true },
        { "gI", icon = { icon = "󰡱", color = "purple" }, real = true },
        { "gt", icon = { icon = "", color = "purple" }, real = true },

        { "gr", group = "LSP", mode = { "n", "x" }, icon = { icon = "󱍔", color = "purple" } },
        { "gra", mode = { "n", "x" }, icon = { icon = "󱍔", color = "purple" }, real = true },

        { "gC", group = "calls", icon = { icon = "󰃻", color = "yellow" } },
        { "gCi", icon = { icon = "󰃺", color = "cyan" }, real = true },
        { "gCo", icon = { icon = "󰃷", color = "orange" }, real = true },

        -- Misc
        { "<leader>n", icon = { icon = "󰂚", color = "yellow" } },
        { "<leader>N", icon = { icon = "󰎟", color = "yellow" } },
        { "<C-W>z", icon = { icon = "󰫢", color = "yellow" } },
        { "<C-W>Z", icon = { icon = "󰘖", color = "yellow" } },
        { "<leader>.", icon = { icon = "󰎕", color = "grey" } },
        { "<leader>lR", icon = { icon = "󰑕", color = "green" } },
        { "<leader>GB", icon = { icon = "󰖟", color = "grey" }, real = true },
      })
    else
      vim.notify("which-key.nvim not found. Install it for enhanced keymap icons and descriptions.", vim.log.levels.WARN, { title = "Snacks Config" })
    end
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

        -- Formatting on save (lua/format/)
        local function setup_format_on_save_toggle()
          local on_save = require("format").on_save
          Snacks.toggle
            .new({
              name = "Format on Save",
              get = on_save.get,
              set = on_save.set,
              map = require("core.lsp").map,
            })
            :map("<leader>Tf")
        end

        local function setup_indent_view_toggle(n_wide, n_compact)
          -- defaults if not provided
          n_wide = n_wide or 8 -- wide visual tab view
          n_compact = n_compact or 2 -- canonical indent

          Snacks.toggle({
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
          }):map("<leader>Ti")
        end

        -- Toggles
        Snacks.toggle.option("spell", { name = "Spell Checking" }):map("<leader>Ts")
        Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>Tw")
        Snacks.toggle.option("relativenumber", { name = "Relative Number" }):map("<leader>TL")
        Snacks.toggle
          .diagnostics({
            wk_desc = { enabled = "Hide ", disabled = "Show " },
          })
          :map("<leader>Td")
        Snacks.toggle.line_number():map("<leader>Tl")
        Snacks.toggle
          .option("conceallevel", {
            name = "Markup Details",
            off = 0,
            on = vim.o.conceallevel > 0 and vim.o.conceallevel or 2,
            wk_desc = { enabled = "Conceal ", disabled = "Show " },
          })
          :map("<leader>Tm")
        Snacks.toggle
          .inlay_hints({
            wk_desc = { enabled = "Hide ", disabled = "Show " },
            map = require("core.lsp").map,
          })
          :map("<leader>Th")
        Snacks.toggle
          .new({
            name = "Code Lens",
            get = function() return vim.lsp.codelens.is_enabled({ bufnr = 0 }) end,
            set = function(state) vim.lsp.codelens.enable(state, { bufnr = 0 }) end,
            wk_desc = { enabled = "Hide ", disabled = "Show " },
            map = require("core.lsp").map,
          })
          :map("<leader>Tc")
        Snacks.toggle
          .new({
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
            wk_desc = { enabled = "Hide ", disabled = "Show " },
            map = require("core.lsp").map,
          })
          :map("<leader>Te")
        Snacks.toggle.indent():map("<leader>Tg")
        Snacks.toggle.dim():map("<leader>TD")
        Snacks.toggle.option("list", { name = "Hidden Chars" }):map("<leader>TH")

        setup_indent_view_toggle()
        setup_format_on_save_toggle()
      end,
    })
  end,
}
