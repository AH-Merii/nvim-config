-- What applies to each buffer, for whatever shows it (the statusline, the tools indicator, :Status): the servers
-- running, the formatters and linters that will run, the missing tools, the tools root and the git checkout. What
-- will run is format.plan(buf).run and linting.plan(buf).run; the rest comes from lang.of, the tool resolver's
-- results, vim.lsp's clients and vim.fs.root. Each buffer's facts are cached until an event that can change them; User FactsChanged (M.event, data
-- { buf }) fires once when they did, so a statusline redraws once. A read is a table lookup.

local tools = require("tools")
local catalog = require("tools.catalog")
-- Required here so their plan caches drop on an event before these facts' handlers read the plans again
local format, linting = require("format"), require("linting")

local M = {}

M.event = "FactsChanged"

---@class ui.Facts
---@field root string the buffer's tools root (tools.root)
---@field repo? string the git checkout the buffer's folder is in (a .git dir or file above it); nil outside one
---@field servers string[] the servers attached and not stopping, by name, once each, in attach order
---@field formatters string[] the formatters that will run, in order
---@field linters string[] the linters that will run
---@field missing string[] catalog binaries the buffer's tools run that the resolver did not find
---@field unanswered boolean the root's project mise config waits for the project prompt's answer

local cache = {} ---@type table<integer, ui.Facts> buf -> its facts
local stale = {} ---@type table<integer, true> buffers whose cached facts an event may have changed
local before = {} ---@type table<integer, ui.Facts> buf -> its facts when it went stale, until the next flush
local detaching = {} ---@type table<integer, table<integer, true>> buf -> clients in its LspDetach, still attached
local waiting = {} ---@type table<integer, true> buffers waiting for a tool or project scan their facts left pending
local queued = false

--- The servers running on buf (lsp.running), less those in their LspDetach from it, by name.
---@param buf integer
---@return string[]
local function running(buf)
  local names, seen, skip = {}, {}, detaching[buf] or {}
  for _, client in ipairs(require("lsp").running(buf)) do
    if not seen[client.name] and not skip[client.id] then
      seen[client.name] = true
      names[#names + 1] = client.name
    end
  end
  return names
end

--- The git checkout buf's folder is in: a .git dir or file above it (a linked worktree has a file), nil outside one.
---@param buf integer
---@return string?
local function repo_of(buf)
  local folder = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p:h")
  return folder ~= "" and vim.fs.root(folder, ".git") or nil
end

local touch ---@type fun(buf: integer)

---@param buf integer
---@return ui.Facts
local function compute(buf)
  local found = require("lang").of(vim.bo[buf].filetype)
  local root = tools.root(buf)
  local facts = { root = root, servers = running(buf), formatters = {}, linters = {}, missing = {} } ---@type ui.Facts
  facts.repo = repo_of(buf)
  -- resolve starts what is not resolved yet; until it ends, a tool counts neither as found nor as missing
  local names = found and catalog.needed(found) or {}
  local pending = {}
  for _, bin in ipairs(names) do
    local result = tools.resolve(bin, root)
    if not result then
      pending[#pending + 1] = bin
    elseif not result.path then
      facts.missing[#facts.missing + 1] = bin
    end
  end
  if found then
    facts.formatters, facts.linters = format.plan(buf).run, linting.plan(buf).run
  end
  local project = tools.project(root)
  facts.unanswered = project ~= nil and #project.configs > 0 and project.choice == nil
  -- ToolsChanged fires only when a result differs from the one before a refresh, so wait for these ourselves
  if (#pending > 0 or not project) and not waiting[buf] then
    waiting[buf] = true
    tools.resolve_all(pending, root, function()
      tools.project(root, function()
        waiting[buf] = nil
        touch(buf)
      end)
    end)
  end
  return facts
end

--- Recomputes the stale buffers that were read before, and fires FactsChanged for each whose facts changed.
local function flush()
  queued = false
  local changed = before
  before, detaching = {}, {}
  for buf, old in pairs(changed) do
    if vim.api.nvim_buf_is_valid(buf) and cache[buf] then
      if stale[buf] then
        cache[buf], stale[buf] = compute(buf), nil
      end
      if not vim.deep_equal(old, cache[buf]) then
        vim.api.nvim_exec_autocmds("User", { pattern = M.event, modeline = false, data = { buf = buf } })
      end
    end
  end
end

local function queue()
  if not queued then
    queued = true
    vim.schedule(flush)
  end
end

--- Marks buf's facts stale; they are recomputed on the next read or the next tick, whichever comes first.
---@param buf integer
function touch(buf)
  if not cache[buf] then
    return
  end
  stale[buf] = true
  before[buf] = before[buf] or cache[buf]
  queue()
end

--- buf's facts. Callers must not modify them.
---@param buf? integer default current
---@return ui.Facts
function M.get(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return { root = tools.root(), servers = {}, formatters = {}, linters = {}, missing = {}, unanswered = false }
  end
  if not cache[buf] or stale[buf] then
    cache[buf], stale[buf] = compute(buf), nil
  end
  return cache[buf]
end

--- Drops every cached answer and (re)makes the handlers that mark facts stale.
function M.setup()
  cache, stale, before, detaching, waiting = {}, {}, {}, {}, {}
  local group = vim.api.nvim_create_augroup("ui.facts", { clear = true })
  local au = vim.api.nvim_create_autocmd
  au({ "FileType", "BufFilePost", "LspAttach" }, { group = group, callback = function(ev) touch(ev.buf) end })
  -- A checkout made since (git init) shows on the next visit, as the statusline's branch looks again then. Only the
  -- checkout is looked up again: the whole facts cost about 15 times as much, mostly tools.root
  au("BufEnter", {
    group = group,
    callback = function(ev)
      if cache[ev.buf] and not stale[ev.buf] and repo_of(ev.buf) ~= cache[ev.buf].repo then
        touch(ev.buf)
      end
    end,
  })
  au("LspDetach", {
    group = group,
    callback = function(ev)
      -- The detaching client is still attached while LspDetach runs
      detaching[ev.buf] = detaching[ev.buf] or {}
      detaching[ev.buf][ev.data.client_id] = true
      touch(ev.buf)
      queue() -- forgets the client on the next tick, read or not
    end,
  })
  au("User", {
    group = group,
    pattern = tools.event,
    callback = function(ev)
      for buf, facts in pairs(cache) do
        if facts.root == ev.data.root then
          touch(buf)
        end
      end
    end,
  })
  -- A buffer that is not a file takes the cwd as its root, and an unnamed one its checkout
  au("DirChanged", {
    group = group,
    callback = function()
      for buf in pairs(cache) do
        touch(buf)
      end
    end,
  })
  au({ "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev)
      cache[ev.buf], stale[ev.buf], before[ev.buf], waiting[ev.buf] = nil, nil, nil, nil
    end,
  })
end

M.setup()

return M
