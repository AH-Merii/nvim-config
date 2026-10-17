return {
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
