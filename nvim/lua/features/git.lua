-- Git: gitsigns' hunks, signs and blame, diffview, and PR review on GitHub
local M = {}

-- Not mapped: call with :lua require("features.git").copyFilePathAndLineNumber()
-- Copy the current file path and line number to the clipboard, use GitHub URL if in a Git repository
M.copyFilePathAndLineNumber = function()
  local current_file = vim.fn.expand("%:p")
  local current_line = vim.fn.line(".")
  local is_git_repo = vim.fn.system("git rev-parse --is-inside-work-tree"):match("true")

  if is_git_repo then
    local current_repo = vim.fn.systemlist("git remote get-url origin")[1]
    local current_branch = vim.fn.systemlist("git rev-parse --abbrev-ref HEAD")[1]

    -- Convert Git URL to GitHub web URL format
    current_repo = current_repo:gsub("git@github.com:", "https://github.com/")
    current_repo = current_repo:gsub("%.git$", "")

    -- Remove leading system path to repository root
    local repo_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
    if repo_root then
      current_file = current_file:sub(#repo_root + 2)
    end

    local url = string.format("%s/blob/%s/%s#L%s", current_repo, current_branch, current_file, current_line)
    vim.fn.setreg("+", url)
    print("Copied to clipboard: " .. url)
  else
    -- If not in a Git directory, copy the full file path
    vim.fn.setreg("+", current_file .. "#L" .. current_line)
    print("Copied full path to clipboard: " .. current_file .. "#L" .. current_line)
  end
end

local specs = {
  {
    src = "lewis6991/gitsigns.nvim",
    -- before the first file opens, so it attaches to it
    phase = "startup",
    setup = function()
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

  -- `nvim +DiffviewOpen` runs before VeryLazy; its plugin/ file defines the real commands (plugin/diffview.lua:23,27)
  { src = "sindrets/diffview.nvim", cmd = { "DiffviewOpen", "DiffviewFileHistory" } },
}
table.insert(specs, {
  src = "AH-Merii/github-pr-reviewer.nvim",
  -- Not at VeryLazy: its setup maps <C-h>, <C-l> and <C-e> globally, outside review mode falling back to Neovim's
  -- own keys (github-pr-reviewer/init.lua:1397-1424, called from setup at :5023), which would replace the window
  -- keys (features/windows.lua). The two commands the <leader>p rows run load it, as before
  phase = "on_demand",
  cmd = { "PRReviewMenu", "PRSuggestChange" },
  setup = function() require("github-pr-reviewer").setup({ pr_list_limit = 250 }) end,
})
M.plugins = specs

function M.setup()
  local keys = require("keys")

  -- The git needs, cached by the events that change them: a need is read on each press and popup rebuild
  local cwd_repo = {} ---@type table<string, boolean> cwd -> in a repo; emptied when the cwd changes
  local file_repo = {} ---@type table<integer, { file: string, repo: boolean, remote?: boolean }> by buffer, for its file
  -- The cwd is in a repo: the pickers act on it
  keys.need("git cwd", function()
    local cwd = vim.fn.getcwd()
    if cwd_repo[cwd] == nil then
      cwd_repo[cwd] = Snacks.git.get_root(cwd) ~= nil
    end
    return cwd_repo[cwd]
  end)
  -- The buffer's file is in a repo; that repo has a remote
  keys.need("git file", function(buf)
    local f = file_repo[buf]
    return f ~= nil and f.file == vim.api.nvim_buf_get_name(buf) and f.repo
  end)
  keys.need("git remote", function(buf)
    local f = file_repo[buf]
    return f ~= nil and f.file == vim.api.nvim_buf_get_name(buf) and f.remote == true
  end)

  ---@param buf integer
  local function look_up_file(buf)
    local file = vim.api.nvim_buf_get_name(buf)
    local root = vim.bo[buf].buftype == "" and file ~= "" and Snacks.git.get_root(file) or nil
    local entry = { file = file, repo = root ~= nil }
    file_repo[buf] = entry
    if root then
      vim.system({ "git", "-C", root, "remote" }, { text = true }, function(out) entry.remote = out.code == 0 and vim.trim(out.stdout) ~= "" end)
    end
  end

  -- The events that fill the caches, made once with the needs and their caches
  local group = vim.api.nvim_create_augroup("features.git", { clear = true })
  vim.api.nvim_create_autocmd("DirChanged", { group = group, callback = function() cwd_repo = {} end })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufFilePost" }, {
    group = group,
    callback = function(ev) look_up_file(ev.buf) end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", { group = group, callback = function(ev) file_repo[ev.buf] = nil end })

  local function icon(glyph, color) return { icon = glyph, color = color } end
  --   Git Tools: Interact with branches, logs, and diffs
  -- These act on the repo of the cwd
  keys.feature("git", { need = "git cwd" })({
    { "<leader>gB", function() Snacks.picker.git_branches() end, "Branches", icon = icon("", "grey") },
    { "<leader>gl", function() Snacks.picker.git_log() end, "Log", icon = icon("", "orange") },
    { "<leader>gs", function() Snacks.picker.git_status() end, "Status", icon = icon("󰊢", "cyan") },
    { "<leader>gS", function() Snacks.picker.git_stash() end, "Stashes", icon = icon("󰀼", "grey") },
    { "<leader>gD", function() Snacks.picker.git_diff() end, "Diff (Hunks)", icon = icon("", "cyan") },
  })
  -- These act on the buffer's file
  keys.feature("git", { need = "git file" })({
    { "<leader>gL", function() Snacks.picker.git_log_line() end, "Log (Line)", icon = icon("", "yellow") },
    { "<leader>gf", function() Snacks.picker.git_log_file() end, "Log (File)", icon = icon("", "blue") },
  })
  -- This needs a remote on the buffer's repo
  keys.feature("git")({ "<leader>GB", function() Snacks.gitbrowse() end, "Open in Git Browser", need = "git remote", icon = icon("󰖟", "grey") })

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
  keys.need("github", function() return github[vim.fn.getcwd()] == true end)
  local icon = { icon = "", color = "cyan" }
  keys.feature("pr review", { need = "github", icon = icon })({
    { "<leader>p", "<cmd>PRReviewMenu<cr>", "PR Review Menu" },
    { "<leader>p", ":<C-u>'<,'>PRSuggestChange<CR>", "Suggest change", mode = "x" },
  })
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = look_up,
  })
  look_up()
end

return M
