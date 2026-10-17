-- Folds: nvim-origami's fold text, and every fold open when a file opens
local M = {}

M.plugins = {
  {
    "chrisgrieser/nvim-origami",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = { "BufReadPre", "BufWinEnter" },
    opts = {
      foldtext = {
        lineCount = {
          template = "󰘖 %d", -- `%d` is replaced with the number of folded lines
        },
      },
    },
  },
}

function M.setup()
  vim.opt.foldlevel = 99
  vim.opt.foldlevelstart = 99

  vim.opt.fillchars = {
    fold = " ",
    foldopen = "",
    foldclose = "",
    foldsep = " ",
  }
end

return M
