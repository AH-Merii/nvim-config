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
    vim.notify("Unable to Load onedark pallette in lualine", vim.log.levels.WARN)
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
  "nvim-lualine/lualine.nvim",
  event = "VeryLazy",
  config = function()
    local lualine = require("lualine")
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
      set_hl("LualineNormal", { fg = c.fg })
      set_hl("LualineProjectRoot", { fg = c.magenta, bold = true })
      set_hl("LualinePath", { fg = c.fg })
      set_hl("LualineFilename", { fg = c.blue, bold = true })
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
          lualine.refresh({ place = { "statusline" } })
        end
      end,
    })

    ---------------------------------------------------------------------------
    -- Adaptive Path component with highlight
    ---------------------------------------------------------------------------
    -- The path is drawn as a statusline string, where a % in a name would start an item
    local function escape(text) return (text:gsub("%%", "%%%%")) end

    --- Adaptive filepath component for lualine.
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

      local hl_project = "%#LualineProjectRoot#"
      local hl_middle = "%#LualinePath#"
      local hl_file = "%#LualineFilename#"
      local hl_reset = "%#LualineNormal#"

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
    -- Macro recording component
    ---------------------------------------------------------------------------
    local function macro_recording()
      local reg = vim.fn.reg_recording()
      if reg == "" then
        return ""
      end
      return " @" .. reg
    end

    ---------------------------------------------------------------------------
    -- lualine setup
    ---------------------------------------------------------------------------
    local config = {
      options = {
        component_separators = "",
        section_separators = "",
        globalstatus = true,
        -- lualine's default events without CursorMoved/CursorMovedI, which rebuilt the whole statusline on every j
        -- (about 1.8 ms; docs/profiling-scrolling.md). What follows the cursor is drawn by Neovim instead: the
        -- location and progress below are statusline expressions, and searchcount refreshes on its own.
        refresh = {
          events = {
            "WinEnter",
            "BufEnter",
            "BufWritePost",
            "SessionLoadPost",
            "FileChangedShellPost",
            "VimResized",
            "Filetype",
            "ModeChanged",
            "DiagnosticChanged",
            -- the macro recording and progress segments
            "RecordingEnter",
            "RecordingLeave",
            "Progress",
          },
        },
        theme = {
          normal = { c = { fg = colors.fg } },
          inactive = { c = { fg = colors.fg } },
        },
      },
      sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_y = {},
        lualine_z = {},
        lualine_c = {},
        lualine_x = {},
      },
      inactive_sections = {
        lualine_a = {},
        lualine_b = {},
        lualine_y = {},
        lualine_z = {},
        lualine_c = {},
        lualine_x = {},
      },
    }

    local function ins_left(component) table.insert(config.sections.lualine_c, component) end
    local function ins_right(component) table.insert(config.sections.lualine_x, component) end

    ---------------------------------------------------------------------------
    -- LEFT side
    ---------------------------------------------------------------------------
    ins_left({
      function() return "" end,
      color = function()
        local mode_color = {
          n = colors.fg,
          i = colors.green,
          v = colors.blue,
          V = colors.blue,
          c = colors.magenta,
          s = colors.orange,
          S = colors.orange,
          R = colors.violet,
          t = colors.red,
        }
        return { fg = mode_color[vim.fn.mode()] or colors.red }
      end,
      padding = { right = 1 },
    })

    ins_left({
      function() return filepath_component(0.4) end,
      cond = conditions.buffer_not_empty,
    })

    -- lualine's location and progress, as expressions Neovim evaluates whenever it draws the statusline
    ins_left({ function() return "%3l:%-2{charcol('.')}" end })
    ins_left({
      function() return "%{line('.') == 1 ? 'Top' : line('.') == line('$') ? 'Bot' : printf('%2d%%', line('.') * 100 / line('$'))}" end,
      color = { fg = colors.fg, gui = "bold" },
    })
    -- diagnostics
    ins_left({
      "diagnostics",
      sources = { "nvim_diagnostic" },
      symbols = { error = " ", warn = " ", info = " " },
      diagnostics_color = {
        error = { fg = colors.red },
        warn = { fg = colors.yellow },
        info = { fg = colors.cyan },
      },
    })
    ins_left({ function() return "%=" end })

    ins_left({
      function()
        local buf = shown_buf()
        return buf and (#facts.get(buf).servers > 0 and list("servers") or "No Active LSP") or ""
      end,
      icon = "󱍔 LSP:",
      color = { fg = colors.yellow, gui = "bold" },
    })

    -- The formatters and linters that will run
    ins_left({
      function() return list("formatters") end,
      icon = "󰁨 ",
      color = { fg = colors.magenta, gui = "bold" },
    })

    ins_left({
      function() return list("linters") end,
      icon = " ",
      color = { fg = colors.orange, gui = "bold" },
    })

    -- Tools: a wrench with the number of missing tools and "?" for an unanswered project mise config, hidden
    -- otherwise (lualine leaves out the icon of an empty component); click for :Tools
    ins_left({
      function() return require("tools.ux").status() end,
      icon = "󰖷",
      color = { fg = colors.orange, gui = "bold" },
      on_click = function() vim.cmd("Tools") end,
    })

    ---------------------------------------------------------------------------
    -- RIGHT side
    ---------------------------------------------------------------------------
    -- Git Branch
    ins_right({
      "branch",
      icon = "",
      color = { fg = colors.cyan, gui = "bold" },
      cond = conditions.check_git_workspace,
    })
    -- Git Changes, counted by gitsigns: without a source lualine runs its own git diff on every BufEnter and write
    ins_right({
      "diff",
      source = function()
        local status = vim.b.gitsigns_status_dict
        if status then
          return { added = status.added, modified = status.changed, removed = status.removed }
        end
      end,
      symbols = { added = "󰐖 ", modified = "󰦓 ", removed = "󰍵 " },
      diff_color = {
        added = { fg = colors.green },
        modified = { fg = colors.orange },
        removed = { fg = colors.red },
      },
      cond = conditions.hide_in_width,
    })
    -- Running progress-messages (LSP work, :checkhealth), e.g. "40%(2)"; % escaped, "%(" opens a statusline group
    ins_right({
      function() return (vim.ui.progress_status():gsub("%%", "%%%%")) end,
      icon = "󰔟",
      color = { fg = colors.violet },
    })
    -- Search count, e.g. "[2/3]": ui2 draws it on the cmdline, which is hidden since 'cmdheight' is 0
    -- the count follows the cursor, so refresh on moves while a search is highlighted
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
      callback = function()
        if vim.v.hlsearch == 1 then
          lualine.refresh({ place = { "statusline" } })
        end
      end,
    })
    ins_right({
      "searchcount",
      color = { fg = colors.fg },
    })
    -- Macro Status
    ins_right({
      macro_recording,
      color = { fg = colors.yellow, gui = "bold" },
    })
    -- Pending keys (e.g. a count), shown here since 'cmdheight' is 0: through config.ui2.showcmd, which leaves out
    -- keys whose command runs at once, or Neovim's own %S without ui2
    ins_right({
      function() return require("config.ui2.showcmd").active and "%{v:lua.require'config.ui2.showcmd'.get()}" or "%S" end,
      color = { fg = colors.fg },
    })

    ---------------------------------------------------------------------------
    -- go live
    ---------------------------------------------------------------------------
    lualine.setup(config)
  end,
}
