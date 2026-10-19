-- The treesitter parsers each buffer needs, installed when a buffer first needs them (D116 to D121 in
-- docs/rearchitecture-decisions.md). A language needs its own parser and the languages nvim-treesitter's injections
-- query for it names, one level deep: their own injections aren't followed. nvim-treesitter's copy is installed even
-- for a parser Neovim bundles, for its indents and injections; Neovim's serves until it lands. Installs run once
-- a session per parser, only with a UI and installs on (tools.can_install), and only with tree-sitter, which the tool
-- resolver finds and the tools prompt offers. User ParsersChanged (M.event) says when a parser's state changed.

local tools = require("tools")

local M = {}

M.event = "ParsersChanged"

---@class parsers.Backend where parsers come from: nvim-treesitter (parsers.nvim_treesitter), or a fake in tests/unit
---@field available fun(lang: string): boolean nvim-treesitter can install lang
---@field installed fun(lang: string): boolean nvim-treesitter installed lang
---@field loadable fun(lang: string): boolean Neovim loads lang now: installed, or its own (lib/nvim/parser)
---@field injections fun(lang: string): string? the text of nvim-treesitter's injections query for lang, nil without one
---@field install fun(langs: string[], opts: { cli: string }, cb: fun(failed: string[])) installs with the tree-sitter at opts.cli; cb on the main loop
---@field update fun(langs: string[], cb: fun(failed: string[]))

---@class parsers.State
---@field state "installed"|"installing"|"failed"|"missing"|"none" none: no nvim-treesitter parser by that name
---@field reason? string why it failed, or why a missing one isn't installed

local backend = require("parsers.nvim_treesitter") ---@type parsers.Backend

local plans = {} ---@type table<string, string[]> filetype -> its parsers
local present = {} ---@type table<string, true> parsers known to be installed, which stay
local states = {} ---@type table<string, { state: "installing"|"failed", reason?: string, cli?: boolean, seq: integer }> this session's installs
local seq = 0 -- the order installs started in, so a retry keeps it
local waiting = {} ---@type table<integer, { cb: fun(lang: string), langs: table<string, true> }> buf -> what it waits for
local deferred = {} ---@type table<integer, fun(lang: string)> buf -> its callback, opened before installs could run

local title = "Parsers"

--------------------------------------------------------------------------------
-- What a language needs
--------------------------------------------------------------------------------

--- line without its comment: from a ";" outside a string to the end.
---@param line string
local function uncomment(line)
  local quoted = false
  for i = 1, #line do
    local c = line:sub(i, i)
    if c == '"' and line:sub(i - 1, i - 1) ~= "\\" then
      quoted = not quoted
    elseif c == ";" and not quoted then
      return line:sub(1, i - 1)
    end
  end
  return line
end

--- The languages lang's injections query sets by name, with those of the queries it inherits.
---@param lang string
---@param seen table<string, true>
---@param out table<string, true>
local function injected(lang, seen, out)
  if seen[lang] then
    return
  end
  seen[lang] = true
  local text = backend.injections(lang)
  if not text then
    return
  end
  for line in text:gmatch("[^\n]+") do
    local inherits = line:match("^%s*;+%s*inherits%s*:%s*(.-)%s*$")
    if inherits then
      for base in inherits:gmatch("[^,%s]+") do
        injected((base:gsub("^%((.*)%)$", "%1")), seen, out)
      end
    end
    -- Only a name the query sets: a language read from the text (@injection.language) is the file's to choose
    local code = uncomment(line)
    for name in code:gmatch('#set!%s+injection%.language%s+"([^"]+)"') do
      out[name] = true
    end
    for name in code:gmatch("#set!%s+injection%.language%s+([%w_]+)") do
      out[name] = true
    end
  end
end

---@param lang string
local function is_parser(lang) return backend.available(lang) end

--- The parsers a buffer of filetype ft needs: its own parser, then the languages its injections name, sorted. Empty
--- when there is no parser for ft.
---@param ft string
---@return string[]
function M.needed(ft)
  if plans[ft] then
    return plans[ft]
  end
  local own = ft ~= "" and vim.treesitter.language.get_lang(ft) or nil
  local list = {}
  if own and is_parser(own) then
    local names = {}
    injected(own, {}, names)
    names[own] = nil
    list = vim.tbl_filter(is_parser, vim.tbl_keys(names))
    table.sort(list)
    table.insert(list, 1, own)
  end
  plans[ft] = list
  return list
end

--------------------------------------------------------------------------------
-- States
--------------------------------------------------------------------------------

--- Where lang stands: a lookup, and a stat of nvim-treesitter's install dir while it isn't there.
---@param lang string
---@return parsers.State
function M.get(lang)
  if not present[lang] then
    present[lang] = backend.installed(lang) or nil
  end
  if present[lang] then
    return { state = "installed" }
  elseif states[lang] then
    return { state = states[lang].state, reason = states[lang].reason }
  elseif not backend.available(lang) then
    return { state = "none" }
  end
  return { state = "missing", reason = not tools.can_install() and "installs are off (vim.g.install_tools or no UI)" or nil }
end

--- Whether a buffer can attach with lang now: nvim-treesitter's copy, or until it lands Neovim's own.
---@param lang string
local function there(lang) return M.get(lang).state == "installed" or backend.loadable(lang) end

--- The parsers buf needs whose install failed.
---@param buf integer
---@return string[]
function M.missing(buf)
  return vim.tbl_filter(function(lang) return M.get(lang).state == "failed" end, M.needed(vim.bo[buf].filetype))
end

local pending ---@type table<string, true>?

--- Fires ParsersChanged for langs on the next tick, merged with others changed in this one.
---@param langs string[]
local function changed(langs)
  if not pending then
    pending = {}
    vim.schedule(function()
      local list = vim.tbl_keys(pending)
      pending = nil
      table.sort(list)
      vim.api.nvim_exec_autocmds("User", { pattern = M.event, modeline = false, data = { langs = list } })
    end)
  end
  for _, lang in ipairs(langs) do
    pending[lang] = true
  end
end

--------------------------------------------------------------------------------
-- Installs
--------------------------------------------------------------------------------

--- Calls back each buffer waiting on one of langs whose own parser is there now.
---@param langs string[]
local function landed(langs)
  for buf, wait in pairs(waiting) do
    local hit = false
    for _, lang in ipairs(langs) do
      if wait.langs[lang] then
        wait.langs[lang], hit = nil, true
      end
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      waiting[buf] = nil
    elseif hit then
      local own = M.needed(vim.bo[buf].filetype)[1]
      if next(wait.langs) == nil then
        waiting[buf] = nil
      end
      if own and there(own) then
        wait.cb(own)
      end
    end
  end
end

---@param list string[]
local function join(list) return table.concat(list, ", ") end

--- Installs langs, which this session hasn't tried yet or retries, as one group: one toast as it starts, one as it ends.
---@param langs string[]
---@param root string where tree-sitter is looked up
local function start(langs, root)
  for _, lang in ipairs(langs) do
    seq = seq + 1
    states[lang] = { state = "installing", seq = seq }
  end
  changed(langs)
  tools.resolve("tree-sitter", root, function(cli)
    if not cli.path then
      for _, lang in ipairs(langs) do
        states[lang] = { state = "failed", reason = "needs tree-sitter to build it", cli = true, seq = states[lang].seq }
      end
      return changed(langs)
    end
    vim.notify("Installing " .. join(langs), vim.log.levels.INFO, { title = title })
    backend.install(langs, { cli = cli.path }, function(failed)
      for _, lang in ipairs(langs) do
        if vim.list_contains(failed, lang) then
          states[lang] = { state = "failed", reason = "install failed (see :messages)", seq = states[lang].seq }
        else
          states[lang], present[lang] = nil, true
        end
      end
      if #failed == 0 then
        vim.notify("Installed " .. join(langs), vim.log.levels.INFO, { title = title })
      else
        vim.notify(("Couldn't install %s\nnvim-treesitter's errors are in :messages"):format(join(failed)), vim.log.levels.ERROR, { title = title })
      end
      changed(langs)
      landed(langs)
    end)
  end)
end

--- Makes buf's parsers there: cb(lang) runs with the buffer's own parser at once when it is there, and again each time
--- an install for the buffer lands while its own parser is there. Starts installing what nothing has tried this
--- session; a parser that failed waits for retry().
---@param buf integer
---@param cb fun(lang: string)
function M.ensure(buf, cb)
  local list = M.needed(vim.bo[buf].filetype)
  local own = list[1]
  if not own then
    -- a parser nvim-treesitter doesn't have, which Neovim or another plugin brings
    local lang = vim.bo[buf].filetype ~= "" and vim.treesitter.language.get_lang(vim.bo[buf].filetype)
    if lang and backend.loadable(lang) then
      cb(lang)
    end
    return
  end
  if there(own) then
    cb(own)
  end
  local todo, wait = {}, {}
  for _, lang in ipairs(list) do
    local state = M.get(lang).state
    if state == "missing" or state == "installing" then
      wait[lang] = true
    end
    if state == "missing" then
      table.insert(todo, lang)
    end
  end
  if next(wait) then
    waiting[buf] = { cb = cb, langs = wait }
  end
  if #todo == 0 then
    return
  elseif not tools.can_install() then
    -- A file opened at startup has its FileType before the UI attaches
    deferred[buf] = cb
    return
  end
  start(todo, tools.root(buf))
end

--- Installs langs again, after a failure.
---@param langs string[]
---@param root? string where tree-sitter is looked up, default the current buffer's
function M.retry(langs, root)
  local todo = vim.tbl_filter(function(lang) return states[lang] and states[lang].state == "failed" end, langs)
  if #todo > 0 and tools.can_install() then
    start(todo, root or tools.root(0))
  end
end

--- Updates installed parsers to nvim-treesitter's revisions.
---@param langs string[]
function M.update(langs)
  vim.notify("Updating " .. join(langs), vim.log.levels.INFO, { title = title })
  backend.update(langs, function(failed)
    if #failed > 0 then
      vim.notify("Couldn't update " .. join(failed), vim.log.levels.ERROR, { title = title })
    else
      vim.notify("Updated " .. join(langs), vim.log.levels.INFO, { title = title })
    end
    changed(langs)
    landed(langs)
  end)
end

--- opts.backend replaces where parsers come from (default nvim-treesitter) and drops every cached answer.
---@param opts? { backend?: parsers.Backend }
function M.setup(opts)
  if opts and opts.backend then
    backend = opts.backend
  end
  plans, present, states, waiting, deferred = {}, {}, {}, {}, {}
  local group = vim.api.nvim_create_augroup("parsers", { clear = true })
  vim.api.nvim_create_autocmd("UIEnter", {
    group = group,
    callback = function()
      local now = deferred
      deferred = {}
      for buf, cb in pairs(now) do
        if vim.api.nvim_buf_is_valid(buf) then
          M.ensure(buf, cb)
        end
      end
    end,
  })
  -- tree-sitter installed (or found by a rescan): build what waited for it
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = tools.event,
    callback = function(ev)
      local langs = vim.tbl_filter(function(lang) return states[lang].cli == true end, vim.tbl_keys(states))
      if #langs > 0 then
        table.sort(langs, function(a, b) return states[a].seq < states[b].seq end)
        M.retry(langs, ev.data.root)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev)
      waiting[ev.buf], deferred[ev.buf] = nil, nil
    end,
  })
end

return M
