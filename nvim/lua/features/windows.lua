-- Windows and tmux: moving between Neovim windows and tmux panes with the same keys, resizing, zen and zoom, and what
-- a window shows (numbers, indent guides, dimming, hidden characters)
local M = {}

M.plugins = {
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
      "TmuxNavigatorProcessList",
    },
  },
}

function M.setup()
  local group = vim.api.nvim_create_augroup("features.windows", { clear = true })
  vim.g.tmux_navigator_no_wrap = 1

  -- Reusable function to register keymaps in different contexts
  local function set_keymaps()
    vim.keymap.set({ "n", "t" }, "<C-h>", "<cmd>TmuxNavigateLeft<cr>")
    vim.keymap.set({ "n", "t" }, "<C-j>", "<cmd>TmuxNavigateDown<cr>")
    vim.keymap.set({ "n", "t" }, "<C-k>", "<cmd>TmuxNavigateUp<cr>")
    vim.keymap.set({ "n", "t" }, "<C-l>", "<cmd>TmuxNavigateRight<cr>")
  end

  -- Register once globally
  set_keymaps()

  -- Re-register for terminal buffers to prevent literal command injection
  vim.api.nvim_create_autocmd("TermOpen", {
    group = group,
    callback = set_keymaps,
  })

  local function icon(glyph, color) return { icon = glyph, color = color } end
  require("keys").feature("windows")({
    { "<C-W>z", function() Snacks.zen() end, "Toggle Zen Mode", icon = icon("󰫢", "yellow") },
    { "<C-W>Z", function() Snacks.zen.zoom() end, "Toggle Zoom", icon = icon("󰘖", "yellow") },
  })

  -- Its toggles, once snacks is loaded: a press flips one, says so, and its label in the popup follows it
  require("features").at_very_lazy(
    function()
      require("keys").feature("windows")({
        { "<leader>TL", toggle = Snacks.toggle.option("relativenumber", { name = "Relative Number" }) },
        { "<leader>Tl", toggle = Snacks.toggle.line_number() },
        { "<leader>Tg", toggle = Snacks.toggle.indent() },
        { "<leader>TD", toggle = Snacks.toggle.dim() },
        { "<leader>TH", toggle = Snacks.toggle.option("list", { name = "Hidden Chars" }) },
      })
    end
  )

  require("keys").feature("windows")({
    -- Panes resizing
    { "+", ":vertical resize +5<CR>", "Increase width", silent = true },
    { "-", ":vertical resize -5<CR>", "Decrease width", silent = true },
    { "=", ":resize +5<CR>", "Increase height", silent = true },
    { "_", ":resize -5<CR>", "Decrease height", silent = true },
  })

  local autocmd = vim.api.nvim_create_autocmd

  -- Close specific filetypes with 'q'. Not language rows (keys.language): a row yields to the buffer's own map, and the
  -- runtime's man ftplugin and checkhealth map q themselves (runtime/ftplugin/man.vim:29, lua/vim/health.lua:474)
  autocmd("FileType", {
    group = group,
    pattern = {
      "PlenaryTestPopup",
      "help",
      "lspinfo",
      "man",
      "notify",
      "qf",
      "spectre_panel",
      "startuptime",
      "tsplayground",
      "checkhealth",
      "netrw",
      "Jaq",
      "git",
      "oil",
      "lir",
    },
    callback = function(event)
      vim.bo[event.buf].buflisted = false
      vim.keymap.set("n", "q", "<cmd>close<cr>", {
        buf = event.buf,
        silent = true,
        desc = "Close window",
      })
    end,
  })

  -- Resize windows equally when Neovim is resized
  autocmd("VimResized", {
    group = group,
    callback = function()
      local current_tab = vim.api.nvim_get_current_tabpage()
      vim.cmd("tabdo wincmd =")
      vim.api.nvim_set_current_tabpage(current_tab)
    end,
  })

  -- Show cursor line only in active window
  autocmd({ "InsertLeave", "WinEnter" }, {
    group = group,
    callback = function() vim.opt_local.cursorline = true end,
  })
  autocmd({ "InsertEnter", "WinLeave" }, {
    group = group,
    callback = function() vim.opt_local.cursorline = false end,
  })
end

return M
