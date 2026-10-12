-- @desc     which-key draws an icon of ours on ]b ]a ]l and their [ pairs where pressing the key runs a treesitter move (it stays in the buffer, no error), never the move's icon where it runs the built-in :bnext, :next or :lnext, also across filetype changes, and opening buffers adds no spec
-- @areas    which-key keys treesitter
-- @budget   30
-- @version-sensitive
-- @args     main.lua
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded) then return end
local wkc = package.loaded["which-key.config"]
local Buf, Util, View = require("which-key.buf"), require("which-key.util"), require("which-key.view")
local KEYS = { "]b", "[b", "]a", "[a", "]l", "[l" }
local function norm(lhs) return vim.fn.keytrans(vim.keycode(lhs)) end
local OURS = {}
for _, k in ipairs(KEYS) do OURS[norm(k)] = true end

local function flush()
  local ran = false
  vim.schedule(function() ran = true end)
  wait_until(function() return ran end, 1000)
end

local function nspecs()
  local n = 0
  for _, m in ipairs(rawget(wkc, "mappings")) do
    if OURS[norm(m.lhs)] then n = n + 1 end
  end
  return n
end

-- the treesitter move stays in the buffer without an error; the built-ins switch buffer or fail (no next argument, no loclist)
local function ts_moves(buf, lhs)
  vim.cmd.buffer(buf)
  local cur = vim.api.nvim_win_get_cursor(0)
  vim.v.errmsg = ""
  vim.cmd("silent! normal " .. lhs)
  local stayed, err = vim.api.nvim_get_current_buf() == buf, vim.v.errmsg
  vim.cmd.buffer(buf)
  vim.api.nvim_win_set_cursor(0, cur)
  return stayed and err == ""
end

-- icon, highlight and label which-key resolves for lhs in buf, as the popup does with buf current, and whether a spec supplied the icon
local function resolve(buf, lhs)
  return vim.api.nvim_buf_call(buf, function()
    local m = Buf.get({ buf = buf, mode = "n", update = true })
    local node = m and m.tree.root:find(Util.keys(lhs, { norm = true }))
    if not node then return { shown = false } end
    local icon, hl = View.icon(node)
    local d = node.desc
    if type(d) == "function" then d = d() end
    return { shown = true, icon = icon, hl = hl, desc = d, spec = node.mapping ~= nil and node.mapping.icon ~= nil }
  end)
end

-- what resolves with every spec on these keys taken out, i.e. which-key's own fallback
local function baseline(buf, lhs)
  local list, saved = rawget(wkc, "mappings"), {}
  for i = #list, 1, -1 do
    if OURS[norm(list[i].lhs)] then table.insert(saved, 1, { i, table.remove(list, i) }) end
  end
  Buf.clear()
  local ok, ret = pcall(resolve, buf, lhs)
  for _, s in ipairs(saved) do table.insert(list, s[1], s[2]) end
  Buf.clear()
  assert(ok, ret)
  return ret
end

local function show(r) return ("%s %s %s"):format(r.icon and ("U+%04X"):format(vim.fn.char2nr(r.icon)) or "nil", tostring(r.hl), tostring(r.desc)) end
local function look(r) return tostring(r.icon) .. " " .. tostring(r.hl) end

-- lhs -> the icons it showed where it ran the treesitter move; main.lua, judged first, runs all six
local moved = {}

local totals = { ts = 0, builtin = 0 }
-- the popup is read first, as the user sees it before pressing; then each key is pressed
local function judge(name, buf)
  local seen = {}
  for _, lhs in ipairs(KEYS) do seen[lhs] = resolve(buf, lhs) end
  local own, leak, ts, builtin, acts = {}, {}, 0, 0, {}
  for _, lhs in ipairs(KEYS) do
    local r = seen[lhs]
    acts[lhs] = ts_moves(buf, lhs)
    if acts[lhs] then
      ts = ts + 1
      if not (r.shown and r.spec and r.icon) then own[#own + 1] = lhs .. " " .. show(r) end
      moved[lhs] = moved[lhs] or {}
      moved[lhs][look(r)] = true
    else
      builtin = builtin + 1
      -- the built-in key keeps what it shows with no spec on it, or shows an icon of its own, never the move's
      local b = baseline(buf, lhs)
      if look(r) ~= look(b) and (moved[lhs] or {})[look(r)] then leak[#leak + 1] = ("%s %s, without specs %s"):format(lhs, show(r), show(b)) end
    end
  end
  totals.ts, totals.builtin = totals.ts + ts, totals.builtin + builtin
  check(name .. ": a key running the treesitter move shows an icon of ours", #own == 0, ts .. " treesitter" .. (#own > 0 and (", fallback on: " .. table.concat(own, "; ")) or ""))
  check(name .. ": a key running the built-in does not show the move's icon", #leak == 0, builtin .. " built-in" .. (#leak > 0 and (", changed: " .. table.concat(leak, "; ")) or ""))
  return acts
end
local function all(acts, want)
  for _, lhs in ipairs(KEYS) do
    if acts[lhs] ~= want then return false end
  end
  return true
end
local function list(acts)
  local out = {}
  for _, lhs in ipairs(KEYS) do out[#out + 1] = lhs .. "=" .. (acts[lhs] and "ts" or "built-in") end
  return table.concat(out, " ")
end

-- other listed buffers, so :bnext and :bprevious switch
local before = nspecs()
local first = vim.api.nvim_get_current_buf()
for _, f in ipairs({ "app.py", "main.go", "index.ts", "notes.md" }) do vim.cmd.badd(FIX .. "/" .. f) end
local acts = judge("main.lua", first)
check("main.lua: all six keys run the treesitter move", all(acts, true), list(acts))

for _, f in ipairs({ "app.py", "main.go", "index.ts", "notes.md" }) do
  vim.cmd.edit(FIX .. "/" .. f)
  local buf = vim.api.nvim_get_current_buf()
  flush()
  acts = judge(f, buf)
  if f ~= "notes.md" then check(f .. ": all six keys run the treesitter move", all(acts, true), list(acts)) end
end

vim.cmd.enew()
local plain = vim.api.nvim_get_current_buf()
vim.bo[plain].buftype = "nofile"
vim.bo[plain].filetype = "text"
flush()
acts = judge("text buffer", plain)
check("text buffer: all six keys run the built-in", all(acts, false), list(acts))

-- the moves go with the filetype: no icon of ours stays on the built-in keys
vim.cmd.edit(FIX .. "/app.py")
local py = vim.api.nvim_get_current_buf()
vim.bo[py].filetype = "text"
flush()
acts = judge("app.py as text", py)
check("app.py as text: the moves are gone", all(acts, false), list(acts))
vim.bo[py].filetype = "markdown"
flush()
acts = judge("app.py as markdown", py)
check("app.py as markdown: ]b runs the treesitter move again", acts["]b"] == true, list(acts))
vim.bo[py].filetype = "python"
flush()
acts = judge("app.py as python again", py)
check("app.py as python again: the moves are back", all(acts, true), list(acts))

check("buffers met both treesitter and built-in keys", totals.ts > 0 and totals.builtin > 0, vim.inspect(totals))
check("opening buffers adds no which-key spec on these keys", nspecs() == before, before .. " -> " .. nspecs())
