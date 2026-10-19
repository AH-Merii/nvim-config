-- @desc     the which-key popup says what each ]/[ move and a/i object does at the cursor, judged by pressing it: an icon of ours and the target's language where it acts unlike the built-in (node-type wording for a markdown heading and an HTML element, also for a target off screen), Neovim's help index or default-map text and no icon of ours where it acts as the built-in, hidden where the built-in has no meaning; opening buffers adds no spec
-- @areas    which-key treesitter keys
-- @budget   90
-- @fixture  tobj
-- @args     doc.md
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded) then return end
local wkc = package.loaded["which-key.config"]
local Buf, Util, View = require("which-key.buf"), require("which-key.util"), require("which-key.view")
local specs = #rawget(wkc, "mappings")
-- a tall screen, as on a real monitor: the injections on screen are the ones parsed, as the highlighter does
vim.o.lines = 60

local MOVES = { "]f", "[f", "]F", "[F", "]c", "[c", "]C", "[C", "]p", "[p", "]b", "[b", "]B", "[B", "]i", "[i", "]l", "[l", "]a", "[a", "]r", "[r", "]/", "[/" }
local OBJECTS = { "af", "if", "ac", "ic", "ai", "ii", "al", "il", "ap", "ip", "ab", "ib", "a/", "aa", "ia", "ar", "ir" }
local KEYS = { n = MOVES, x = vim.list_extend(vim.list_extend({}, MOVES), OBJECTS), o = vim.list_extend(vim.list_extend({}, MOVES), OBJECTS) }
local MODES = { "n", "x", "o" }

-- ---- what each key means built in: index.txt, and the --clean nvim's default maps --------------------------------
-- section -> modes; a normal-mode motion (note 1) also counts in x and o; in x any normal command does
local SECTIONS = { ["2"] = { "n" }, ["2.1"] = { "x", "o" }, ["2.3"] = { "n" }, ["2.4"] = { "n" }, ["2.5"] = { "n" }, ["2.6"] = { "o" }, ["3"] = { "x" } }
local builtin, per_sec = { n = {}, x = {}, o = {} }, {}
do
  local sec, after_rule, in_table, last = nil, false, false, nil
  local rows = {}
  for line in io.lines(vim.env.VIMRUNTIME .. "/doc/index.txt") do
    if line:match("^=+$") then
      sec, after_rule, in_table, last = nil, true, false, nil
    elseif after_rule then
      after_rule = false
      sec = line:match("^(%d+)%.%s") or line:match("^(%d+%.%d+)%s")
    -- a table starts at its column headings ("Tag  Char  Note Normal-mode action ~"); help files before
    -- neovim/neovim@d65f9daf45 put a "----- ~" rule under them, which reads as a non-row line
    elseif sec and SECTIONS[sec] and line:match("^Tag%s.*~$") then
      in_table = true
    elseif in_table then
      local tag, rest = line:match("^|([^|]+)|%s*(.*)$")
      if tag then
        local chars, tail = rest:match("^([^\t]+)\t+(.*)$")
        local note, desc = (tail or ""):match("^%s*([12]?)%s%s+(.*)$")
        last = { chars = vim.trim(chars or rest), note = note, desc = vim.trim(desc or tail or ""), sec = sec }
        rows[#rows + 1] = last
      elseif last and line:match("^\t\t\t") then
        last.desc = vim.trim(last.desc .. " " .. vim.trim(line))
      else
        last = nil
      end
    end
  end
  for _, r in ipairs(rows) do
    if r.desc ~= "" and not r.desc:match("^not used") and not r.desc:match("^reserved") then
      per_sec[r.sec] = (per_sec[r.sec] or 0) + 1
      local modes = vim.list_extend({}, SECTIONS[r.sec])
      if r.sec ~= "2.1" and r.sec ~= "2.6" and r.sec ~= "3" then
        modes[#modes + 1] = "x"
        if r.note == "1" then modes[#modes + 1] = "o" end
      end
      for _, m in ipairs(modes) do
        builtin[m][r.chars] = builtin[m][r.chars] or {}
        table.insert(builtin[m][r.chars], r.desc)
      end
    end
  end
end
-- a parse that finds too little stops the check here: every verdict below would only repeat it, as a wrong label
local empty = {}
for s in vim.spairs(SECTIONS) do
  if not per_sec[s] then empty[#empty + 1] = s end
end
local index_ok = check("index.txt: every section's table has commands", #empty == 0, #empty > 0 and ("none in " .. table.concat(empty, ", ")) or nil)
-- one long-standing key from each section, in the modes the section gives it
local KNOWN = { n = { "w", "]p", "gg", "zz" }, x = { "w", "ip", "o" }, o = { "w", "ip", "]]", "v" } }
local absent = {}
for m, keys in vim.spairs(KNOWN) do
  for _, k in ipairs(keys) do
    if not builtin[m][k] then absent[#absent + 1] = m .. " " .. k end
  end
end
index_ok = check("index.txt: long-standing keys parse into their modes", #absent == 0, #absent > 0 and ("missing: " .. table.concat(absent, ", ")) or nil) and index_ok
if not index_ok then return end

local defaults = {}
do
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  vim.fn.writefile({
    "local r = {}",
    "for _, m in ipairs({ 'n', 'x', 'o' }) do for _, k in ipairs(vim.api.nvim_get_keymap(m)) do r[m .. ' ' .. k.lhs] = k.desc or k.rhs or '' end end",
    "vim.fn.writefile({ vim.json.encode(r) }, vim.env.NVR_OUT)",
    "vim.cmd('qa!')",
  }, tmp .. "/dump.lua")
  local res = vim.system({ vim.v.progpath, "--clean", "--headless", "-n", "-c", "luafile " .. tmp .. "/dump.lua" }, {
    timeout = 20000,
    env = { NVR_OUT = tmp .. "/maps.json", XDG_CONFIG_HOME = tmp, XDG_DATA_HOME = tmp, XDG_STATE_HOME = tmp, XDG_CACHE_HOME = tmp },
  }):wait()
  local ok, got = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(tmp .. "/maps.json"), "")) end)
  if not check("the --clean nvim dumped its default maps", ok and got["n ]b"] ~= nil, ok and "" or ("exit " .. res.code)) then return end
  defaults = got
end

-- which-key's own texts for the built-in objects and commands (its presets), another description of the built-in
local presets = {}
do
  local function scan(t)
    if type(t) ~= "table" then return end
    if type(t[1]) == "string" and type(t.desc) == "string" then presets[t[1]] = presets[t[1]] or t.desc end
    for _, v in pairs(t) do scan(v) end
  end
  local ok, mod = pcall(require, "which-key.plugins.presets")
  scan(ok and mod or nil)
end

-- what the key means built in, in mode: the default map's desc, the index texts, which-key's preset text
local function meanings(mode, lhs)
  local out = vim.deepcopy(builtin[mode][lhs] or {})
  if defaults[mode .. " " .. lhs] then table.insert(out, 1, defaults[mode .. " " .. lhs]) end
  if #out > 0 and presets[lhs] then table.insert(out, presets[lhs]) end
  return out
end
-- "Inside paragraph", "inner paragraph" and '"inner paragraph"' all come down to "paragraph"
local function core(s)
  s = (s or ""):lower():gsub('"', ""):gsub("%s+", " "):gsub("^ ", ""):gsub("[ %.]+$", "")
  return (s:gsub("^inner ", ""):gsub("^inside ", ""):gsub("^around ", ""):gsub("^a ", ""))
end
local function says(label, texts)
  local l = core(label)
  for _, t in ipairs(texts) do
    local d = core(t)
    if d ~= "" and l ~= "" and (l == d or l:find(d, 1, true) or (d:find(l, 1, true) == 1 and d:sub(#l + 1, #l + 1):match("^[ (,]?$"))) then return true end
  end
  return false
end

-- ---- the popup, read in its mode ----------------------------------------------------------------------------------
local function in_mode(mode, fn)
  if mode == "n" then return fn() end
  local got
  vim.keymap.set(mode, "<Plug>(nvr-wk-probe)", function() got = { pcall(fn) } end)
  feed((mode == "x" and "v" or "d") .. "<Plug>(nvr-wk-probe)<Esc>")
  vim.keymap.del(mode, "<Plug>(nvr-wk-probe)")
  assert(got and got[1], got and got[2] or "the probe map never ran")
  return got[2]
end
local function popup(mode)
  local buf = vim.api.nvim_get_current_buf()
  return in_mode(mode, function()
    local m = Buf.get({ buf = buf, mode = mode, update = true })
    local out = {}
    for _, lhs in ipairs(KEYS[mode]) do
      local node = m and m.tree.root:find(Util.keys(lhs, { norm = true }))
      if node and not node.hidden then
        local icon, hl = View.icon(node)
        out[lhs] = { desc = tostring(node.desc), icon = icon and (icon .. " " .. tostring(hl)) or nil }
      end
    end
    return out
  end)
end

-- ---- what pressing the key does -----------------------------------------------------------------------------------
local function open(f)
  vim.cmd.edit(vim.fn.fnameescape(FIX .. "/" .. f))
  local buf = vim.api.nvim_get_current_buf()
  local ok, p = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if ok and p then p:parse({ vim.fn.line("w0") - 1, vim.fn.line("w$") }) end
  return buf
end
local function at(pat, sub)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find(pat, 1, true) then
      vim.api.nvim_win_set_cursor(0, { i, sub and (assert(l:find(sub, 1, true), sub) - 1) or 0 })
      return
    end
  end
  error(("no line %s in %s: %s"):format(pat, vim.api.nvim_buf_get_name(0), table.concat(vim.api.nvim_buf_get_lines(0, 0, 3, false), " | ")))
end
local function esc()
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
end
local yank
vim.api.nvim_create_autocmd("TextYankPost", { callback = function() yank = table.concat(vim.v.event.regcontents, "\n") end })
local REGS = { '"', "0", "1", "-", "a" }

-- how: nil typed with maps; true built in (normal!); a function for a default map
local function effect(keys, how)
  local buf, cur = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local seq, modified = vim.fn.undotree().seq_cur, vim.bo[buf].modified
  local regs = {}
  for _, r in ipairs(REGS) do regs[r] = vim.fn.getreginfo(r) end
  yank = nil
  vim.v.errmsg = ""
  if type(how) == "function" then
    local ok, e = pcall(how)
    if not ok then vim.v.errmsg = tostring(e) end
  else
    vim.cmd("silent! normal" .. (how and "! " or " ") .. vim.keycode(keys))
  end
  local now = vim.api.nvim_win_get_cursor(0)
  -- nvim-origami's on_key takes the / of ]/ for a search, and the next key then fails with E490: not the key's effect
  local err = vim.v.errmsg:match("E%d+:") or vim.v.errmsg
  local r = { row = now[1], col = now[2], mode = (vim.fn.mode():gsub("\22", "^V")), yank = yank, err = err ~= "E490:" and err or "" }
  if r.mode:match("^[vV^]") then
    local v = vim.fn.getpos("v")
    r.vrow, r.vcol = v[2], v[3] - 1
  end
  esc()
  r.switched = vim.api.nvim_get_current_buf() ~= buf
  if r.switched then vim.cmd("silent! buffer " .. buf) end
  r.changed = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= text
  -- a :normal that ends in an error leaves its change unsynced, out of reach of :undo
  vim.o.undolevels = vim.o.undolevels
  if vim.fn.undotree().seq_cur ~= seq then vim.cmd("silent! undo " .. seq) end
  if table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= text then
    info(("undo after %q did not restore the text"):format(keys))
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n"))
  end
  if not modified then vim.bo[buf].modified = false end
  for _, reg in ipairs(REGS) do pcall(vim.fn.setreg, reg, regs[reg]) end
  vim.api.nvim_win_set_cursor(0, cur)
  -- an operator over nothing (y with no target) yanks an empty string: no effect
  if r.yank == "" then r.yank = nil end
  r.nothing = not r.switched and not r.changed and r.yank == nil and r.err == "" and r.row == cur[1] and r.col == cur[2]
    and (r.vrow == nil or (r.mode == "v" and r.vrow == cur[1] and r.vcol == cur[2]))
  return r
end
local function brief(r)
  return ("%d:%d %s%s%s%s%s%s"):format(r.row, r.col, r.mode, r.vrow and (" from " .. r.vrow .. ":" .. r.vcol) or "", r.yank and (" yank " .. #r.yank) or "",
    r.switched and " switched" or "", r.changed and " changed" or "", r.err ~= "" and (" " .. r.err) or "")
end
local function same(a, b)
  return a.row == b.row and a.col == b.col and a.mode == b.mode and a.vrow == b.vrow and a.vcol == b.vcol and a.yank == b.yank
    and a.switched == b.switched and a.changed == b.changed and a.err == b.err
end
local PREFIX = { n = "", x = "v", o = "y" }
local function native_how(mode, lhs)
  local d = defaults[mode .. " " .. lhs]
  if mode == "n" and d and d:match("^:%a+$") then
    return function() vim.cmd("silent " .. d:sub(2)) end
  end
  return true
end

-- the language at a position: the innermost tree there whose language has textobjects
local function lang_at(row, col)
  local ok, p = pcall(vim.treesitter.get_parser, 0, nil, { error = false })
  if not ok or not p then return nil end
  p:parse(true)
  local t = p:language_for_range({ row - 1, col, row - 1, col })
  while t and not vim.treesitter.query.get(t:lang(), "textobjects") do t = t:parent() end
  return t and t:lang()
end
-- words of the named nodes that start at a position (or the first non-blank after it), in the language there
local function node_words(row, col)
  local words = {}
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  while lines[row] and (lines[row]:sub(col + 1, col + 1)):match("^%s?$") do
    if col >= #lines[row] then row, col = row + 1, 0 else col = col + 1 end
  end
  local p = vim.treesitter.get_parser(0)
  local t = p:language_for_range({ row - 1, col, row - 1, col })
  local node = t:named_node_for_range({ row - 1, col, row - 1, col })
  while node do
    local sr, sc = node:start()
    if sr ~= row - 1 or sc ~= col then break end
    for w in node:type():gmatch("[^_]+") do words[#words + 1] = w end
    node = node:parent()
  end
  return words
end

-- ---- every key, every mode, in each context ---------------------------------------------------------------------
local CONTEXTS = {
  { "doc.md", "# Title" }, { "doc.md", "Second paragraph here." }, { "doc.md", "def add(a, b=2", "b=2" }, { "doc.md", "a += x", "x" },
  { "doc.md", "local function f(x, y)", "y)" }, { "doc.md", "## Second heading", "Second" }, { "doc.md", "Last paragraph." },
  { "a.py", "def add(a, b=2", "b=2" }, { "a.py", "total = a + b", "total" }, { "a.py", "for x in rest", "for" },
  { "notes.txt", "still paragraph one", "with" }, { "notes.txt", "Paragraph two." },
  { "t.sh", "greet one two", "one" }, { "page.html", "<p>Some", "Some" }, { "page.html", "function hello(name", "name" },
  { "plug.vim", "local function hello(name", "name" }, { "plug.vim", "let g:x" },
}
-- the node-type wording: a markdown heading is no class, an HTML element no function. The label still opens with what
-- the key does, so a generic move doesn't read as one that only goes to that kind of node (D144)
local WORDING = { ["doc.md # Title n ]c"] = "Next class: ", ["doc.md ## Second heading x ac"] = "Around class: ", ["page.html <p>Some x af"] = "Around function: " }

local seen = {} -- mode .. lhs -> { ours = { icon = true }, cases = { ... } }
local bad = { ours = {}, native = {}, hidden = {}, wording = {} }
local tally = { ours = 0, native = 0, unknown = 0 }
for _, c in ipairs(CONTEXTS) do
  local buf = open(c[1])
  at(c[2], c[3])
  local okp, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  local plain = not okp or parser == nil
  local where = ("%s %s"):format(c[1], c[2])
  for _, mode in ipairs(MODES) do
    at(c[2], c[3])
    local start = vim.api.nvim_win_get_cursor(0)
    local shown = popup(mode)
    if not vim.deep_equal(vim.api.nvim_win_get_cursor(0), start) then
      info(("%s %s: the popup probe moved the cursor %s -> %s"):format(where, mode, vim.inspect(start), vim.inspect(vim.api.nvim_win_get_cursor(0))))
      vim.api.nvim_win_set_cursor(0, start)
    end
    for _, lhs in ipairs(KEYS[mode]) do
      local keys = PREFIX[mode] .. lhs
      local ours, native = effect(keys), effect(keys, native_how(mode, lhs))
      local s = shown[lhs]
      local id = mode .. " " .. lhs
      seen[id] = seen[id] or { ours = {}, cases = {} }
      local kind = not same(ours, native) and "ours" or ((plain or not native.nothing) and "native" or "unknown")
      tally[kind] = tally[kind] + 1
      table.insert(seen[id].cases, { kind = kind, shown = s, where = where, pressed = brief(ours) })
      if kind == "ours" then
        local lang = mode ~= "o" and not ours.nothing and not ours.switched and lang_at(ours.row, ours.col)
        if not s or not s.icon or says(s.desc, meanings(mode, lhs)) or (lang and not s.desc:find(lang, 1, true)) then
          table.insert(bad.ours, ("%s at %s: %s (target in %s; pressed %s, built-in %s)"):format(id, where, s and (tostring(s.icon) .. " " .. s.desc) or "hidden", tostring(lang), brief(ours), brief(native)))
        end
        if s and s.icon then seen[id].ours[s.icon] = true end
        if WORDING[("%s %s %s"):format(c[1], c[2], id)] then
          local first = (ours.vrow and (ours.vrow < ours.row or (ours.vrow == ours.row and ours.vcol < ours.col))) and { ours.vrow, ours.vcol } or { ours.row, ours.col }
          local words, hit = node_words(first[1], first[2]), false
          for _, w in ipairs(words) do hit = hit or (#w > 2 and s ~= nil and s.desc:lower():find(w, 1, true) ~= nil) end
          if not hit or not (s and vim.startswith(s.desc, WORDING[("%s %s %s"):format(c[1], c[2], id)])) then table.insert(bad.wording, ("%s at %s: %q, nodes %s"):format(id, where, s and s.desc or "hidden", table.concat(words, " "))) end
          WORDING[("%s %s %s"):format(c[1], c[2], id)] = "done"
        end
      elseif kind == "native" then
        local texts = meanings(mode, lhs)
        if #texts == 0 and s then
          table.insert(bad.hidden, ("%s at %s: %q, the built-in does nothing (both %s)"):format(id, where, s.desc, brief(ours)))
        elseif #texts > 0 and s and not says(s.desc, texts) then
          table.insert(bad.native, ("%s at %s: %q, built in %q"):format(id, where, s.desc, texts[1]))
        end
      end
    end
  end
end

-- a key that acts as treesitter somewhere is ours: where it is the built-in with a meaning it says that, with no icon of ours
local unlabelled, icons, mixed = {}, {}, {}
for id, k in pairs(seen) do
  local mode, lhs = id:match("^(%a) (.*)$")
  local mine = next(k.ours) ~= nil
  for _, case in ipairs(k.cases) do
    local s = case.shown
    if case.kind == "native" then
      if s and s.icon and k.ours[s.icon] then table.insert(icons, ("%s at %s: %s"):format(id, case.where, s.icon)) end
      if mine and not s and #meanings(mode, lhs) > 0 then table.insert(unlabelled, ("%s at %s"):format(id, case.where)) end
    elseif case.kind == "unknown" and s then
      -- nothing happened either way: the built-in's text with no icon of ours, or an icon with a label of its own
      local says_builtin = says(s.desc, meanings(mode, lhs))
      if (says_builtin and s.icon ~= nil and k.ours[s.icon]) or (not says_builtin and s.icon == nil) then
        table.insert(mixed, ("%s at %s: %s %q"):format(id, case.where, tostring(s.icon), s.desc))
      end
    end
  end
end
for _, t in pairs({ bad.ours, bad.native, bad.hidden, bad.wording, unlabelled, icons, mixed }) do table.sort(t) end
for name, t in pairs({ ours = bad.ours, native = bad.native, hidden = bad.hidden, wording = bad.wording, unlabelled = unlabelled, icons = icons, mixed = mixed }) do
  for _, line in ipairs(t) do info(name .. ": " .. line) end
end
local function list(t) return #t > 0 and (#t .. ": " .. table.concat(vim.list_slice(t, 1, 12), "; ")) or nil end
info(("judged: %d acted as treesitter, %d as the built-in, %d did nothing either way"):format(tally.ours, tally.native, tally.unknown))
check("a key acting as treesitter shows an icon and a label naming the target's language, not the built-in's text", #bad.ours == 0, list(bad.ours))
check("a key acting as the built-in shows the help index or default-map text", #bad.native == 0, list(bad.native))
check("a key acting as the built-in with no built-in meaning is hidden", #bad.hidden == 0, list(bad.hidden))
check("a treesitter key acting as a meaningful built-in stays listed", #unlabelled == 0, list(unlabelled))
check("a key acting as the built-in shows no icon of ours", #icons == 0, list(icons))
check("where a key does nothing, its icon and label agree", #mixed == 0, list(mixed))
local missed = {}
for k, v in pairs(WORDING) do
  if v ~= "done" then missed[#missed + 1] = k end
end
check("a heading and an element are named by their node type, after what the key does", #bad.wording == 0 and #missed == 0, list(bad.wording) or (#missed > 0 and ("did not act as treesitter: " .. table.concat(missed, ", ")) or nil))
check("the contexts met keys acting both ways", tally.ours > 0 and tally.native > 0, vim.inspect(tally))
-- off screen in a buffer of ordinary size, a move's label still names the target the move goes to
do
  open("doc.md")
  vim.o.lines = 8
  at("# Title", "Title")
  vim.cmd("normal! zt")
  local bottom = vim.fn.line("w$")
  local s = popup("n")["]c"]
  local r = effect("]c")
  local lang = r.row > bottom and lang_at(r.row, r.col)
  local words, hit = node_words(r.row, r.col), false
  for _, w in ipairs(words) do hit = hit or (#w > 2 and s ~= nil and s.desc:lower():find(w, 1, true) ~= nil) end
  check("a move's label names a target off screen by its language and node type", lang and s ~= nil and s.desc:find(lang, 1, true) ~= nil and hit and vim.startswith(s.desc, "Next class: "),
    ("]c to %d:%d (screen ends at %d) in %s, nodes %s: %s"):format(r.row, r.col, bottom, tostring(lang), table.concat(words, " "), s and s.desc or "hidden"))
  vim.o.lines = 60
end
check("opening buffers adds no which-key spec", #rawget(wkc, "mappings") == specs, specs .. " -> " .. #rawget(wkc, "mappings"))
check("back in normal mode", vim.api.nvim_get_mode().mode == "n", vim.api.nvim_get_mode().mode)
