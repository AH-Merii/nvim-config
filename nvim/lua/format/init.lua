-- Formatting: what formats a buffer, formatting it with one report of what ran, and formatting on save. The buffer's
-- language names its formatters (lua/lang/), the resolver finds their binaries (lua/tools/), and conform runs them,
-- through format/conform.lua, the only file that knows the plugin. Where none runs, an attached server formats.
--
-- Requiring this module loads no plugin: lsp/buffer.lua requires it at startup, and its key gates read M.has.

local tools = require("tools")

local M = {}

---@class format.Plan
---@field formatters string[] the formatters the buffer's language names, in the order they run
---@field run string[] of those, the ones that run now: binary found, not still being looked up (conform's check for one with no catalog binary)

-- Each buffer's plan, with the filetype and root it was made for. Dropped on FileType, BufFilePost (a new root),
-- DirChanged (a buffer that isn't a file has the cwd as its root), ToolsChanged for its root and a lookup finishing; a
-- filetype set without FileType (noautocmd) makes a new plan on the next read. A root that moves with no event (a
-- project marker made in a terminal) is not seen until one of these, or until M.buffer, which always makes a new plan.
-- Attached servers are not part of a plan: M.has and M.buffer read them live.
local plans = {} ---@type table<integer, { ft: string, root: string, plan: format.Plan }>

---@param root? string drops the plans of buffers in root, or every plan
local function drop(root)
  for buf, entry in pairs(plans) do
    if not root or entry.root == root then
      plans[buf] = nil
    end
  end
end

-- Made when the module loads, so plans are dropped before any later handler of these events reads them
do
  local group = vim.api.nvim_create_augroup("format.plans", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufFilePost", "BufWipeout" }, { group = group, callback = function(ev) plans[ev.buf] = nil end })
  vim.api.nvim_create_autocmd("DirChanged", { group = group, callback = function() drop() end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = tools.event, callback = function(ev) drop(ev.data.root) end })
end

---@param buf integer
---@return format.Plan plan, string root
local function make(buf)
  local found = require("lang").of(vim.bo[buf].filetype)
  local plan = { formatters = found and found.formatters or {}, run = {} } ---@type format.Plan
  -- Finding the root probes the file system; a buffer with no formatters needs none
  local root = #plan.formatters > 0 and tools.root(buf) or ""
  for _, name in ipairs(plan.formatters) do
    local bin = tools.catalog.binary("formatter", name)
    if bin then
      -- A lookup whose result did not change fires no ToolsChanged, so its end drops the plan itself
      local result = tools.get(bin, root) or tools.resolve(bin, root, function()
        vim.schedule(function() drop(root) end)
      end)
      if result and result.path then
        plan.run[#plan.run + 1] = name
      end
    elseif require("format.conform").available(name, buf) then
      plan.run[#plan.run + 1] = name
    end
  end
  return plan, root
end

---@param buf? integer
---@return integer
local function resolve_buf(buf) return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf end

--- What formats buf: the formatters its language names and those of them that run now. Cached per buffer; callers must
--- not modify it.
---@param buf? integer default the current buffer
---@return format.Plan
function M.plan(buf)
  buf = resolve_buf(buf)
  local ft = vim.bo[buf].filetype
  local entry = plans[buf]
  if not entry or entry.ft ~= ft then
    local plan, root = make(buf)
    entry = { ft = ft, root = root, plan = plan }
    plans[buf] = entry
  end
  return entry.plan
end

--- Whether buf has something to format it with: its language names a formatter (installed or not), or an attached
--- server formats it (formats a range, with range). The "formatter" need of the format keys: it makes no plan, so a
--- key press or a which-key rebuild can call it. Servers are read live, since registering a method fires no autocmd.
---@param buf? integer default the current buffer
---@param range? boolean
---@return boolean
function M.has(buf, range)
  buf = resolve_buf(buf)
  local found = require("lang").of(vim.bo[buf].filetype)
  if found and #found.formatters > 0 then
    return true
  end
  return #vim.lsp.get_clients({ bufnr = buf, method = range and "textDocument/rangeFormatting" or "textDocument/formatting" }) > 0
end

--- Formats buf with the formatters that run there, else with an attached server, and reports once what ran, what failed
--- (the formatter's or server's own message) or that nothing can format it. Formatters still being looked up are
--- waited for, as conform's command for them would.
---@param buf? integer default the current buffer
---@param opts? { async?: boolean } async defaults to true; in visual mode, conform formats the selection
function M.buffer(buf, opts)
  buf = resolve_buf(buf)
  opts = opts or {}
  local async = opts.async ~= false
  local ft = vim.bo[buf].filetype

  local found = require("lang").of(ft)
  local root = tools.root(buf)
  for _, name in ipairs(found and found.formatters or {}) do
    local bin = tools.catalog.binary("formatter", name)
    if bin then
      tools.wait(bin, root)
    end
  end
  plans[buf] = nil
  local names = M.plan(buf).run

  local filepath = vim.api.nvim_buf_get_name(buf)
  local filename = (filepath ~= "" and vim.fn.fnamemodify(filepath, ":t")) or "<buffer>"

  -- Where no formatter runs, conform falls back to a server that formats
  local has_lsp = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if client:supports_method("textDocument/formatting") or client:supports_method("textDocument/rangeFormatting") then
      has_lsp = true
      break
    end
  end

  local label
  if #names > 0 then
    label = table.concat(names, ", ")
  elseif has_lsp then
    label = "LSP"
  else
    vim.notify(string.format("No formatter or LSP available for filetype (%s)", ft), vim.log.levels.WARN, { title = "Conform" })
    return
  end

  require("format.conform").format({ async = async, bufnr = buf }, function(err, did_edit)
    if err then
      vim.notify(string.format("Formatting failed in %s with %s: %s", filename, label, err), vim.log.levels.ERROR, { title = "Conform" })
      return
    end
    if not did_edit then
      vim.notify(string.format("No changes made while formatting (%s)", ft), vim.log.levels.INFO, { title = "Conform" })
      return
    end
    vim.notify(string.format("Formatted %s with: %s", filename, label), vim.log.levels.INFO, { title = "Conform" })
  end)
end

local saving = true

--- Formatting on save, on by default: the state the <leader>Tf toggle reads and flips.
M.on_save = {
  ---@return boolean
  get = function() return saving end,
  ---@param on boolean
  set = function(on) saving = on end,
}

--- Sets conform up with the resolved binaries, and adds formatting on save and :FormatWithConform. Run from conform's
--- plugin spec.
function M.setup()
  require("format.conform").setup()
  local group = vim.api.nvim_create_augroup("format", { clear = true })
  -- Synchronous, so the file is written formatted
  vim.api.nvim_create_autocmd("BufWritePre", {
    group = group,
    callback = function(ev)
      if saving then
        M.buffer(ev.buf, { async = false })
      end
    end,
  })
  vim.api.nvim_create_user_command("FormatWithConform", function() M.buffer() end, { desc = "Format current buffer with Conform and print formatters used" })
end

return M
