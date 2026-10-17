-- palletes
local function get_onedark_palette()
  -- onedark.palette holds one table per style
  local ok, palettes = pcall(require, "onedark.palette")
  local c = ok and vim.g.onedark_config and palettes[vim.g.onedark_config.style]
  if c then
    return {
      bg = c.bg0 or "#282c34",
      fg = c.fg or "#abb2bf",
      red = c.red or "#e06c75",
      yellow = c.yellow or "#e5c07b",
      green = c.green or "#98c379",
      cyan = c.cyan or "#56b6c2",
      blue = c.blue or "#61afef",
      magenta = c.purple or "#c678dd",
      orange = c.orange or "#d19a66",
      violet = c.violet or "#a9a1e1",
    }
  else
    vim.notify("Unable to Load onedark pallette in the statusline", vim.log.levels.WARN)
    -- Fallback OneDark colors (from official theme)
    return {
      bg = "#282c34",
      fg = "#abb2bf",
      red = "#e06c75",
      yellow = "#e5c07b",
      green = "#98c379",
      cyan = "#56b6c2",
      blue = "#61afef",
      magenta = "#c678dd",
      orange = "#d19a66",
      violet = "#a9a1e1",
    }
  end
end

local function get_colors() return get_onedark_palette() end

return {
  "AH-Merii/neoblocks.nvim",
  event = "VeryLazy",
  config = function()
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
    ---@param name "servers"|"formatters"|"linters"
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

    -- vim.api.nvim_create_autocmd("ColorScheme", {
    --   callback = function()
    --     colors = get_colors()
    --     define_highlights(colors)
    --   end,
    -- })

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
      -- The formatters and linters that will run
      {
        function() return list("formatters") end,
        icon = "󰁨 ",
        color = { fg = colors.magenta, bold = true },
      },
      {
        function() return list("linters") end,
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
      -- Pending keys (e.g. a count), shown here since 'cmdheight' is 0: through config.ui2.showcmd, which leaves out
      -- keys whose command runs at once, or Neovim's own %S without ui2
      {
        function() return require("config.ui2.showcmd").active and "%{v:lua.require'config.ui2.showcmd'.get()}" or "%S" end,
        color = { fg = colors.fg },
      },
    }

    ---------------------------------------------------------------------------
    -- go live
    ---------------------------------------------------------------------------
    require("neoblocks").setup({
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
