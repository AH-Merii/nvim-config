return {
  {
    "navarasu/onedark.nvim",
    priority = 1000,
    config = function()
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
          -- Make statusline/lualine background transparent
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

        -- Lualine options --
        lualine = {
          transparent = true, -- lualine center bar transparency
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
