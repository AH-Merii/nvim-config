-- Folds: nvim-origami's fold text, and every fold open when a file opens
local M = {}

M.plugins = {
  {
    src = "chrisgrieser/nvim-origami",
    -- with the first file; it sets up the buffers and windows already open when it loads
    phase = "buffer",
    setup = function()
      require("origami").setup({
        foldtext = {
          lineCount = {
            template = "󰘖 %d", -- `%d` is replaced with the number of folded lines
          },
        },
      })
    end,
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
