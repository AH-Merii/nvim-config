local function get_colors() return require("ui.theme").palette() end

local spec = {
  src = "AH-Merii/neoblocks.nvim",
  -- $NVIM_PLUGIN_DEV/neoblocks.nvim, when set, instead of the installed copy (lua/app/plugins.lua)
  dev = true,
  -- At startup, not deferred: its messages module hooks ui2 (:h ui2), and every message before that skips the
  -- toasts and the history (docs/rearchitecture-decisions.md, D78)
  phase = "startup",
  setup = function()
    local sl = require("neoblocks.statusline")
    -- What the segments show of a buffer's servers, tools and checkout (lua/ui/facts.lua); this spec only draws it
    local facts = require("ui.facts")

    local colors = get_colors()

    local conditions = {
      buffer_not_empty = function() return vim.fn.empty(vim.fn.expand("%:t")) ~= 1 end,
      hide_in_width = function() return vim.fn.winwidth(0) > 80 end,
      check_git_workspace = function() return facts.get(0).repo ~= nil end,
    }

    ---------------------------------------------------------------------------
    -- Highlight groups for statusline segments
    ---------------------------------------------------------------------------
    local function define_highlights(c)
      local set_hl = function(name, opts) vim.api.nvim_set_hl(0, name, opts) end
      set_hl("StatuslineNormal", { fg = c.fg })
      set_hl("StatuslineProjectRoot", { fg = c.magenta, bold = true })
      set_hl("StatuslinePath", { fg = c.fg })
      set_hl("StatuslineFilename", { fg = c.blue, bold = true })
    end

    ---------------------------------------------------------------------------
    -- The buffer whose servers and tools the lists show: the current one, or the last file buffer while the current
    -- one is not a file (a picker, a terminal), so a popup does not blank them
    ---------------------------------------------------------------------------
    local last_file ---@type integer?
    local function shown_buf()
      local buf = vim.api.nvim_get_current_buf()
      if vim.bo[buf].buftype == "" then
        last_file = buf
        return buf
      end
      return last_file and vim.api.nvim_buf_is_valid(last_file) and last_file or nil
    end
    --- buf's list of name, joined, or "" with no buffer to show
    ---@param name "servers"|"formatter_tools"|"linter_tools"
    local function list(name)
      local buf = shown_buf()
      return buf and table.concat(facts.get(buf)[name], ", ") or ""
    end

    -- Redraw once when the shown buffer's facts change: an attach, a detach, a tool found or lost
    vim.api.nvim_create_autocmd("User", {
      pattern = facts.event,
      callback = function(ev)
        if ev.data.buf == vim.api.nvim_get_current_buf() or ev.data.buf == last_file then
          sl.refresh()
        end
      end,
    })

    ---------------------------------------------------------------------------
    -- Adaptive Path component with highlight
    ---------------------------------------------------------------------------
    -- The path is drawn as a statusline string, where a % in a name would start an item
    local function escape(text) return (text:gsub("%%", "%%%%")) end

    --- Adaptive filepath component.
    --- Shows full path when space allows, then progressively shortens:
    ---   1. Abbreviate intermediate dirs (a/b/c)
    ---   2. Shorten project name (my..example)
    ---   3. Fallback to filename only
    ---
    --- @param component_width number? (0–1) fraction of total winwidth to use (default = 0.4)
    local function filepath_component(component_width)
      component_width = component_width or 0.4

      if vim.fn.bufname("%") == "" then
        return ""
      end

      local fullpath = vim.fn.expand("%:p")
      local root = facts.get(0).repo or vim.fn.getcwd()
      if not fullpath or not root or fullpath == "" or root == "" then
        return escape(vim.fn.expand("%:t"))
      end

      local win_width = vim.fn.winwidth(0)
      local max_budget = math.floor(win_width * component_width)
      local rel = fullpath:gsub("^" .. vim.pesc(root) .. "/?", "")
      local parts = {}
      for seg in string.gmatch(rel, "[^/]+") do
        table.insert(parts, seg)
      end

      local project_name = vim.fn.fnamemodify(root, ":t")
      local filename = parts[#parts] or ""
      local middle_path = ""
      if #parts > 1 then
        middle_path = table.concat(vim.list_slice(parts, 1, #parts - 1), "/")
      end

      local hl_project = "%#StatuslineProjectRoot#"
      local hl_middle = "%#StatuslinePath#"
      local hl_file = "%#StatuslineFilename#"
      local hl_reset = "%#StatuslineNormal#"

      local function shorten_project_name(name)
        local words = {}
        for seg in name:gmatch("[^%-%_]+") do
          table.insert(words, seg)
        end
        if #words == 1 then
          for seg in name:gmatch("[A-Z][^A-Z]*") do
            table.insert(words, seg)
          end
        end
        if #words >= 2 then
          return words[1] .. ".." .. words[#words]
        end
        return name
      end

      --- The drawn path and its width on screen
      local function build_path(proj, mid, file)
        local out, shown = { hl_project .. escape(proj) .. hl_reset }, { proj }
        if mid ~= "" then
          table.insert(out, "/" .. hl_middle .. escape(mid) .. hl_reset)
          table.insert(shown, mid)
        end
        if file ~= "" then
          table.insert(out, "/" .. hl_file .. escape(file) .. hl_reset)
          table.insert(shown, file)
        end
        return table.concat(out, ""), vim.fn.strdisplaywidth(table.concat(shown, "/"))
      end

      local display, width = build_path(project_name, middle_path, filename)

      if width > max_budget then
        local short_parts = {}
        for _, seg in ipairs(vim.list_slice(parts, 1, #parts - 1)) do
          table.insert(short_parts, seg:sub(1, 1))
        end
        middle_path = table.concat(short_parts, "/")
        display, width = build_path(project_name, middle_path, filename)
      end

      if width > max_budget then
        project_name = shorten_project_name(project_name)
        display, width = build_path(project_name, middle_path, filename)
      end

      if width > max_budget then
        display = hl_file .. escape(filename) .. hl_reset
      end

      return display
    end

    define_highlights(colors)

    -- A colorscheme starts with :hi clear, which empties the path's groups
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("config.statusline", { clear = true }),
      callback = function() define_highlights(get_colors()) end,
    })

    ---------------------------------------------------------------------------
    -- LEFT side
    ---------------------------------------------------------------------------
    local left = {
      {
        function() return "" end,
        color = sl.mode_color({
          n = { fg = colors.fg },
          i = { fg = colors.green },
          v = { fg = colors.blue },
          V = { fg = colors.blue },
          c = { fg = colors.magenta },
          s = { fg = colors.orange },
          S = { fg = colors.orange },
          R = { fg = colors.violet },
          t = { fg = colors.red },
        }, { fg = colors.red }),
        padding = { right = 1 },
      },
      {
        function() return filepath_component(0.4) end,
        cond = conditions.buffer_not_empty,
      },
      -- the location and progress are expressions Neovim evaluates whenever it draws the statusline
      "%3l:%-2{charcol('.')}",
      {
        "%{line('.') == 1 ? 'Top' : line('.') == line('$') ? 'Bot' : printf('%2d%%', line('.') * 100 / line('$'))}",
        color = { fg = colors.fg, bold = true },
      },
      {
        "diagnostics",
        symbols = { error = " ", warn = " ", info = " " },
        diagnostics_color = {
          error = { fg = colors.red },
          warn = { fg = colors.yellow },
          info = { fg = colors.cyan },
        },
      },
      "%=",
      {
        function()
          local buf = shown_buf()
          return buf and (#facts.get(buf).servers > 0 and list("servers") or "No Active LSP") or ""
        end,
        icon = "󱍔 LSP:",
        color = { fg = colors.yellow, bold = true },
      },
      -- The tools of the formatters and linters that will run: ruff, not ruff_fix, ruff_format (D137)
      {
        function() return list("formatter_tools") end,
        icon = "󰁨 ",
        color = { fg = colors.magenta, bold = true },
      },
      {
        function() return list("linter_tools") end,
        icon = " ",
        color = { fg = colors.orange, bold = true },
      },
      -- Tools: a wrench with the number of missing tools and "?" for an unanswered project mise config, hidden
      -- otherwise (an empty component draws no icon); click for :Tools
      {
        function() return require("tools.ux").status() end,
        icon = "󰖷",
        color = { fg = colors.orange, bold = true },
        on_click = function() vim.cmd("Tools") end,
      },
    }

    ---------------------------------------------------------------------------
    -- RIGHT side
    ---------------------------------------------------------------------------
    local right = {
      -- Git Branch, read from HEAD and watched
      {
        "branch",
        icon = "",
        color = { fg = colors.cyan, bold = true },
        cond = conditions.check_git_workspace,
      },
      -- Git Changes, counted by gitsigns (b:gitsigns_status_dict)
      {
        "diff",
        symbols = { added = "󰐖 ", modified = "󰦓 ", removed = "󰍵 " },
        diff_color = {
          added = { fg = colors.green },
          modified = { fg = colors.orange },
          removed = { fg = colors.red },
        },
        cond = conditions.hide_in_width,
      },
      -- Running progress-messages (LSP work, :checkhealth), e.g. "40%(2)"
      {
        "progress_status",
        icon = "󰔟",
        color = { fg = colors.violet },
      },
      -- Search count, e.g. "[2/3]": ui2 draws it on the cmdline, which is hidden since 'cmdheight' is 0. It follows
      -- the cursor while a search is highlighted, without rebuilding the line
      {
        "searchcount",
        color = { fg = colors.fg },
      },
      -- Macro Status
      {
        "recording",
        icon = "",
        color = { fg = colors.yellow, bold = true },
      },
      -- Pending keys (e.g. a count), shown here since 'cmdheight' is 0: through neoblocks' messages module, which
      -- leaves out keys whose command runs at once, or Neovim's own %S without ui2
      {
        function() return Neoblocks.messages.showcmd() end,
        color = { fg = colors.fg },
      },
    }

    ---------------------------------------------------------------------------
    -- go live
    ---------------------------------------------------------------------------
    require("neoblocks").setup({
      -- noice's look on ui2: ':' in a popup, messages as snacks.notifier toasts, long output in a split, the message
      -- history and the pending keys above. The options phase enabled ui2 already, unless it failed before; then the
      -- module enables it, with the same options (lua/app/init.lua)
      messages = { ui2 = require("app").ui2 },
      -- The cursor line's diagnostics in a pill after it, a count on the other lines: tiny-inline-diagnostic's look
      -- (lua/features/diagnostics.lua turns Neovim's virtual text off and toggles this on <leader>dt)
      diagnostics = {},
      statusline = {
        color = { fg = colors.fg },
        left = left,
        right = right,
        -- Rebuilt on these and on what the built-ins need (DiagnosticChanged, Progress, the recording events, HEAD),
        -- never on a cursor move: what follows the cursor is drawn by Neovim. The server and tool lists redraw on
        -- FactsChanged above. There is no timer, so the path follows a rename (BufFilePost), a :cd (DirChanged) and
        -- its width budget a window resize (WinResized) on their events
        events = {
          "WinEnter",
          "BufEnter",
          "BufFilePost",
          "DirChanged",
          "BufWritePost",
          "SessionLoadPost",
          "FileChangedShellPost",
          "VimResized",
          "WinResized",
          "FileType",
          "ModeChanged",
        },
      },
    })
  end,
}

return { plugins = { spec } }
