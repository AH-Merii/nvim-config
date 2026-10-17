return {

  -- Heuristically set buffer options
  -- {
  -- 	"tpope/vim-sleuth",
  -- },

  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {},
  },

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
    init = function()
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
    end,
  },

  -- Better folding
  {
    "chrisgrieser/nvim-origami",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = { "BufReadPre", "BufWinEnter" },
    init = function()
      vim.opt.foldlevel = 99
      vim.opt.foldlevelstart = 99

      vim.opt.fillchars = {
        fold = " ",
        foldopen = "",
        foldclose = "",
        foldsep = " ",
      }
    end,
    opts = {
      foldtext = {
        lineCount = {
          template = "󰘖 %d", -- `%d` is replaced with the number of folded lines
        },
      },
    },
  },
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
  },
  {
    "AH-Merii/github-pr-reviewer.nvim",
    cmd = { "PRReviewMenu", "PRSuggestChange" },
    opts = {
      pr_list_limit = 250,
    },
    init = function()
      -- PR review works on the repo of the cwd, so its keys act while that repo has a GitHub remote. git is asked each
      -- time the cwd changes; until it answers, the new cwd's keys do not act.
      local github = {} ---@type table<string, boolean>
      local function look_up()
        local cwd = vim.fn.getcwd()
        github[cwd] = nil
        vim.system(
          { "git", "-C", cwd, "remote", "-v" },
          { text = true },
          function(out) github[cwd] = out.code == 0 and out.stdout:find("github.com", 1, true) ~= nil end
        )
      end
      local keys = require("keys")
      keys.need("github", function() return github[vim.fn.getcwd()] == true end)
      local icon = { icon = "", color = "cyan" }
      keys.feature("pr review", { need = "github", icon = icon })({
        { "<leader>p", "<cmd>PRReviewMenu<cr>", "PR Review Menu" },
        { "<leader>p", ":<C-u>'<,'>PRSuggestChange<CR>", "Suggest change", mode = "x" },
      })
      vim.api.nvim_create_autocmd("DirChanged", {
        group = vim.api.nvim_create_augroup("PRReviewKeys", { clear = true }),
        callback = look_up,
      })
      look_up()
    end,
  },
}
