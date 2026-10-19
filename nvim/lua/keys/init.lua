-- Every key is a row: ours, a plugin's or Neovim's own. A row with a need acts only where the need holds, and the
-- popup lists it only there (docs/rearchitecture-decisions.md, D48, D49, D132 and D133).
--
--   local key = require("keys").feature("lsp")          -- an adder for one owner
--   key({ "gd", function() Snacks.picker.lsp_definitions() end, "Definition", need = "definition" })
--   keys.need("a fold here", function(buf, win) return win ~= nil and … end)
--   keys.language("python")({ "]]", label = "Next top-level def/class" })
--   keys.holds("rename", buf)  -- what a press of grn gets now
--   keys.menu(buf, "n")        -- what the popup lists now
--   keys.list()                -- every row, its owner and file:line
--
-- A need says whether the key would act at the cursor now (D132), so the popup lists only keys that do something
-- here: a hunk key on a hunk's line, a fold key on a fold. Where the action doesn't depend on the cursor the answer
-- is a buffer or cwd fact ("formatter", "git cwd"). An LSP method or client need is the closest answer knowable
-- without asking the server: an attached server supports the method, not that it has something here (D133).
-- Two kinds of row stay at buffer level by decision, their cursor-level answer being too slow for a popup rebuild:
-- ]] and [[ (word references) and the treesitter moves (D132).
--
-- A row with a need is one global expr map: a press tests the need in the current buffer; where it holds the action
-- runs, elsewhere the key does what it did before (the map it took over, or Vim's own key). A leader key, or a row
-- with `echo`, says which need failed instead. A label-only row with a need lists the key, whoever maps it, only
-- where the need holds. Only language rows are buffer-local, and a buffer's own map always wins. Needs are read when
-- used, so nothing here runs on attach, FileType or registration.
local M = {}

---@alias keys.Icon string|{ icon: string, color?: string }

---@class keys.Toggle
---@field get fun(): boolean
---@field set fun(state: boolean)

---@class keys.Row
---@field [1] string lhs
---@field [2]? string|fun() the action: keys to run (noremap unless `remap`) or a function
---@field [3]? string the label
---@field label? string|fun(mode: string, lhs: string): string? the label, or a getter run when the popup draws
---@field need? string|string[] where the row acts: a word (keys.need), an LSP method ("rename",
---   "workspace/symbol") or "client:<name>"; with a list, where any one holds
---@field toggle? keys.Toggle|table a {get, set} pair or a Snacks toggle: a press flips it, the label follows it
---@field icon? keys.Icon|fun(mode: string, lhs: string): keys.Icon?
---@field mode? string|string[] default "n"
---@field group? string a prefix's name in the popup
---@field native? boolean Vim's own key, with no map: listed wherever its need holds
---@field hidden? boolean left out of the popup
---@field echo? boolean where the need fails, say so instead of doing Vim's own key (D49)
---@field listed? fun(mode: string, lhs: string): boolean a label-only row over another module's map: where the
---   popup lists the key, whoever maps it
---@field remap? boolean
---@field silent? boolean
---@field nowait? boolean

---@class keys.Entry one row in one mode
---@field id integer
---@field lhs string
---@field raw string the lhs as keys, <leader> replaced
---@field mode string
---@field row keys.Row
---@field action? string|fun()
---@field needs string[]
---@field ft? string
---@field owner string
---@field at string file:line of the declaration
---@field origin string owner, place and position: a row declared again from there replaces this one

---@class keys.Slot every entry on one mode and lhs
---@field key string mode .. raw
---@field mode string
---@field lhs string
---@field raw string
---@field entries keys.Entry[]
---@field prior? table the global map the slot took over (maparg's dict)
---@field placed? table a language row's buffer map, as placed (nvim_buf_get_keymap's dict), on its per-buffer slot
---@field mapped? boolean a global map of ours is set on it
---@field toggles? boolean a toggle row is on it

local entries = {} ---@type keys.Entry[]
local slots = {} ---@type table<string, keys.Slot>
local order = {} ---@type keys.Slot[]
local tests = {} ---@type table<string, fun(buf: integer, win?: integer): boolean>
local watchers = {} ---@type fun(slot: keys.Slot)[]

local KNOWN = { "lhs", "label", "need", "toggle", "icon", "mode", "group", "native", "hidden", "echo", "listed", "remap", "silent", "nowait" }

-- LSP methods by their full name and by the name after "textDocument/"
local methods ---@type table<string, string>?
---@param need string
---@return string?
local function method_of(need)
  if not methods then
    methods = {}
    for _, m in pairs(vim.lsp.protocol.Methods) do
      if type(m) == "string" then
        methods[m] = m
        local short = m:match("^textDocument/(.+)$")
        if short then
          methods[short] = methods[short] or m
        end
      end
    end
  end
  return methods[need]
end

local warned = {} ---@type table<string, true>

--- The window whose cursor a need reads for buf: the current one when it shows buf, else the first that does.
---@param buf integer
---@return integer?
local function window_of(buf)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) == buf then
    return win
  end
  win = vim.fn.bufwinid(buf)
  return win ~= -1 and win or nil
end

--- Whether need holds in buf, read now.
---@param need string
---@param buf integer
---@return boolean
local function test(need, buf)
  local fn = tests[need]
  if fn then
    local ok, held = pcall(fn, buf, window_of(buf))
    if not ok and not warned[need] then
      warned[need] = true
      vim.notify(("keys: the need %q failed: %s"):format(need, held), vim.log.levels.ERROR)
    end
    return ok and held and true or false
  end
  local name = need:match("^client:(.+)$")
  local method = not name and method_of(need)
  if not name and not method then
    if not warned[need] then
      warned[need] = true
      vim.notify(("keys: unknown need %q"):format(need), vim.log.levels.ERROR)
    end
    return false
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, name = name })) do
    if not client:is_stopped() and (name or client:supports_method(method, buf)) then
      return true
    end
  end
  return false
end

--- need in buf, answered once per memo (a which-key rebuild).
---@param memo? table
local function held(need, buf, memo)
  if not memo then
    return test(need, buf)
  end
  local v = memo[need]
  if v == nil then
    v = test(need, buf)
    memo[need] = v
  end
  return v
end

---@param ft string
---@param want string
local function ft_is(ft, want)
  if ft == want then
    return true
  end
  return ft:find(".", 1, true) ~= nil and vim.list_contains(vim.split(ft, ".", { plain = true }), want)
end

--- Whether entry acts in buf: its language and any one of its needs.
---@param e keys.Entry
---@param buf integer
---@param memo? table
local function acts(e, buf, memo)
  if e.ft and not ft_is(vim.bo[buf].filetype, e.ft) then
    return false
  end
  if #e.needs == 0 then
    return true
  end
  for _, need in ipairs(e.needs) do
    if held(need, buf, memo) then
      return true
    end
  end
  return false
end

--- Whether need holds in buf now.
---@param need string a word, an LSP method or "client:<name>"
---@param buf? integer default the current buffer
---@return boolean
function M.holds(need, buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  return test(need, buf)
end

--- Defines a need word: whether a row that names it would act at the cursor now. test gets the buffer and the window
--- whose cursor to read (the current one when it shows buf; nil where no window does). It must be a lookup (it runs
--- on a press and once per popup rebuild, D61's frame); an owner caches anything slow.
---@param word string
---@param fn fun(buf: integer, win?: integer): boolean
function M.need(word, fn)
  assert(not word:match("^client:") and not method_of(word), ("keys: %q is an LSP method or client need"):format(word))
  tests[word] = fn
end

-- toggles ------------------------------------------------------------------------------------------------------

local TOGGLE = {
  icon = { enabled = " ", disabled = " " },
  color = { enabled = "green", disabled = "yellow" },
  words = { enabled = "Disable ", disabled = "Enable " },
}

---@param t table
local function is_snacks(t) return type(t.toggle) == "function" and type(t.opts) == "table" end

---@param e keys.Entry
local function toggle_on(e)
  local t = e.row.toggle
  if is_snacks(t) then
    return t:get() and true or false
  end
  local ok, on = pcall(t.get)
  return ok and on and true or false
end

---@param e keys.Entry
local function toggle_name(e)
  local t = e.row.toggle
  return is_snacks(t) and t.opts.name or e.row.label or e.row[3] or e.lhs
end

---@param e keys.Entry
local function flip(e)
  local t = e.row.toggle
  if is_snacks(t) then
    return t:toggle()
  end
  local state = not toggle_on(e)
  t.set(state)
  local name = toggle_name(e)
  vim.notify(("%s **%s**"):format(state and "Enabled" or "Disabled", name), state and vim.log.levels.INFO or vim.log.levels.WARN, { title = name })
end

---@param e keys.Entry
local function toggle_label(e)
  local t, key = e.row.toggle, toggle_on(e) and "enabled" or "disabled"
  local words = is_snacks(t) and t.opts.wk_desc or TOGGLE.words
  return (type(words) == "string" and words or words[key]) .. toggle_name(e)
end

---@param e keys.Entry
local function toggle_icon(e)
  local t, key = e.row.toggle, toggle_on(e) and "enabled" or "disabled"
  local icon, color = TOGGLE.icon, TOGGLE.color
  if is_snacks(t) then
    icon, color = t.opts.icon or icon, t.opts.color or color
  end
  return { icon = type(icon) == "string" and icon or icon[key], color = type(color) == "string" and color or color[key] }
end

-- labels -------------------------------------------------------------------------------------------------------

--- The entry's label now, nil for none.
---@param e keys.Entry
---@return string?
local function label_of(e)
  if e.row.toggle then
    return toggle_label(e)
  end
  local l = e.row.label or e.row[3] or e.row.group
  if type(l) == "function" then
    local ok, got = pcall(l, e.mode, e.lhs)
    return ok and got or nil
  end
  return l
end

---@param e keys.Entry
local function icon_of(e)
  if e.row.toggle then
    return toggle_icon(e)
  end
  local i = e.row.icon
  if type(i) == "function" then
    local ok, got = pcall(i, e.mode, e.lhs)
    return ok and got or nil
  end
  return i
end

---@param e keys.Entry
local function static_label(e)
  local l = e.row.toggle and ("Toggle " .. toggle_name(e)) or e.row.label or e.row[3]
  return type(l) == "string" and l or nil
end

-- maps ---------------------------------------------------------------------------------------------------------

---@param raw string
local function is_leader(raw)
  local l = vim.g.mapleader
  return type(l) == "string" and l ~= "" and vim.startswith(raw, vim.keycode(l))
end

---@param need string
local function describe(need)
  if need:match("^client:") then
    return ("the %s server is not attached"):format(need:sub(8))
  end
  local method = method_of(need)
  if method then
    return "no attached server supports " .. method
  end
  return ("%q does not hold here"):format(need)
end

--- Echoes which need the first action row of slot lacks, for a key with nothing to fall back to.
---@param key string
function M._echo(key)
  local slot = slots[key]
  for _, e in ipairs(slot and slot.entries or {}) do
    if e.action then
      local why = vim.tbl_map(describe, e.needs)
      local name = static_label(e) or label_of(e) or e.lhs
      vim.api.nvim_echo({ { ("%s (%s): %s"):format(name, vim.fn.keytrans(e.raw), table.concat(why, ", or ")), "WarningMsg" } }, true, {})
      return
    end
  end
end

--- Runs entry id's function action.
---@param id integer
function M._run(id)
  local e = entries[id]
  if e.row.toggle then
    return flip(e)
  end
  e.action()
end

--- Runs the global map slot took over.
---@param key string
function M._prior(key)
  local map = slots[key].prior
  if map.callback then
    return map.callback()
  end
  vim.api.nvim_feedkeys(vim.keycode(map.rhs), map.noremap == 1 and "ni" or "mi", false)
end

--- The keys a press of e runs.
---@param e keys.Entry
local function run_keys(e)
  if type(e.action) == "string" then
    return e.action
  end
  return ("<Cmd>lua require('keys')._run(%d)<CR>"):format(e.id)
end

--- What a key does where none of its rows acts: say why, or the map it took over, or Vim's own key.
---@param slot keys.Slot
local function fallback(slot)
  local echo = is_leader(slot.raw)
  for _, e in ipairs(slot.entries) do
    echo = echo or e.row.echo == true
  end
  if echo then
    return ("<Cmd>lua require('keys')._echo(%q)<CR>"):format(slot.key)
  end
  local map = slot.prior
  if not map then
    return slot.lhs
  end
  if map.expr == 1 then
    return map.callback and map.callback() or vim.api.nvim_eval(map.rhs)
  end
  if map.callback or map.noremap ~= 1 then
    return ("<Cmd>lua require('keys')._prior(%q)<CR>"):format(slot.key)
  end
  return map.rhs
end

--- (Re)sets slot's global map: a plain map for one row that always acts, else an expr map that picks the row.
---@param slot keys.Slot
local function place(slot)
  local acting = vim.tbl_filter(function(e) return e.action ~= nil and not e.ft end, slot.entries)
  if #acting == 0 then
    return
  end
  local first = acting[1]
  local opts = { desc = static_label(first), silent = first.row.silent, nowait = first.row.nowait }
  local remap = false
  for _, e in ipairs(acting) do
    remap = remap or e.row.remap == true
  end
  opts.remap = remap
  if #acting == 1 and #first.needs == 0 then
    vim.keymap.set(slot.mode, slot.lhs, first.action, opts)
  else
    opts.expr = true
    vim.keymap.set(slot.mode, slot.lhs, function()
      local buf = vim.api.nvim_get_current_buf()
      for _, e in ipairs(acting) do
        if acts(e, buf) then
          return run_keys(e)
        end
      end
      return fallback(slot)
    end, opts)
  end
  slot.mapped = true
end

local BUF_MAPS = {} -- memo key: mode -> lhs as keys -> the buffer's own map

--- buf's own maps in mode, by lhs as keys: read once per memo, for every slot's label.
---@param buf integer
---@param mode string
---@param memo? table
local function buf_maps(buf, mode, memo)
  memo = memo or {}
  memo[BUF_MAPS] = memo[BUF_MAPS] or {}
  local maps = memo[BUF_MAPS][mode]
  if not maps then
    maps = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      maps[m.lhsraw] = m
    end
    memo[BUF_MAPS][mode] = maps
  end
  return maps
end

-- language rows: buffer maps, placed on FileType where the buffer has no map of its own on the lhs
local lang_rows = {} ---@type keys.Entry[]
local lang_group ---@type integer?

---@param e keys.Entry
---@param buf integer
local function place_in(e, buf)
  if not ft_is(vim.bo[buf].filetype, e.ft) then
    return
  end
  local own = vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(e.lhs, e.mode, false, true) end)
  if own.buffer == 1 then
    return
  end
  local slot = { key = e.mode .. e.raw .. "@" .. buf, mode = e.mode, lhs = e.lhs, raw = e.raw, entries = { e } }
  slots[slot.key] = slot
  local opts = { buf = buf, desc = static_label(e), silent = e.row.silent, nowait = e.row.nowait, remap = e.row.remap }
  if #e.needs == 0 then
    vim.keymap.set(e.mode, e.lhs, e.action, opts)
  else
    opts.expr = true
    vim.keymap.set(e.mode, e.lhs, function() return acts(e, buf) and run_keys(e) or fallback(slot) end, opts)
  end
  slot.placed = buf_maps(buf, e.mode)[e.raw]
end

---@param e keys.Entry
---@param old? keys.Entry the entry e replaces
local function add_language(e, old)
  local at
  for i, row in ipairs(lang_rows) do
    if old and row == old then
      at = i
    end
  end
  if at then
    lang_rows[at] = e
  else
    table.insert(lang_rows, e)
  end
  lang_group = lang_group or vim.api.nvim_create_augroup("keys.language", { clear = true })
  if #lang_rows == 1 then
    vim.api.nvim_create_autocmd("FileType", {
      group = lang_group,
      callback = function(ev)
        for _, row in ipairs(lang_rows) do
          place_in(row, ev.buf)
        end
      end,
    })
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      place_in(e, buf)
    end
  end
end

-- rows ---------------------------------------------------------------------------------------------------------

---@param row keys.Row
---@param defaults table
---@param owner string
---@param at string
---@param index integer the row's place in its adder call
---@param ft? string
local function add(row, defaults, owner, at, index, ft)
  for k in pairs(row) do
    if type(k) == "string" and not vim.list_contains(KNOWN, k) then
      error(("keys: unknown field %q in a row at %s"):format(k, at), 3)
    end
  end
  row = vim.tbl_extend("keep", row, defaults)
  local lhs = row[1] or row.lhs
  assert(type(lhs) == "string", "keys: a row without an lhs at " .. at)
  if lhs:lower():find("<leader>", 1, true) and vim.g.mapleader == nil then
    error("keys: set mapleader before the first <leader> row (" .. at .. ")", 3)
  end
  local action = row[2]
  if row.toggle then
    action = action or true
  end
  local needs = row.need == nil and {} or type(row.need) == "table" and row.need or { row.need }
  local modes = row.mode or "n"
  for _, mode in ipairs(type(modes) == "table" and modes or { modes }) do
    local raw = vim.keycode(lhs)
    local e = {
      id = #entries + 1,
      lhs = lhs,
      raw = raw,
      mode = mode,
      row = row,
      action = action ~= true and action or nil,
      needs = needs,
      ft = ft,
      owner = owner,
      at = at,
      -- the same row declared again (its module sourced again) replaces itself
      origin = ("%s|%s|%d|%s"):format(owner, at, index, ft or ""),
    }
    if row.toggle then
      e.action = function() flip(e) end
    end
    entries[e.id] = e
    local key = mode .. raw
    local slot = slots[key]
    local new = slot == nil
    if new then
      slot = { key = key, mode = mode, lhs = lhs, raw = raw, entries = {} }
      local prior = vim.fn.maparg(lhs, mode, false, true)
      if prior.lhs and prior.buffer ~= 1 then
        slot.prior = prior
      end
      slots[key] = slot
      table.insert(order, slot)
    end
    local old
    for i, x in ipairs(slot.entries) do
      if x.origin == e.origin then
        old = x
        slot.entries[i] = e
      end
    end
    if not old then
      table.insert(slot.entries, e)
    end
    slot.toggles = slot.toggles or row.toggle ~= nil
    if e.action and ft then
      add_language(e, old)
    elseif e.action then
      place(slot)
    end
    for _, watch in ipairs(watchers) do
      watch(slot)
    end
  end
end

---@param defaults table
---@param owner string
---@param ft? string
local function adder(defaults, owner, ft)
  return function(rows)
    local info = debug.getinfo(2, "Sl")
    local at = ("%s:%d"):format(vim.fn.fnamemodify(info.source:gsub("^@", ""), ":~:."), info.currentline)
    if type(rows[1]) == "string" or rows.lhs then
      rows = { rows }
    end
    for i, row in ipairs(rows) do
      add(row, defaults, owner, at, i, ft)
    end
  end
end

--- An adder for one owner's rows: add(row) or add({ row, row, … }). defaults go into each row (a set's need).
---@param name string
---@param defaults? keys.Row
---@return fun(rows: keys.Row|keys.Row[])
function M.feature(name, defaults) return adder(defaults or {}, name) end

--- An adder for a language's rows: buffer-local in buffers whose filetype (or a dot-part of it) is ft.
---@param ft string
---@param defaults? keys.Row
---@return fun(rows: keys.Row|keys.Row[])
function M.language(ft, defaults) return adder(defaults or {}, "language " .. ft, ft) end

-- reads --------------------------------------------------------------------------------------------------------

--- Whether the popup lists e in buf: it acts there, and a label-only row's `listed` agrees.
---@param e keys.Entry
---@param buf integer
---@param memo? table
local function shows(e, buf, memo)
  if e.row.hidden or not acts(e, buf, memo) then
    return false
  end
  return not e.row.listed or e.row.listed(e.mode, e.lhs) ~= false
end

--- Whether a map is on slot's lhs in buf (any, global or the buffer's own).
---@param slot keys.Slot
---@param buf integer
local function mapped(slot, buf)
  return not vim.tbl_isempty(vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(slot.lhs, slot.mode, false, true) end))
end

--- The label and icon slot shows in buf. Where the buffer's own map wins the press (an ftplugin's), its desc, else a
--- label-only language row's; else each from a language row first, then from the first row that is listed.
---@param slot keys.Slot
---@param buf integer
---@param memo? table
local function slot_label(slot, buf, memo)
  local map = buf_maps(buf, slot.mode, memo)[slot.raw] or {}
  local own = map.lhs ~= nil
  local placed = slots[slot.key .. "@" .. buf] and slots[slot.key .. "@" .. buf].placed
  local foreign = own and not (placed and placed.callback == map.callback and placed.rhs == map.rhs)
  if foreign and map.desc then
    return map.desc, nil
  end
  local label, icon
  for pass = 1, 2 do
    for _, e in ipairs(slot.entries) do
      local lang = e.ft ~= nil
      local applies = lang and own and not (foreign and e.action) or not lang and not own
      if (pass == 1) == lang and applies and shows(e, buf, memo) then
        label = label or label_of(e)
        icon = icon or icon_of(e)
      end
    end
  end
  return label, icon
end

--- memo is for one popup rebuild in one buffer: a new buffer empties it.
---@param memo table
---@param buf integer
local function memo_for(memo, buf)
  if memo.buf ~= buf then
    for k in pairs(memo) do
      memo[k] = nil
    end
    memo.buf = buf
  end
end

--- What the popup shows for slot in the current buffer: label and icon, for the which-key adapter. Read once per
--- rebuild: memo keeps the answer, under the slot itself (need words are its string keys).
--- A toggle's label follows its state, which a press changes between rebuilds, so it is read each time (from the
--- memo's needs and maps).
---@param slot keys.Slot
---@param memo table answers for this rebuild
function M._label(slot, memo)
  local buf = vim.api.nvim_get_current_buf()
  memo_for(memo, buf)
  local got = memo[slot]
  if not got then
    got = { slot_label(slot, buf, memo) }
    if not slot.toggles then
      memo[slot] = got
    end
  end
  return got[1], got[2]
end

--- Whether the popup lists a map or spec of slot in the current buffer.
---@param slot keys.Slot
---@param kind "spec"|"ours"|"other"|"buffer" our popup spec, our global map, another's global map, or a buffer's
---   own map on the lhs
---@param memo table answers for this rebuild
function M._lists(slot, kind, memo)
  local buf = vim.api.nvim_get_current_buf()
  memo_for(memo, buf)
  for _, e in ipairs(slot.entries) do
    -- a hidden row's spec stays, so the popup hides whatever maps the key
    if e.row.hidden then
      return kind == "spec"
    end
    if e.row.listed and not e.row.listed(e.mode, e.lhs) then
      return false
    end
  end
  if kind == "buffer" then
    return true
  end
  if kind == "other" then
    -- a label-only row with a need (Neovim's ]d and gx) lists the key, whoever maps it, only where the need holds
    local gated = false
    for _, e in ipairs(slot.entries) do
      if not e.action and not e.row.group and not e.ft and #e.needs > 0 then
        if shows(e, buf, memo) then
          return true
        end
        gated = true
      end
    end
    return not gated
  end
  for _, e in ipairs(slot.entries) do
    if (kind == "spec" or (e.action and not e.ft)) and shows(e, buf, memo) then
      return true
    end
  end
  return false
end

---@param mode string
---@param raw string
---@return keys.Slot?
function M._slot(mode, raw) return slots[mode .. raw] end

--- Calls fn with every slot so far and each slot a later row adds to or creates.
---@param fn fun(slot: keys.Slot)
function M._watch(fn)
  table.insert(watchers, fn)
  for _, slot in ipairs(order) do
    fn(slot)
  end
end

---@class keys.Item
---@field lhs string as keytrans writes it ("<Space>lf")
---@field label? string
---@field icon? keys.Icon
---@field group? boolean

--- What the popup lists in buf and mode now: each row that acts there (a label-only row where a map is on its lhs),
--- and each group with a listed key under it.
---@param buf? integer
---@param mode? string default "n"
---@return keys.Item[]
function M.menu(buf, mode)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  mode = mode or "n"
  local memo, out, groups = {}, {}, {}
  for _, slot in ipairs(order) do
    if slot.mode == mode then
      local listed, group = false, false
      for _, e in ipairs(slot.entries) do
        group = group or e.row.group ~= nil
        if not e.row.group and shows(e, buf, memo) and (e.action or e.row.native or mapped(slot, buf)) then
          listed = true
        end
      end
      if group then
        table.insert(groups, slot)
      elseif listed then
        local label, icon = vim.api.nvim_buf_call(buf, function() return slot_label(slot, buf, memo) end)
        table.insert(out, { lhs = vim.fn.keytrans(slot.raw), label = label, icon = icon })
      end
    end
  end
  for _, slot in ipairs(groups) do
    local prefix = vim.fn.keytrans(slot.raw)
    if vim.iter(out):any(function(item) return #item.lhs > #prefix and vim.startswith(item.lhs, prefix) end) then
      local label, icon = vim.api.nvim_buf_call(buf, function() return slot_label(slot, buf, memo) end)
      table.insert(out, { lhs = prefix, label = label, icon = icon, group = true })
    end
  end
  table.sort(out, function(a, b) return a.lhs < b.lhs end)
  return out
end

---@class keys.Listed
---@field lhs string
---@field mode string
---@field label? string
---@field action? string|fun()
---@field need string[]
---@field ft? string
---@field owner string
---@field at string file:line

--- Every row, one per mode, with its owner and where it was declared.
---@return keys.Listed[]
function M.list()
  local out = {}
  for _, slot in ipairs(order) do
    for _, e in ipairs(slot.entries) do
      local item = { lhs = e.lhs, mode = e.mode, label = static_label(e), action = e.row[2], need = e.needs, ft = e.ft }
      item.owner, item.at = e.owner, e.at
      table.insert(out, item)
    end
  end
  return out
end

return M
