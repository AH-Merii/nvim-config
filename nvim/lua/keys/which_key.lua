-- The which-key adapter: the only code that knows which-key. One popup spec per mode and lhs, whose label and icon
-- are getters over the rows, and a filter that lists a key only where a row of it acts (keys._lists), testing each
-- need once per popup rebuild.
local keys = require("keys")

local M = {}

-- each need's answer and each key's label for one rebuild: which-key clears a mode's tree before it rebuilds it
-- (which-key/buf.lua Mode:update), on every popup (which-key/state.lua M.start), so a clear starts a new memo
local memo = {}

local raws = {} ---@type table<string, string>
---@param lhs string
local function raw_of(lhs)
  local raw = raws[lhs]
  if not raw then
    raw = vim.keycode(lhs)
    raws[lhs] = raw
  end
  return raw
end

--- which-key's filter, called for every map and spec on each rebuild, with the buffer current.
---@param m wk.Mapping|wk.Keymap
function M.filter(m)
  local slot = keys._slot(m.mode, m.lhsraw or raw_of(m.lhs))
  if not slot then
    return true
  end
  local kind = m.idx and "spec" or ((m.buffer or 0) == 0 and slot.mapped) and "ours" or "other"
  return keys._lists(slot, kind, memo)
end

---@param slot keys.Slot
---@return wk.Spec
local function spec(slot)
  local s = { slot.lhs, mode = slot.mode }
  local group, native, hidden
  for _, e in ipairs(slot.entries) do
    group = group or e.row.group
    native = native or e.row.native
    hidden = hidden or e.row.hidden
  end
  if hidden then
    s.hidden = true
    return s
  end
  if group then
    s.group = group
  else
    s.desc = function() return (keys._label(slot, memo)) end
    -- a row with no map of its own labels whoever maps the key, and is left out where nothing does
    s.real = not native
  end
  s.icon = function() return select(2, keys._label(slot, memo)) end
  return s
end

function M.setup()
  local wk = require("which-key")
  local Tree = require("which-key.tree")
  local clear = Tree.clear
  Tree.clear = function(...)
    memo = {}
    return clear(...)
  end

  local ready, initial, seen = false, {}, {}
  keys._watch(function(slot)
    if seen[slot.key] then
      return
    end
    seen[slot.key] = true
    if ready then
      wk.add({ spec(slot) })
    else
      table.insert(initial, spec(slot))
    end
  end)
  wk.setup({
    preset = "helix",
    delay = 300,
    filter = M.filter,
    icons = {
      breadcrumb = " ", -- symbol used in the command line area that shows your active key combo
      separator = "󱦰  ", -- symbol used between a key and it's label
      group = "", -- symbol prepended to a group
    },
    plugins = {
      spelling = { enabled = false },
      presets = {
        operators = false, -- adds help for operators like d, y, ...
        motions = false, -- adds help for motions
        text_objects = false, -- help for text objects triggered after entering an operator
        windows = true, -- default bindings on <c-w>
        nav = false, -- misc bindings to work with windows
        z = false, -- bindings for folds, spelling and others prefixed with z
        g = false, -- bindings for prefixed with g
      },
    },
    win = { height = { max = math.huge } },
    spec = initial,
  })
  ready = true
end

return M
