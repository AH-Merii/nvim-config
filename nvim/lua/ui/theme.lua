-- The colorscheme and every highlight override: onedark, with the overrides in its `highlights`, which onedark applies
-- again each time it loads (:colorscheme onedark included)
local M = {}

--- The colorscheme's colours by name, for modules that draw their own groups (the statusline); onedark's current
--- style, else onedark's defaults
function M.palette()
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

M.plugins = {
  {
    src = "navarasu/onedark.nvim",
    -- first, so the plugins after it find their colours
    phase = "startup",
    setup = function()
      require("onedark").setup({
        -- Default theme style. Choose between 'dark', 'darker', 'cool', 'deep', 'warm', 'warmer' and 'light'
        style = "deep",
        term_colors = false, -- :terminal keeps the terminal's own palette (ghostty/themes/OneDark)
        transparent = true,

        -- toggle theme style ---
        toggle_style_key = "<leader>Tt", -- keybind to toggle theme style. Leave it nil to disable it, or set it to a string, for example "<leader>ts"
        toggle_style_list = { "dark", "darker", "cool", "deep", "warm", "warmer", "light" }, -- List of styles to toggle between

        -- Change code style ---
        code_style = {
          comments = "italic",
          keywords = "none",
          functions = "none",
          strings = "none",
          variables = "none",
        },
        colors = {
          bright_orange = "#ff8800",
          text = "#cdd6f4",
          str = "#82d547",
          cursorline = "#2c313c",
        },

        highlights = {
          CursorLineFold = { fg = "$bright_orange", fmt = "bold" },
          CursorLineNr = { fg = "$bright_orange", fmt = "bold" },
          CursorLineSign = { fg = "$bright_orange", fmt = "bold" },
          CursorLine = { bg = "$cursorline" },
          StatusLine = { bg = "none" },

          String = { fg = "$str" },
          ["@string"] = { fg = "$str" },

          Pmenu = { bg = "none" },
          NormalFloat = { bg = "none" },
          FloatBorder = { fg = "$text", bg = "none" },

          SnacksPickerBorder = { fg = "$text" },
          SnacksPickerCursorLine = { bg = "$cursorline" },
          SnacksPickerListCursorLine = { bg = "$cursorline" },
          SnacksPickerPreviewCursorLine = { bg = "$cursorline" },

          WhichKeyTitle = { fg = "$text" },
          WhichKey = { fg = "$text" },

          LspReferenceText = { fg = "none", bg = "none", fmt = "bold" },
          LspReferenceRead = { fg = "none", bg = "none", fmt = "bold" },
          LspReferenceWrite = { fg = "none", bg = "none", fmt = "bold" },

          IlluminatedWordText = { fg = "none", bg = "none", fmt = "bold" },
          IlluminatedWordRead = { fg = "none", bg = "none", fmt = "bold" },
          IlluminatedWordWrite = { fg = "none", bg = "none", fmt = "bold" },
        },

        -- Plugins Config --
        diagnostics = {
          darker = true, -- darker colors for diagnostic
          undercurl = true, -- use undercurl instead of underline for diagnostics
          background = true, -- use background color for virtual text
        },
      })
      require("onedark").load()
    end,
  },
}

return M
