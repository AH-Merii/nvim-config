local M = {}

function M.setup()
  local autocmd = vim.api.nvim_create_autocmd
  local augroup = vim.api.nvim_create_augroup
  local user_group = augroup("UserAutocmds", { clear = true })

  -- Utility to sanitize and normalize command results
  local function sanitize_system_result(result)
    local _ = {}
    -- ok is true if exit code == 0 (success)
    _.ok = (result.code or 0) == 0
    _.stderr = (result.stderr or ""):gsub("%s+$", "")
    _.stdout = (result.stdout or ""):gsub("%s+$", "")
    _.output = _.stderr ~= "" and _.stderr or _.stdout
    if _.output == "" then
      _.output = "No output from ghostty command"
    end
    return _
  end

  -- Validate Ghostty config
  local function validate_ghostty_config()
    if vim.fn.executable("ghostty") ~= 1 then
      return
    end

    local validate = sanitize_system_result(vim.system({ "ghostty", "+validate-config" }, { text = true }):wait())

    if not validate.ok then
      vim.notify("󰧵  Invalid Ghostty config:\n" .. validate.output, vim.log.levels.WARN, { title = "Ghostty" })
      return false
    end

    return true
  end

  -- Reload Ghostty config (future CLI command)
  local function reload_ghostty_config()
    if vim.fn.executable("ghostty") ~= 1 then
      return
    end

    -- TODO Ghostty does not currently expose reload-config via the api, this is a placeholder function
    -- I need to replace '+reload-config' with the appropriate endpoint once it is supported
    local reload = sanitize_system_result(vim.system({ "ghostty", "+reload-config" }, { text = true }):wait())

    if not reload.ok then
      vim.notify("󰧵  Failed to reload Ghostty config:\n" .. reload.output, vim.log.levels.WARN, { title = "Ghostty" })
      return false
    end

    vim.notify("󰊠  Ghostty config reloaded!", vim.log.levels.INFO, { title = "Ghostty" })
    return true
  end

  -- Validate and optionally reload
  local function validate_and_reload_ghostty_config()
    -- Validate first
    if not validate_ghostty_config() then
      return
    end

    -- TODO: Reload (future CLI)
    -- reload_ghostty_config()
  end

  autocmd("BufWritePost", {
    group = user_group,
    pattern = {
      "*/ghostty/config",
    },
    callback = function() validate_and_reload_ghostty_config() end,
    desc = "Validate Ghostty config on save and reload if valid",
  })

  -- Disable automatic comment insertion on new lines
  autocmd("BufEnter", {
    group = user_group,
    callback = function() vim.opt.formatoptions:remove({ "c", "r", "o" }) end,
  })

  -- Wrap words softly in mail buffer
  autocmd("FileType", {
    group = user_group,
    pattern = "mail",
    callback = function()
      vim.opt_local.textwidth = 0
      vim.opt_local.wrapmargin = 0
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
      vim.opt_local.columns = 80
      vim.opt_local.colorcolumn = "80"
    end,
  })

  -- Highlight on yank
  autocmd("TextYankPost", {
    group = user_group,
    callback = function() vim.hl.hl_op({ higroup = "Search", timeout = 200 }) end,
  })

  -- Close specific filetypes with 'q'
  autocmd("FileType", {
    group = user_group,
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
    group = user_group,
    callback = function()
      local current_tab = vim.api.nvim_get_current_tabpage()
      vim.cmd("tabdo wincmd =")
      vim.api.nvim_set_current_tabpage(current_tab)
    end,
  })

  -- Show cursor line only in active window
  local cursor_group = augroup("CursorLine", { clear = true })
  autocmd({ "InsertLeave", "WinEnter" }, {
    group = cursor_group,
    callback = function() vim.opt_local.cursorline = true end,
  })
  autocmd({ "InsertEnter", "WinLeave" }, {
    group = cursor_group,
    callback = function() vim.opt_local.cursorline = false end,
  })

  -- Enable spell checking and wrapping for text-based files
  autocmd("FileType", {
    group = user_group,
    pattern = { "gitcommit", "oil", "markdown", "text", "tex", "NeogitCommitMessage", "typst" },
    callback = function()
      vim.opt_local.spell = true
      vim.opt_local.spelllang = "en"
      vim.opt_local.wrap = true
    end,
  })

  -- Fix terraform and HCL comment string
  autocmd("FileType", {
    group = user_group,
    pattern = { "terraform", "hcl" },
    callback = function(event) vim.bo[event.buf].commentstring = "# %s" end,
  })

  -- LSP progress as progress-messages, so vim.ui.progress_status() (in lualine) counts it (:h LspProgress).
  -- Silent: the Progress event still fires but no message is drawn, so lualine is the one place it shows.
  autocmd("LspProgress", {
    group = user_group,
    callback = function(ev)
      local value = ev.data.params.value
      if type(value) ~= "table" or not value.kind then
        return
      end
      local opts = {
        id = "lsp." .. ev.data.client_id .. "." .. tostring(ev.data.params.token),
        kind = "progress",
        source = "vim.lsp",
        title = value.title,
        status = value.kind ~= "end" and "running" or "success",
        percent = value.percentage,
      }
      vim._with({ silent = true }, function() vim.api.nvim_echo({ { value.message or "done" } }, false, opts) end)
    end,
  })

  -- Language servers' colors (vim.lsp.document_color, on by default, redrawn on edits only), drawn as a palette
  -- symbol at the line's end in the color instead of the built-in's background
  local color_ns = vim.api.nvim_create_namespace("config.document_color")
  local drawn = {} ---@type table<integer, integer> buffer -> the version its marks are for
  vim.lsp.document_color.enable(true, nil, {
    style = function(buf, range, hex)
      -- called for each color once per buffer version, after the built-in clears its own marks
      local version = vim.lsp.util.buf_versions[buf]
      if drawn[buf] ~= version then
        vim.api.nvim_buf_clear_namespace(buf, color_ns, 0, -1)
        drawn[buf] = version
      end
      local hl = "LspDocumentColorSymbol_" .. hex:sub(2)
      vim.api.nvim_set_hl(0, hl, { fg = hex, default = true })
      vim.api.nvim_buf_set_extmark(buf, color_ns, range.start_row, range.start_col, {
        virt_text = { { " \u{E22B}", hl } },
        virt_text_pos = "eol",
        strict = false,
      })
    end,
  })
  -- the built-in clears only its own marks when a server goes
  autocmd("LspDetach", {
    group = user_group,
    callback = function(ev)
      vim.api.nvim_buf_clear_namespace(ev.buf, color_ns, 0, -1)
      drawn[ev.buf] = nil
    end,
  })
end

return M
