-- Diagnostics display: tiny-inline-diagnostic draws them, trouble lists them

local specs = {
  {
    "rachartier/tiny-inline-diagnostic.nvim",
    event = "VeryLazy", -- Or `LspAttach`
    priority = 1000, -- needs to be loaded in first
    config = function()
      -- Default configuration
      require("tiny-inline-diagnostic").setup({
        preset = "modern",

        -- Make cursorline background transparent for diagnostics
        transparent_cursorline = true,

        -- Highlight Groups
        hi = {
          error = "DiagnosticError", -- Highlight for error diagnostics
          warn = "DiagnosticWarn", -- Highlight for warning diagnostics
          info = "DiagnosticInfo", -- Highlight for info diagnostics
          hint = "DiagnosticHint", -- Highlight for hint diagnostics
          arrow = "NonText", -- Highlight for the arrow pointing to diagnostic
          background = "CursorLine", -- Background highlight for diagnostics
          mixing_color = "Normal", -- Color to blend background with (or "None")
        },

        options = {
          -- Display the source of diagnostics (e.g., "lua_ls", "pyright")
          show_source = {
            enabled = true, -- Enable showing source names
            if_many = false, -- Only show source if multiple sources exist for the same diagnostic
          },

          -- Use icons from vim.diagnostic.config instead of preset icons
          use_icons_from_diagnostic = false,

          -- Color the arrow to match the severity of the first diagnostic
          set_arrow_to_diag_color = false,

          -- Throttle update frequency in milliseconds to improve performance
          -- Higher values reduce CPU usage but may feel less responsive
          -- Set to 0 for immediate updates (may cause lag on slow systems)
          throttle = 20,

          -- Minimum number of characters before wrapping long messages
          softwrap = 30,

          -- Control how diagnostic messages are displayed
          -- NOTE: When using display_count = true, you need to enable multiline diagnostics with multilines.enabled = true
          --       If you want them to always be displayed, you can also set multilines.always_show = true.
          add_messages = {
            messages = true, -- Show full diagnostic messages
            display_count = true, -- Show diagnostic count instead of messages when cursor not on line
            use_max_severity = false, -- When counting, only show the most severe diagnostic
            show_multiple_glyphs = true, -- Show multiple icons for multiple diagnostics of same severity
          },

          -- Settings for multiline diagnostics
          multilines = {
            enabled = true, -- Enable support for multiline diagnostic messages
            always_show = false, -- Always show messages on all lines of multiline diagnostics
            trim_whitespaces = false, -- Remove leading/trailing whitespace from each line
            tabstop = 4, -- Number of spaces per tab when expanding tabs
            severity = nil, -- Filter multiline diagnostics by severity (e.g., { vim.diagnostic.severity.ERROR })
          },

          -- Show all diagnostics on the current cursor line, not just those under the cursor
          show_all_diags_on_cursorline = false,

          -- Display related diagnostics from LSP relatedInformation
          show_related = {
            enabled = true, -- Enable displaying related diagnostics
            max_count = 3, -- Maximum number of related diagnostics to show per diagnostic
          },

          -- Handle messages that exceed the window width
          overflow = {
            mode = "none", -- "wrap": split into lines, "none": no truncation, "oneline": keep single line
            padding = 0, -- Extra characters to trigger wrapping earlier
          },

          -- Break long messages into separate lines
          break_line = {
            enabled = false, -- Enable automatic line breaking
            after = 30, -- Number of characters before inserting a line break
          },

          -- Custom function to format diagnostic messages
          -- Receives diagnostic object, returns formatted string
          -- Example: function(diag) return diag.message .. " [" .. diag.source .. "]" end
          format = nil,

          -- Virtual text display priority
          -- Higher values appear above other plugins (e.g., GitBlame)
          virt_texts = {
            priority = 2048,
          },

          -- Filter diagnostics by severity levels
          -- Remove severities you don't want to display
          severity = {
            vim.diagnostic.severity.ERROR,
            vim.diagnostic.severity.WARN,
            vim.diagnostic.severity.INFO,
            vim.diagnostic.severity.HINT,
          },

          -- Automatically disable diagnostics when opening diagnostic float windows
          override_open_float = true,
        },
      })

      -- Turn off built-in virtual text so TinyInline can handle display
      vim.diagnostic.config({
        virtual_text = false,
      })
    end,
  },
}

-- trouble's lists, and its actions in snacks' pickers
local trouble = {
  "folke/trouble.nvim",
  cmd = "Trouble",
  opts = {}, -- for default options, refer to the configuration section for custom setup.
  lazy = true,
  specs = {
    "folke/snacks.nvim",
    opts = function(_, opts)
      -- trouble's picker actions, required when one runs: requiring them here loaded trouble with snacks at startup
      local actions = {}
      for name, desc in pairs({
        trouble_open = "smart-open-with-trouble",
        trouble_open_selected = "open-with-trouble",
        trouble_open_all = "open-all-with-trouble",
        trouble_add = "smart-add-to-trouble",
        trouble_add_selected = "add-to-trouble",
        trouble_add_all = "add-all-to-trouble",
      }) do
        actions[name] = {
          action = function(...) return require("trouble.sources.snacks").actions[name].action(...) end,
          desc = desc,
        }
      end
      return vim.tbl_deep_extend("force", opts or {}, {
        picker = {
          actions = actions,
          win = {
            input = {
              keys = {
                ["<c-t>"] = {
                  "trouble_open",
                  mode = { "n", "i" },
                },
              },
            },
          },
        },
      })
    end,
  },
  keys = {
    {
      "<leader>xx",
      "<cmd>Trouble diagnostics toggle<cr>",
      desc = "Diagnostics (Trouble)",
    },
    {
      "<leader>xL",
      "<cmd>Trouble loclist toggle<cr>",
      desc = "Location List (Trouble)",
    },
    {
      "<leader>xQ",
      "<cmd>Trouble qflist toggle<cr>",
      desc = "Quickfix List (Trouble)",
    },
  },
  config = function()
    require("trouble").setup({
      modes = {
        diagnostics = { win = { size = 15 } },
        qflist = { win = { size = 15 } },
        loclist = { win = { size = 15 } },
      },
      keys = {
        ["<tab>"] = "jump", -- jump to the diagnostic or open / close folds
        ["<c-x>"] = "jump_split", -- open buffer in new split
      },
    })
  end,
}
table.insert(specs, trouble)

return { plugins = specs }
