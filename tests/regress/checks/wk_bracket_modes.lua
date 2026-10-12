-- @desc     a ] or [ key with an icon of ours in normal mode shows the same icon wherever the visual or operator-pending popup shows it; ]b ]a ]l carry ours in every mode where pressing them runs the treesitter move and never where they run the built-ins; the x and o popups list no unmapped key that does nothing there
-- @areas    which-key keys treesitter
-- @budget   40
-- @version-sensitive
-- @args     app.py
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded) then return end
local Buf, Util, View = require("which-key.buf"), require("which-key.util"), require("which-key.view")
local MODES, XO = { "n", "x", "o" }, { "x", "o" }
local MOVES = { "]b", "[b", "]a", "[a", "]l", "[l" }

local function flush()
  local ran = false
  vim.schedule(function() ran = true end)
  wait_until(function() return ran end, 1000)
end

local function cps(s)
  if not s then return "nil" end
  return table.concat(vim.tbl_map(function(c) return ("U+%04X"):format(c) end, vim.fn.str2list(s)), "+")
end
local function show(r) return r and ("%s %s %s"):format(cps(r.icon), tostring(r.hl), tostring(r.desc)) or "absent" end

-- run fn with nvim really in mode, as when the popup renders: visual after v, operator-pending after d
local function in_mode(mode, fn)
  if mode == "n" then return vim.api.nvim_get_mode().mode, pcall(fn) end
  local got
  vim.keymap.set(mode, "<Plug>(nvr-wk-probe)", function() got = { vim.api.nvim_get_mode().mode, pcall(fn) } end)
  feed((mode == "x" and "v" or "d") .. "<Plug>(nvr-wk-probe)<Esc>")
  vim.keymap.del(mode, "<Plug>(nvr-wk-probe)")
  return unpack(got or { "none", false, "the probe map never ran" })
end

-- keys -> what the popup of mode would show under ] and [ in the current buffer
local function snapshot(mode)
  local buf = vim.api.nvim_get_current_buf()
  local nvmode, ok, snap = in_mode(mode, function()
    local m = Buf.get({ buf = buf, mode = mode, update = true })
    local out = {}
    local function walk(node)
      local icon, hl = View.icon(node)
      local d = node.desc
      if type(d) == "function" then d = d() end
      out[node.keys] = {
        icon = icon,
        hl = hl,
        desc = d,
        ours = node.mapping ~= nil and node.mapping.icon ~= nil and icon ~= nil,
        group = node:is_group(),
        virtual = node.keymap == nil,
      }
      for _, c in ipairs(node:children()) do
        walk(c)
      end
    end
    for _, root in ipairs({ "]", "[" }) do
      local node = m and m.tree.root:find(Util.keys(root, { norm = true }))
      if node then walk(node) end
    end
    return out
  end)
  return nvmode, ok, snap
end

-- what pressing lhs in mode does from the cursor: "ts" for the treesitter move, "builtin", or nil when it cannot tell.
-- n: the move stays in the buffer with no error, the built-ins switch buffer or fail; x and o: the move extends the
-- selection or yanks, the built-in does neither, and nothing at all happens to either when no object is ahead
local function acts(mode, lhs, n_kind)
  local buf, cur = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
  local yanked = false
  local au = vim.api.nvim_create_autocmd("TextYankPost", { callback = function() yanked = #table.concat(vim.v.event.regcontents) > 0 end })
  vim.v.errmsg = ""
  vim.cmd("silent! normal " .. ({ n = "", x = "v", o = "y" })[mode] .. lhs)
  local now, err, stayed = vim.api.nvim_win_get_cursor(0), vim.v.errmsg, vim.api.nvim_get_current_buf() == buf
  vim.api.nvim_del_autocmd(au)
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  if not stayed then vim.cmd.buffer(buf) end
  vim.api.nvim_win_set_cursor(0, cur)
  if mode == "n" then return (stayed and err == "") and "ts" or "builtin" end
  if (mode == "x" and (now[1] ~= cur[1] or now[2] ~= cur[2])) or (mode == "o" and yanked) then return "ts" end
  return n_kind == "builtin" and "builtin" or nil
end

local WANT = { n = "^n$", x = "^v$", o = "^no" }
local snaps, totals = {}, { x = 0, o = 0 }
local moves = {} -- lhs -> list of { where, mapped, ours }
local phantoms = {} -- mode .. keys -> buffers whose popup lists it with no map

local function judge(name)
  local buf = vim.api.nvim_get_current_buf()
  local s = {}
  for _, mode in ipairs(MODES) do
    local nvmode, ok, snap = snapshot(mode)
    check(("%s: the %s popup is read in mode %s"):format(name, mode, mode), ok and nvmode:match(WANT[mode]) ~= nil, nvmode .. (ok and "" or (" " .. tostring(snap))))
    s[mode] = ok and snap or {}
  end
  snaps[name] = s

  local bad, compared = {}, { x = {}, o = {} }
  for keys, r in pairs(s.n) do
    if r.ours then
      for _, mode in ipairs(XO) do
        local o = s[mode][keys]
        if o then
          table.insert(compared[mode], keys)
          if o.icon ~= r.icon or o.hl ~= r.hl or (r.group and o.desc ~= r.desc) then bad[#bad + 1] = ("%s %s: n %s, %s %s"):format(keys, mode, show(r), mode, show(o)) end
        end
      end
    end
  end
  for _, mode in ipairs(XO) do
    table.sort(compared[mode])
    totals[mode] = totals[mode] + #compared[mode]
    info(("%s %s compared: %s"):format(name, mode, table.concat(compared[mode], " ")))
  end
  table.sort(bad)
  check(name .. ": a key with our icon in normal mode has it in the x and o popups", #bad == 0, #bad > 0 and table.concat(bad, "; ") or nil)

  -- pressed from the top for ] and from the bottom for [, so an object lies ahead where the language has one
  for _, lhs in ipairs(MOVES) do
    local keys = Util.norm(lhs)
    vim.api.nvim_win_set_cursor(0, lhs:sub(1, 1) == "]" and { 1, 0 } or { vim.api.nvim_buf_line_count(0), 0 })
    local n_kind
    for _, mode in ipairs(MODES) do
      local kind = acts(mode, lhs, n_kind)
      n_kind = n_kind or kind
      local r = s[mode][keys]
      moves[lhs] = moves[lhs] or {}
      table.insert(moves[lhs], { where = name .. " " .. mode, kind = kind, ours = r ~= nil and r.ours, r = r })
    end
  end

  for _, mode in ipairs(XO) do
    for keys, r in pairs(s[mode]) do
      if r.virtual and not r.group then
        local id = mode .. " " .. keys
        phantoms[id] = phantoms[id] or { mode = mode, keys = keys, from = {} }
        table.insert(phantoms[id].from, name)
      end
    end
  end
end

-- app.py: the treesitter moves and the python ftplugin's ]m ]] ][ maps
local py_mapped = wait_until(function() return vim.fn.maparg("]m", "o", false, true).buffer == 1 end, 5000)
check("app.py has the python ftplugin's ]m in o", py_mapped)
-- other listed buffers, so :bnext switches
for _, f in ipairs({ "main.lua", "notes.md" }) do vim.cmd.badd(FIX .. "/" .. f) end
judge("app.py")
check("app.py compared keys in both the x and o popups", totals.x > 0 and totals.o > 0, vim.inspect(totals))

vim.cmd.edit(FIX .. "/notes.md")
check("notes.md maps ]] in x", vim.fn.maparg("]]", "x", false, true).buffer == 1)
judge("notes.md")

vim.cmd.enew()
local plain = vim.api.nvim_get_current_buf()
vim.bo[plain].buftype = "nofile"
vim.bo[plain].filetype = "text"
flush()
judge("text buffer")

-- ]b ]a ]l: ours in every mode where pressing runs the move, never where the key runs the built-in
local missing, leaked, nts, nbuiltin = {}, {}, 0, 0
for _, lhs in ipairs(MOVES) do
  for _, e in ipairs(moves[lhs]) do
    if e.kind == "ts" then
      nts = nts + 1
      if not e.ours then missing[#missing + 1] = ("%s %s: %s"):format(lhs, e.where, show(e.r)) end
    elseif e.kind == "builtin" then
      if e.r then nbuiltin = nbuiltin + 1 end
      if e.ours then leaked[#leaked + 1] = ("%s %s: %s"):format(lhs, e.where, show(e.r)) end
    end
  end
end
check("]b ]a ]l show our icon in every mode they run the treesitter move", #missing == 0, nts .. " treesitter" .. (#missing > 0 and (", not ours: " .. table.concat(missing, "; ")) or ""))
check("]b ]a ]l show no icon of ours where they run the built-in", #leaked == 0, nbuiltin .. " shown built-in" .. (#leaked > 0 and (", ours: " .. table.concat(leaked, "; ")) or ""))
check("the moves met both treesitter and shown built-ins", nts > 0 and nbuiltin > 0, nts .. " treesitter, " .. nbuiltin .. " built-in")

-- every unmapped key the x and o popups list must do something there: move the cursor in visual mode, change text after d
local LINES = { "alpha", "def foo():", "  speling misteak here", "  x = 1", "", "def bar():", "  y = wrongg", "  return y", "end", "" }
local function playground()
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  vim.wo.spell = true
  vim.bo[buf].spelllang = "en"
  vim.wo.foldmethod = "manual"
  vim.cmd("silent! 2,4fold | silent! 6,8fold | silent! normal! zR")
  vim.api.nvim_win_set_cursor(0, { 3, 2 })
  return buf
end
local function acts(mode, keys)
  local buf = playground()
  local cur = vim.api.nvim_win_get_cursor(0)
  vim.cmd("silent! normal! " .. (mode == "x" and "v" or "d") .. vim.keycode(keys))
  local now = vim.api.nvim_win_get_cursor(0)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  if mode == "x" then return now[1] ~= cur[1] or now[2] ~= cur[2] end
  return text ~= table.concat(LINES, "\n")
end
local dead, listed = {}, {}
for id, p in pairs(phantoms) do
  listed[#listed + 1] = id
  if not acts(p.mode, p.keys) then dead[#dead + 1] = ("%s (%s)"):format(id, table.concat(p.from, ", ")) end
end
table.sort(listed)
table.sort(dead)
info("unmapped keys in the x and o popups: " .. table.concat(listed, ", "))
check("every unmapped key in the x and o popups acts there", #dead == 0, #dead > 0 and ("does nothing: " .. table.concat(dead, "; ")) or nil)
check("back in normal mode", vim.api.nvim_get_mode().mode == "n", vim.api.nvim_get_mode().mode)
