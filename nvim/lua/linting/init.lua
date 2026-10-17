-- Linting: which linters run on a buffer, running them with the binaries the resolver finds, and keeping their findings
-- in step with the servers that report the same ones. The buffer's language names its linters (lua/lang/), the
-- resolver finds their binaries (lua/tools/), and nvim-lint runs them, through linting/nvim_lint.lua, the only file
-- that knows the plugin. Named linting/ because nvim-lint's own module is lint/.
--
-- Requiring this module loads no plugin: core/lsp.lua requires it at startup, and its key gates read M.has.

local tools = require("tools")

local M = {}

---@class linting.Plan
---@field linters string[] the linters the buffer's language names, in the order they run
---@field run string[] of those, the ones that run now: not covered, and their binary found
---@field covered table<string, string> linter -> its server, for each linter whose server is attached to the buffer

-- Each buffer's plan, with the filetype and root it was made for. Dropped on FileType, LspAttach and LspDetach (what is
-- covered; again once the detaching client is gone, since it still counts as attached while LspDetach runs),
-- BufFilePost (a new root), DirChanged (a buffer that isn't a file has the cwd as its root), ToolsChanged for its root
-- and a lookup finishing; a filetype set without FileType (noautocmd) makes a new plan on the next read. A root that
-- moves with no event (a project marker made in a terminal) is not seen by M.plan until one of these; a lint, which
-- finds the root anyway, makes a new plan when it moved (plan_in).
local plans = {} ---@type table<integer, { ft: string, root: string, plan: linting.Plan }>

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
  local group = vim.api.nvim_create_augroup("linting.plans", { clear = true })
  vim.api.nvim_create_autocmd({ "FileType", "BufFilePost", "BufWipeout", "LspAttach" }, { group = group, callback = function(ev) plans[ev.buf] = nil end })
  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(ev)
      plans[ev.buf] = nil
      vim.schedule(function() plans[ev.buf] = nil end)
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", { group = group, callback = function() drop() end })
  vim.api.nvim_create_autocmd("User", { group = group, pattern = tools.event, callback = function(ev) drop(ev.data.root) end })
end

--- Whether a server that reports linter name's findings runs on buf (attached and not stopping).
---@param name string
---@param buf integer
local function covered(name, buf)
  local found = require("lang").of(vim.bo[buf].filetype)
  local server = found and found.covered_by[name]
  return server ~= nil and #require("core.lsp_servers").running(buf, server) > 0
end

---@param buf integer
---@return linting.Plan plan, string root
local function make(buf)
  local found = require("lang").of(vim.bo[buf].filetype)
  local plan = { linters = found and found.linters or {}, run = {}, covered = {} } ---@type linting.Plan
  -- Finding the root probes the file system; a buffer with no linters needs none
  local root = #plan.linters > 0 and tools.root(buf) or ""
  for _, name in ipairs(plan.linters) do
    local server = found and found.covered_by[name]
    if server and #require("core.lsp_servers").running(buf, server) > 0 then
      plan.covered[name] = server
    else
      -- A binary not resolved yet counts as missing; a lookup whose result did not change fires no ToolsChanged, so
      -- its end drops the plan itself
      local bin = require("linting.nvim_lint").binary(name)
      local result = bin and (tools.get(bin, root) or tools.resolve(bin, root, function()
        vim.schedule(function() drop(root) end)
      end))
      if not bin or (result and result.path) then
        plan.run[#plan.run + 1] = name
      end
    end
  end
  return plan, root
end

---@param buf? integer
---@return integer
local function resolve_buf(buf) return (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf end

--- Which linters apply to buf and which of them run now. Cached per buffer; callers must not modify it.
---@param buf? integer default the current buffer
---@return linting.Plan
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

--- buf's plan, made again when the cached one was made for another root than root, buf's root now.
---@param buf integer
---@param root string
---@return linting.Plan
local function plan_in(buf, root)
  if plans[buf] and plans[buf].root ~= root then
    plans[buf] = nil
  end
  return M.plan(buf)
end

--- Lints buf, whose root is root, with names.
---@param buf integer
---@param names string[]
---@param root string
local function lint(buf, names, root)
  -- nvim-lint lints the current buffer
  vim.api.nvim_buf_call(buf, function()
    require("linting.nvim_lint").lint(names, {
      root = root,
      runs = function(name) return vim.list_contains(plan_in(buf, root).run, name) end,
      covered = covered,
    })
  end)
end

--- Whether buf's language names a linter, installed or not: the "linter" need. A lookup, so a key press or a which-key
--- rebuild can call it.
---@param buf? integer default the current buffer
---@return boolean
function M.has(buf)
  local found = require("lang").of(vim.bo[resolve_buf(buf)].filetype)
  return found ~= nil and #found.linters > 0
end

--- Lints buf with names (default: every linter its language names), running those of them that run now, each with the
--- binary the resolver found. A linter whose binary is missing is skipped; one still resolving is skipped too, and
--- buf lints again with it once it is found.
---@param buf? integer default the current buffer
---@param names? string[]
function M.buffer(buf, names)
  buf = resolve_buf(buf)
  if not names then
    local found = require("lang").of(vim.bo[buf].filetype)
    names = found and found.linters or {}
  end
  if #names > 0 then
    lint(buf, names, tools.root(buf))
  end
end

--- Sets nvim-lint up with the resolved binaries; lints a buffer on entering it, writing it and leaving insert mode;
--- drops a linter's findings when its server attaches; and lints the loaded buffers of a root again when ToolsChanged
--- says one of their linters was found, installed or went missing. Run from nvim-lint's plugin spec.
function M.setup()
  local adapter = require("linting.nvim_lint")
  adapter.setup()
  local group = vim.api.nvim_create_augroup("linting", { clear = true })

  -- Drop what a linter reported before its server attached
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      for linter, server in pairs(require("lang").views().covered_by) do
        if client and client.name == server then
          vim.diagnostic.reset(adapter.namespace(linter), ev.buf)
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, { group = group, callback = function(ev) M.buffer(ev.buf) end })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = tools.event,
    callback = function(ev)
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local found = vim.api.nvim_buf_is_loaded(buf) and require("lang").of(vim.bo[buf].filetype)
        local names = found and found.linters or {}
        local changed = vim.tbl_filter(function(name) return vim.list_contains(ev.data.tools, adapter.binary(name)) end, names)
        if #changed > 0 and tools.root(buf) == ev.data.root then
          for _, name in ipairs(changed) do
            vim.diagnostic.reset(adapter.namespace(name), buf)
          end
          lint(buf, changed, ev.data.root)
        end
      end
    end,
  })
end

return M
