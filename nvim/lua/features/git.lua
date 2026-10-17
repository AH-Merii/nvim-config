-- Git: gitsigns' hunks, signs and blame, and diffview

local specs = {
  {
    "lewis6991/gitsigns.nvim",
    lazy = false,
    config = function()
      local gs = require("gitsigns")
      local gsc = require("gitsigns.config")
      -- stage_hunk() stages an unstaged hunk under the cursor and unstages a staged one
      local function unstage_hunk()
        local lnum = vim.fn.line(".")
        for _, hunk in ipairs(require("gitsigns").get_hunks() or {}) do
          local first = math.min(math.max(hunk.added.start, 1), vim.fn.line("$"))
          if lnum >= first and lnum <= math.max(hunk.added.start + hunk.added.count - 1, first) then
            return vim.notify("The hunk under the cursor is not staged", vim.log.levels.WARN, { title = "gitsigns" })
          end
        end
        require("gitsigns").stage_hunk()
      end

      -- The hunk keys act where gitsigns is attached: it sets the status dict then, and clears it when it detaches
      -- (e.g. after the file is renamed out of the repo)
      local keys = require("keys")
      keys.need("git", function(buf) return vim.b[buf].gitsigns_status_dict ~= nil end)
      keys.feature("git", { need = "git" })({
        { "[g", function() require("gitsigns").nav_hunk("prev", { navigation_message = false }) end, "git hunk", icon = { icon = "", color = "green" } },
        { "]g", function() require("gitsigns").nav_hunk("next", { navigation_message = false }) end, " git hunk", icon = { icon = "", color = "green" } },
        { "<leader>gb", function() require("gitsigns").blame_line() end, "Blame", icon = { icon = "󰩔", color = "yellow" } },
        { "<leader>gd", function() require("gitsigns").preview_hunk() end, "Diff (Preview)", icon = { icon = "󰦓", color = "cyan" } },
        { "<leader>Gr", function() require("gitsigns").reset_hunk() end, "Reset Hunk", icon = { icon = "󰁯", color = "orange" } },
        { "<leader>GR", function() require("gitsigns").reset_buffer() end, "Reset Buffer", icon = { icon = "󱄍", color = "red" } },
        { "<leader>Gs", function() require("gitsigns").stage_hunk() end, "Stage Hunk", icon = { icon = "", color = "green" } },
        { "<leader>Gu", unstage_hunk, "Unstage Hunk", icon = { icon = "", color = "yellow" } },
        { "<leader>Gd", function() vim.cmd("Gitsigns diffthis HEAD") end, "Diff (vs HEAD)", icon = { icon = "", color = "purple" } },
        {
          "<leader>TG",
          toggle = Snacks.toggle.new({
            name = "Git Signs Column",
            get = function() return gsc.config.signcolumn end,
            set = function(state) gs.toggle_signs(state) end,
          }),
        },
      })
      keys.feature("git")({
        -- high level group for Git actions (capital G to mirror your <leader>T etc.)
        { "<leader>G", group = "Git (Actions)", icon = { icon = "", color = "cyan" } },
        { "<leader>g", group = "Git (Inspect)", icon = { icon = "", color = "cyan" } },
      })

      gs.setup({
        signs = {
          add = { text = "" }, -- added line
          change = { text = "" }, -- modified line
          delete = { text = "" }, -- deleted line
          topdelete = { text = "" },
          changedelete = { text = "󰦒" },
          untracked = { text = "" },
        },
        signs_staged = {
          add = { text = "󰐖" },
          change = { text = "" },
          delete = { text = "󰍵" },
          topdelete = { text = "󰍵" },
          changedelete = { text = "󰦓" },
          untracked = { text = "󰄲" },
        },
        signcolumn = true,
        numhl = false,
        linehl = false,
        word_diff = false,
        watch_gitdir = {
          follow_files = true,
        },
        attach_to_untracked = true,
        current_line_blame = false, -- toggleable via :Gitsigns toggle_current_line_blame
        current_line_blame_opts = {
          virt_text = true,
          virt_text_pos = "eol", -- 'eol' | 'overlay' | 'right_align'
          delay = 1000,
          ignore_whitespace = false,
        },
        current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
        sign_priority = 6,
        status_formatter = nil,
        update_debounce = 200,
        max_file_length = 40000,
        preview_config = {
          border = "rounded",
          style = "minimal",
          relative = "cursor",
          row = 0,
          col = 1,
        },
      })
    end,
  },

  {
    "sindrets/diffview.nvim",
    event = "VeryLazy",
    cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
  },
}

return { plugins = specs }
