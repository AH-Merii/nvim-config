-- Search and jump: flash, snacks' pickers, and clearing the search highlight
local M = {}

local spec = {
  src = "folke/flash.nvim",
  setup = function()
    require("flash").setup({
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
    })
  end,
}
M.plugins = { spec }

-- Every plugin spec line in the config's modules (src = "owner/repo", lua/app/plugins.lua), as Snacks.picker.lazy()
-- listed lazy.nvim's (snacks/picker/source/lazy.lua)
local function plugin_specs()
  local items = {} ---@type snacks.picker.finder.Item[]
  local root = vim.fn.stdpath("config") .. "/lua"
  for name, kind in vim.fs.dir(root, { depth = math.huge }) do
    if kind == "file" and name:match("%.lua$") then
      local file = root .. "/" .. name
      for l, line in ipairs(vim.fn.readfile(file)) do
        local from, to = line:find('src = "[^"]+"')
        if from and not line:match("^%s*%-%-") then
          items[#items + 1] = { file = file, line = line, text = line, pos = { l, from - 1 }, end_pos = { l, to } }
        end
      end
    end
  end
  return items
end

function M.setup()
  local function icon(glyph, color) return { icon = glyph, color = color } end
  -- flash's keys; a press before flash loads loads it (lua/app/plugins.lua)
  require("keys").feature("search")({
    { "f", function() require("flash").jump() end, "Flash jump", mode = { "n", "x", "o" } },
    { "<c-s>", function() require("flash").toggle() end, "Toggle Flash Search", mode = "c" },
    -- treesitter incremental selection
    {
      "<bs>",
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
      "Treesitter selection",
      mode = { "n", "x", "o" },
    },
  })
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
    {
      "<leader>sp",
      function() Snacks.picker.pick({ source = "plugins", title = "Plugins", finder = plugin_specs }) end,
      "Plugins",
      icon = icon("󰏖", "purple"),
    },
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
