-- The editor's own keys
local key = require("keys").feature("editor")

-- Visual mode < and > with the Snacks indent animation paused, and the selection kept
---@param cmd string
local function shift(cmd)
  return function()
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks and snacks.indent then
      local buf = vim.api.nvim_get_current_buf()
      local prev_state = vim.b[buf].snacks_animate_indent
      vim.b[buf].snacks_animate_indent = false

      -- Perform normal indent and stay in visual mode
      vim.cmd("normal! " .. cmd)

      -- Restore animation after short delay
      vim.defer_fn(function() vim.b[buf].snacks_animate_indent = prev_state end, 30)
    else
      vim.cmd("normal! " .. cmd)
    end
  end
end

key({
  -- Move selected line / block of text in visual mode
  { "J", ":m '>+1<CR>gv", "Move line down", mode = "x", silent = true },
  { "K", ":m '<-2<CR>gv", "Move line up", mode = "x", silent = true },

  -- Fast saving
  { "<leader>w", ":write!<CR>", "Write", silent = true, icon = { icon = "", color = "green" } },
  { "<leader>q", ":q!<CR>", "Quit", silent = true, icon = { icon = "", color = "red" } },

  -- Remap for dealing with visual line wraps -> respects wraps. gj/gk run from here rather than typed (an expr
  -- mapping), which made each press a two-key command that flashed "gj" in the statusline's pending keys.
  { "k", function() vim.cmd("normal! " .. (vim.v.count == 0 and "gk" or vim.v.count .. "k")) end, "Move up" },
  { "j", function() vim.cmd("normal! " .. (vim.v.count == 0 and "gj" or vim.v.count .. "j")) end, "Move down" },

  -- Better indenting (with temporary Snacks indent animation disable)
  { "<", shift("<gv"), "Indent left", mode = "x" },
  { ">", shift(">gv"), "Indent right", mode = "x" },

  -- Paste over currently selected text without yanking it
  { "p", "P", "Paste, keep register", mode = "x", silent = true },

  -- Panes resizing
  { "+", ":vertical resize +5<CR>", "Increase width", silent = true },
  { "-", ":vertical resize -5<CR>", "Decrease width", silent = true },
  { "=", ":resize +5<CR>", "Increase height", silent = true },
  { "_", ":resize -5<CR>", "Decrease height", silent = true },

  -- Split line with X
  { "X", ":keeppatterns substitute/\\s*\\%#\\s*/\\r/e <bar> normal! ==^<cr>", "Split line at cursor", silent = true },

  -- Select all
  { "<C-a>", "ggVG", "Select all", silent = true },

  -- Clear search highlight
  { "<Esc>", ":nohlsearch<CR>", "Clear search highlight", silent = true },

  -- Change and delete using the black hole register
  { "<A-c>", '"_c', "Change to black hole register", silent = true },
  { "<A-d>", '"_d', "Delete to black hole register", silent = true },

  -- Undo tree: Neovim's own (:Undotree), opens or closes
  {
    "<leader>GU",
    function()
      vim.cmd.packadd("nvim.undotree")
      require("undotree").open()
    end,
    "Toggle UndoTree",
    silent = true,
  },

  -- The Lua ftplugin's <leader>! (after/ftplugin/lua.lua)
  { "<leader>!", mode = { "n", "x" }, icon = { icon = "", color = "red" } },
})
