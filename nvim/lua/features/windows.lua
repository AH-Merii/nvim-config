-- Windows and tmux: moving between Neovim windows and tmux panes with the same keys
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
    callback = set_keymaps,
  })
end

return M
