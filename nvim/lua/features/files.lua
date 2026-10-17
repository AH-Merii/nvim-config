-- Files: writing, quitting, scratch buffers, renaming the file, and checking a Ghostty config when it is written
local M = {}

function M.setup()
  local function icon(glyph, color) return { icon = glyph, color = color } end
  require("keys").feature("files")({
    { "<leader>.", function() Snacks.scratch({ ft = "markdown" }) end, "Toggle Scratch Buffer", icon = icon("󰎕", "grey") },
    { "<leader>lR", function() Snacks.rename.rename_file() end, "Rename File", icon = icon("󰑕", "green") },
  })

  require("keys").feature("files")({
    -- Fast saving
    { "<leader>w", ":write!<CR>", "Write", silent = true, icon = { icon = "", color = "green" } },
    { "<leader>q", ":q!<CR>", "Quit", silent = true, icon = { icon = "", color = "red" } },
  })

  local autocmd = vim.api.nvim_create_autocmd
  local group = vim.api.nvim_create_augroup("features.files", { clear = true })

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
    group = group,
    pattern = {
      "*/ghostty/config",
    },
    callback = function() validate_and_reload_ghostty_config() end,
    desc = "Validate Ghostty config on save and reload if valid",
  })
end

return M
