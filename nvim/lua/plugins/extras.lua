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
    "nvim-mini/mini.icons",
    -- VeryLazy, not lazy = true: snacks never requires mini.icons, it only reads the MiniIcons global that setup() sets
    event = "VeryLazy",
    opts = {},
    init = function()
      -- diffview and lualine's filetype icons require nvim-web-devicons; mini.icons stands in for it
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
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
    "brenoprata10/nvim-highlight-colors",
    opts = {
      render = "virtual",
      virtual_symbol = "",
      ---Set virtual symbol suffix (defaults to '')
      virtual_symbol_prefix = " ",

      ---Set virtual symbol suffix (defaults to ' ')
      virtual_symbol_suffix = "",
      ---Set virtual symbol position()
      ---@usage 'inline'|'eol'|'eow'
      ---inline mimics VS Code style
      ---eol stands for `end of column` - Recommended to set `virtual_symbol_suffix = ''` when used.
      ---eow stands for `end of word` - Recommended to set `virtual_symbol_prefix = ' ' and virtual_symbol_suffix = ''` when used.
      virtual_symbol_position = "eol",
    },
    -- The plugin re-renders the visible rows on every WinScrolled: with 'scrolloff' 999 that is every j, and every
    -- frame of a smooth scroll. These keep every color it shows while cutting that work
    -- (docs/profiling-scrolling.md).
    config = function(_, opts)
      require("nvim-highlight-colors").setup(opts)
      local utils = require("nvim-highlight-colors.utils")
      local colors = require("nvim-highlight-colors.color.utils")
      local patterns = require("nvim-highlight-colors.color.patterns")

      -- Language server colors come from Neovim's own vim.lsp.document_color, on by default, which redraws on
      -- edits only. The plugin asked every server again on each scroll, calling vim.version() (1.7 ms on
      -- nightly) per server each time. The built-in is drawn the way the plugin draws: the symbol at the line's end.
      utils.highlight_with_lsp = function() end
      local ns = vim.api.nvim_create_namespace("config.document_color")
      local drawn = {} ---@type table<integer, integer> buffer -> the version its marks are for
      vim.lsp.document_color.enable(true, nil, {
        style = function(buf, range, hex)
          -- called for each color once per buffer version, after the built-in clears its own marks
          local version = vim.lsp.util.buf_versions[buf]
          if drawn[buf] ~= version then
            vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
            drawn[buf] = version
          end
          local hl = "LspDocumentColorSymbol_" .. hex:sub(2)
          vim.api.nvim_set_hl(0, hl, { fg = hex, default = true })
          vim.api.nvim_buf_set_extmark(buf, ns, range.start_row, range.start_col, {
            virt_text = { { opts.virtual_symbol_prefix .. opts.virtual_symbol .. opts.virtual_symbol_suffix, hl } },
            virt_text_pos = "eol",
            strict = false,
          })
        end,
      })
      -- the built-in clears only its own marks when a server goes
      vim.api.nvim_create_autocmd("LspDetach", {
        callback = function(ev)
          vim.api.nvim_buf_clear_namespace(ev.buf, ns, 0, -1)
          drawn[ev.buf] = nil
        end,
      })

      -- A match's color depends only on its text, except var(--x), which is looked up in the buffer. Most
      -- matches in code are not colors (":" or "=" and a word, e.g. "= true"), and finding that out is the slow part.
      local get_color_value = colors.get_color_value
      local none = {}
      local cache = {} ---@type table<string, string|table>
      colors.get_color_value = function(color, row_offset, custom_colors, enable_short_hex)
        if patterns.is_var_color(color) then
          return get_color_value(color, row_offset, custom_colors, enable_short_hex)
        end
        -- blink's menu calls it without the options the buffer render passes
        local key = ("%s\0%s\0%s"):format(color, tostring(custom_colors), tostring(enable_short_hex))
        local hit = cache[key]
        if hit == nil then
          hit = get_color_value(color, row_offset, custom_colors, enable_short_hex) or none
          cache[key] = hit
        end
        return hit ~= none and hit or nil
      end

      -- The matches in a line depend only on its text, so a scroll scans just the lines it brings into view. The
      -- plugin's own scan runs on one line at a time, by handing it that line as the buffer's contents.
      local buffer_utils = require("nvim-highlight-colors.buffer_utils")
      local get_positions = buffer_utils.get_positions_by_regex
      local get_contents = buffer_utils.get_buffer_contents ---@type fun(min_row: integer, max_row: integer, buf: integer): string[]
      local lines_cache, cached = {}, 0 ---@type table<string, table<string, table[]>>, integer
      buffer_utils.get_positions_by_regex = function(pats, min_row, max_row, buf, row_offset)
        if cached > 10000 then
          lines_cache, cached = {}, 0
        end
        local key = table.concat(pats, "\1")
        local by_line = lines_cache[key] or {}
        lines_cache[key] = by_line
        local positions = {}
        for i, line in ipairs(get_contents(min_row, max_row, buf)) do
          local found = by_line[line]
          if not found then
            buffer_utils.get_buffer_contents = function() return { line } end
            local ok, ret = pcall(get_positions, pats, 0, 1, buf, 1) -- rows come back as 0
            buffer_utils.get_buffer_contents = get_contents
            found = ok and ret or {}
            by_line[line], cached = found, cached + 1
          end
          for _, p in ipairs(found) do
            positions[#positions + 1] = {
              value = p.value,
              row = i + min_row - row_offset,
              start_column = p.start_column,
              end_column = p.end_column,
            }
          end
        end
        return positions
      end
    end,
  },
  {
    "AH-Merii/github-pr-reviewer.nvim",
    cmd = { "PRReviewMenu", "PRSuggestChange" },
    opts = {
      pr_list_limit = 250,
    },
    init = function()
      -- PR review works on the repo of the cwd, so map it while that repo has a GitHub remote
      local function map_pr_keys()
        local cwd = vim.fn.getcwd()
        vim.system({ "git", "-C", cwd, "remote", "-v" }, { text = true }, function(out)
          local github = out.code == 0 and out.stdout:find("github.com", 1, true) ~= nil
          vim.schedule(function()
            if vim.fn.getcwd() ~= cwd then
              return
            end
            if github then
              vim.keymap.set("n", "<leader>p", "<cmd>PRReviewMenu<cr>", { desc = "PR Review Menu" })
              vim.keymap.set("x", "<leader>p", ":<C-u>'<,'>PRSuggestChange<CR>", { desc = "Suggest change" })
            else
              pcall(vim.keymap.del, "n", "<leader>p")
              pcall(vim.keymap.del, "x", "<leader>p")
            end
          end)
        end)
      end
      vim.api.nvim_create_autocmd("DirChanged", {
        group = vim.api.nvim_create_augroup("PRReviewKeys", { clear = true }),
        callback = map_pr_keys,
      })
      map_pr_keys()
    end,
  },
}
