-- Diagnostics display: how Neovim shows them, neoblocks' diagnostics module draws them at the cursor (set up with
-- neoblocks in lua/ui/statusline.lua), trouble lists them

-- trouble's lists; its keys and its actions in snacks' pickers are made in setup() below
local trouble = {
  src = "folke/trouble.nvim",
  -- `nvim +Trouble` runs before VeryLazy; setup defines the real command (trouble/config/init.lua:242)
  cmd = { "Trouble" },
  setup = function()
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
local M = { plugins = { trouble } }

function M.setup()
  vim.diagnostic.config({
    -- neoblocks' diagnostics module draws them instead
    virtual_text = false,
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    signs = {
      text = {
        [vim.diagnostic.severity.ERROR] = "󰅚 ",
        [vim.diagnostic.severity.WARN] = "󰀪 ",
        [vim.diagnostic.severity.INFO] = "󰋽 ",
        [vim.diagnostic.severity.HINT] = "󰌶 ",
      },
      numhl = {
        [vim.diagnostic.severity.ERROR] = "ErrorMsg",
        [vim.diagnostic.severity.WARN] = "WarningMsg",
      },
    },
  })

  -- The buffer's diagnostics lists, where the buffer has a diagnostic (D132; the need is Neovim's, keys/neovim.lua)
  require("keys").feature("diagnostics")({
    { "<leader>d", group = "Diagnostics", icon = { icon = "", color = "orange" } },
    { "<leader>dd", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", "Buffer Diagnostics (Trouble)", need = "a diagnostic in the buffer" },
    { "<leader>dD", "<cmd>Trouble diagnostics toggle<cr>", "Diagnostics (Trouble)" },
    { "<leader>dl", "<cmd>Trouble loclist toggle<cr>", "Location List (Trouble)", need = "a location list" },
    { "<leader>dq", "<cmd>Trouble qflist toggle<cr>", "Quickfix List (Trouble)", need = "a quickfix list" },
    {
      "<leader>dt",
      label = "Inline Diagnostics",
      toggle = {
        get = function() return require("neoblocks.util").enabled("diagnostics") end,
        set = function(on) require("neoblocks").toggle("diagnostics", on) end,
      },
    },
    {
      "<leader>sd",
      function() Snacks.picker.diagnostics_buffer() end,
      "Diagnostics (Buffer)",
      need = "a diagnostic in the buffer",
      icon = { icon = "", color = "orange" },
    },
  })

  -- trouble's actions in snacks' pickers, merged into snacks' options before it loads: requiring them here would load
  -- trouble with snacks at startup, so each action requires them when it runs
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
  require("ui.snacks").extend({
    picker = {
      actions = actions,
      win = { input = { keys = { ["<c-t>"] = { "trouble_open", mode = { "n", "i" } } } } },
    },
  })

  -- Its toggles, once snacks is loaded: a press flips one, says so, and its label in the popup follows it
  require("features").at_very_lazy(function()
    local hide_show = { enabled = "Hide ", disabled = "Show " }
    require("keys").feature("diagnostics")({
      { "<leader>Td", toggle = Snacks.toggle.diagnostics({ wk_desc = hide_show }) },
    })
  end)
end

return M
