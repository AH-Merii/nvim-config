-- Search and jump: flash, snacks' pickers, and clearing the search highlight
local M = {}

local spec = {
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {
    modes = {
      search = { enabled = true, search = { multi_window = false } },
      char = {
        -- enables cycling between next and previous
        -- if you want to override the default behaviour of f,F,t,T
        -- then we add them to the keys below
        -- I manually have custom keymaps below instead
        keys = { ";", "," },
        jump_labels = true,
      },
    },
  },
  keys = {
    {
      "f",
      mode = { "n", "x", "o" },
      function() require("flash").jump() end,
      desc = "Flash jump",
    },

    { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    -- treesitter incremental selection
    {
      "<bs>",
      mode = { "n", "x", "o" },
      function()
        require("flash").treesitter({
          actions = {
            ["+"] = "next",
            ["-"] = "prev",
            -- Adding this keymap allows us to toggle between
            -- having the char hints on and off for jumping
            -- this is useful when you simply want to use +-
            -- to incrementally increase or decrease selection
            ["%"] = function(state, _)
              -- Toggle labels
              state.opts.label.before = not state.opts.label.before
              state.opts.label.after = not state.opts.label.after

              -- refresh state
              state:update({ force = true })
            end,
          },
        })
      end,
      desc = "Treesitter selection",
    },
  },
}
M.plugins = { spec }

function M.setup()
  local function icon(glyph, color) return { icon = glyph, color = color } end
  require("keys").feature("search")({
    { "<leader>f", group = "Find", icon = icon("󰈞", "blue") },
    { "<leader>s", group = "Search", mode = { "n", "x" }, icon = icon("󰞷", "cyan") },

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
  })

  require("keys").feature("search")({
    -- Clear search highlight
    { "<Esc>", ":nohlsearch<CR>", "Clear search highlight", silent = true },
  })
end

return M
