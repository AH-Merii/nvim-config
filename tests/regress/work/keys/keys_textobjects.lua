-- @desc     pressed in each fixture buffer, ]f reaches the file's first function where a language in the buffer has textobjects and is the built-in where none has, a ]/[ key's which-key label differs from its built-in label exactly where the key acts unlike the built-in, a filetype change re-derives both, a markdown code block brings its language's selects and moves until it goes, and the treesitter toggle exists iff a parser is active and flips highlighting
-- @areas    keys treesitter which-key
-- @budget   40
-- @version-sensitive
-- Replaces work/keys/keys_textobjects.lua: judged by pressing the keys, not by which maps exist.

local cur, n, bad
local function done()
  if cur and bad == 0 then check(cur, true, n .. " assertions") end
end
local function section(name)
  done()
  cur, n, bad = name, 0, 0
end
local function expect(ok, fmt, ...)
  n = n + 1
  if not ok then
    bad = bad + 1
    check(cur .. ": " .. fmt:format(...), false)
  end
  return ok
end
-- run what autocmds and handlers scheduled; two rounds cover a schedule made from a scheduled callback
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end
local function buf_map(buf, mode, lhs)
  local raw = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhsraw == raw or m.lhsrawalt == raw then return m end
  end
end

-- which-key schedules loading its spec when set up after VimEnter
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded, "which-key.config never reached loaded") then return end
local Buf, Util = require("which-key.buf"), require("which-key.util")
local MOVES = { "]f", "[f", "]F", "[F", "]c", "[c", "]p", "[p", "]b", "[b", "]B", "[B", "]i", "[i", "]l", "[l", "]a", "[a", "]r", "[r" }
-- Snacks registers the treesitter toggle when a buffer with a parser first maps it, so look it up when needed
local function ts_desc()
  local t = Snacks.toggle.toggles.treesitter
  return t and ("Toggle " .. t.opts.name)
end
-- the treesitter toggle map that would run in buf, buffer-local or global
local function toggle_map(buf)
  local desc = ts_desc()
  if not desc then return nil end
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if m.desc == desc then return m end
  end
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    if m.desc == desc and not buf_map(buf, "n", m.lhs) then return m end
  end
end

-- what keys do in normal mode from the cursor, then undone: buffer switch, cursor, text change, error.
-- how: nil typed with maps, true without (normal!), or a function standing in for a default map
local function effect(keys, how)
  local buf, at = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local seq, modified = vim.fn.undotree().seq_cur, vim.bo[buf].modified
  vim.v.errmsg = ""
  if type(how) == "function" then
    local ok, e = pcall(how)
    if not ok then vim.v.errmsg = tostring(e) end
  else
    vim.cmd("silent! normal" .. (how and "! " or " ") .. vim.keycode(keys))
  end
  local now = vim.api.nvim_win_get_cursor(0)
  local r = { row = now[1], col = now[2], err = vim.v.errmsg:match("E%d+:") or vim.v.errmsg }
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  r.switched = vim.api.nvim_get_current_buf() ~= buf
  if r.switched then vim.cmd("silent! buffer " .. buf) end
  r.changed = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= text
  -- a :normal that ends in an error leaves its change unsynced, out of reach of :undo
  vim.o.undolevels = vim.o.undolevels
  if vim.fn.undotree().seq_cur ~= seq then vim.cmd("silent! undo " .. seq) end
  if table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= text then vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n")) end
  if not modified then vim.bo[buf].modified = false end
  vim.api.nvim_win_set_cursor(0, at)
  r.nothing = not r.switched and not r.changed and r.err == "" and r.row == at[1] and r.col == at[2]
  return r
end
local function same(a, b) return a.row == b.row and a.col == b.col and a.switched == b.switched and a.changed == b.changed and a.err == b.err end
local function show(r) return ("%d:%d%s%s%s"):format(r.row, r.col, r.switched and " switched" or "", r.changed and " changed" or "", r.err ~= "" and (" " .. r.err) or "") end
-- the built-in: Neovim's default map (]b :bnext, ]B :blast, ]a :next, ]l :lnext) or the command
local DEFAULT = { ["]b"] = "bnext", ["[b"] = "bprevious", ["]B"] = "blast", ["[B"] = "brewind", ["]a"] = "next", ["[a"] = "previous", ["]l"] = "lnext", ["[l"] = "lprevious" }
local function builtin(lhs)
  if DEFAULT[lhs] then return effect(lhs, function() vim.cmd("silent " .. DEFAULT[lhs]) end) end
  return effect(lhs, true)
end
-- "ts" when the key acts unlike the built-in, "builtin" when it does the same and something happened, nil when neither did anything
local function kind(lhs)
  local ours, native = effect(lhs), builtin(lhs)
  if not same(ours, native) then return "ts", ours, native end
  return (not native.nothing) and "builtin" or nil, ours, native
end
local function label(buf, lhs)
  local m = Buf.get({ buf = buf, mode = "n", update = true })
  local node = m and m.tree.root:find(Util.keys(lhs, { norm = true }))
  return node and not node.hidden and tostring(node.desc) or nil
end
-- whether any language tree in buf has a textobjects query
local function has_objects(buf)
  local ok, p = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if not ok or not p then return false end
  p:parse(true)
  local any = false
  p:for_each_tree(function(_, t) any = any or vim.treesitter.query.get(t:lang(), "textobjects") ~= nil end)
  return any
end

local NOGIT = vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/nogit"
vim.fn.mkdir(NOGIT, "p")
vim.fn.writefile({ "plain text" }, NOGIT .. "/plain.txt")
-- the first function from the top: its line; 0 where a language has functions but the file none (notes.md's lua block)
local FIRST_FUNCTION = { ["main.lua"] = 3, ["app.py"] = 4, ["index.ts"] = 1, ["main.go"] = 5, ["hello.c"] = 3, ["notes.md"] = 0 }
local files = { "main.lua", "app.py", "index.ts", "notes.md", "pyproject.toml", "main.go", "hello.c", "app.conf", NOGIT .. "/plain.txt" }
local seen = {}
for _, f in ipairs(files) do
  vim.cmd.edit(f)
  local buf = vim.api.nvim_get_current_buf()
  flush()
  local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
  seen[#seen + 1] = { buf = buf, name = vim.fn.fnamemodify(f, ":t"), parser = lang ~= nil and vim.treesitter.language.add(lang) == true, objects = has_objects(buf) }
end

section("fixture coverage")
expect(vim.iter(seen):any(function(s) return not s.objects end), "some buffer has no textobjects")
expect(vim.iter(seen):any(function(s) return s.objects end), "some buffer has textobjects")

section("]f follows the buffer's languages")
for _, s in ipairs(seen) do
  vim.cmd.buffer(s.buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local k, ours, native = kind("]f")
  local want = FIRST_FUNCTION[s.name]
  if not s.objects then
    expect(k ~= "ts", "%s (no textobjects): ]f is the built-in, got %s vs %s", s.name, show(ours), show(native))
  elseif want == 0 then
    expect(ours.nothing, "%s: ]f does nothing, no function ahead, got %s", s.name, show(ours))
  elseif want then
    expect(not ours.switched and ours.row == want and ours.err == "", "%s: ]f goes to the function on line %d, got %s", s.name, want, show(ours))
  end
end

-- the label a key shows where it is the built-in for sure: plain.txt has no language
local plain = seen[#seen]
vim.cmd.buffer(plain.buf)
local ref = {}
for _, lhs in ipairs(MOVES) do ref[lhs] = label(plain.buf, lhs) end
-- other listed buffers exist, so :bnext switches
section("]/[ labels say what the key does in the buffer")
for _, s in ipairs(seen) do
  vim.cmd.buffer(s.buf)
  local wrong = {}
  for _, lhs in ipairs(MOVES) do
    vim.api.nvim_win_set_cursor(0, lhs:sub(1, 1) == "]" and { 1, 0 } or { vim.api.nvim_buf_line_count(0), 0 })
    local l = label(s.buf, lhs)
    local k, ours = kind(lhs)
    if k == "ts" and l ~= nil and l == ref[lhs] then
      wrong[#wrong + 1] = ("%s acts as treesitter (%s) but shows the built-in label %q"):format(lhs, show(ours), l)
    elseif k == "builtin" and l ~= ref[lhs] then
      wrong[#wrong + 1] = ("%s acts as the built-in (%s) but shows %q, not %q"):format(lhs, show(ours), tostring(l), tostring(ref[lhs]))
    end
  end
  table.sort(wrong)
  expect(#wrong == 0, "%s: %s", s.name, table.concat(wrong, "; "))
end

section("treesitter toggle only where a parser is active")
for _, s in ipairs(seen) do
  local tt = toggle_map(s.buf)
  expect((tt ~= nil) == s.parser, "%s: toggle %s, parser %s", s.name, tt and "present" or "absent", tostring(s.parser))
  if tt and tt.callback and s.parser then
    vim.cmd.buffer(s.buf)
    local before = vim.treesitter.highlighter.active[s.buf] ~= nil
    tt.callback()
    local mid = vim.treesitter.highlighter.active[s.buf] ~= nil
    tt.callback()
    local after = vim.treesitter.highlighter.active[s.buf] ~= nil
    expect(mid ~= before and after == before, "%s: the toggle flips highlighting and back", s.name)
  end
end

section("a filetype change re-derives what the keys do")
vim.cmd.edit("main.lua")
local buf = vim.api.nvim_get_current_buf()
flush()
vim.bo[buf].filetype = "text"
flush()
local stray = {}
for _, lhs in ipairs(MOVES) do
  vim.api.nvim_win_set_cursor(0, lhs:sub(1, 1) == "]" and { 1, 0 } or { vim.api.nvim_buf_line_count(0), 0 })
  if kind(lhs) == "ts" then stray[#stray + 1] = lhs end
end
expect(#stray == 0, "lua buffer set to ft=text: every move is the built-in (treesitter: %s)", table.concat(stray, " "))
expect(toggle_map(buf) == nil, "lua buffer set to ft=text drops the treesitter toggle")
vim.bo[buf].filetype = "lua"
flush()
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local r = effect("]f")
expect(r.row == FIRST_FUNCTION["main.lua"] and r.err == "", "then ft=lua: ]f goes to the function again, got %s", show(r))
vim.cmd("bwipeout!")

section("a markdown code block brings its language's selects and moves")
local function sel(keys)
  vim.fn.setpos("'<", { 0, 0, 0, 0 })
  vim.fn.setpos("'>", { 0, 0, 0, 0 })
  feed(keys .. "<Esc>")
  -- an object that does not exist beeps, and the beep flushes the typed <Esc>
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  return vim.fn.line("'<"), vim.fn.line("'>")
end
vim.fn.mkdir(".nvr-inject", "p")
vim.fn.writefile({ "# Notes", "", "First prose line", "second prose line.", "", "```python", "def add(a, b):", "    return a + b", "```" }, ".nvr-inject/code.md")
vim.cmd.edit(".nvr-inject/code.md")
local md = vim.api.nvim_get_current_buf()
flush()
vim.treesitter.get_parser(md):parse({ vim.fn.line("w0") - 1, vim.fn.line("w$") }) -- what the highlighter does for the rows on screen
flush()
vim.api.nvim_win_set_cursor(0, { 8, 6 })
local s1, e1 = sel("vaf")
expect(s1 == 7 and e1 == 8, "vaf in a python block selects the function (got %d..%d)", s1, e1)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
r = effect("]f")
expect(r.row == 7 and r.err == "" and not r.switched, "]f from the heading goes to the block's function, got %s", show(r))
vim.api.nvim_buf_set_lines(md, 5, 9, false, {})
vim.treesitter.get_parser(md):parse({ vim.fn.line("w0") - 1, vim.fn.line("w$") })
flush()
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local k, ours, native = kind("]f")
expect(k ~= "ts", "without the block, ]f is the built-in (got %s, built-in %s)", show(ours), show(native))
vim.api.nvim_win_set_cursor(0, { 3, 2 })
local s3, e3 = sel("vaf")
expect(s3 == 0 or (s3 == 3 and e3 == 3), "without the block, vaf selects nothing (got %d..%d)", s3, e3)
local s2, e2 = sel("vap")
expect(s2 == 3 and e2 >= 4, "without code, vap selects the prose paragraph (got %d..%d)", s2, e2)
done()
