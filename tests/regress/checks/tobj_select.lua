-- @desc     a/i objects follow the language at the cursor: fence and injected parameters (markdown, HTML script, Vim lua heredoc), the built-in paragraph in prose and plain text with counts and dot repeat, and a select with nothing at the cursor, later on its line or around it does nothing instead of editing far away
-- @areas    treesitter keys
-- @budget   40
-- @fixture  tobj
-- @args     doc.md

-- what the highlighter parses for the rows on screen; injections off screen stay unparsed, as in a real session
local function open(f)
  vim.cmd.edit(vim.fn.fnameescape(FIX .. "/" .. f))
  local buf = vim.api.nvim_get_current_buf()
  local ok, p = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if ok and p then p:parse({ vim.fn.line("w0") - 1, vim.fn.line("w$") }) end
  return buf
end

-- cursor on the first line containing pat, on sub when given, else column 0
local function at(pat, sub)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find(pat, 1, true) then
      vim.api.nvim_win_set_cursor(0, { i, sub and (assert(l:find(sub, 1, true), sub) - 1) or 0 })
      return i
    end
  end
  error("no line " .. pat)
end

local function esc()
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
end

-- typed keys with maps (bang: without), errors kept out of the message history but still in v:errmsg
local function press(keys, bang)
  vim.v.errmsg = ""
  vim.cmd("silent! normal" .. (bang and "! " or " ") .. vim.keycode(keys))
end

-- the selection after v{keys}: mode, range, text, error
local function sel(keys, bang)
  local cur = vim.api.nvim_win_get_cursor(0)
  press("v" .. keys, bang)
  local m, r = vim.fn.mode(), { err = vim.v.errmsg }
  if m:match("^[vV\22]") then
    local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
    r.text = table.concat(vim.fn.getregion(a, b, { type = m }), "\n")
    if b[2] < a[2] or (b[2] == a[2] and b[3] < a[3]) then a, b = b, a end
    r.mode = m == "\22" and "^V" or m
    r.range = ("%d:%d-%d:%d"):format(a[2], a[3], b[2], b[3])
    r.first, r.last = a[2], b[2]
  else
    r.mode = "none"
  end
  esc()
  r.nothing = r.mode == "v" and r.range == ("%d:%d-%d:%d"):format(cur[1], cur[2] + 1, cur[1], cur[2] + 1) and r.err == ""
  vim.api.nvim_win_set_cursor(0, cur)
  return r
end
local function show(r) return ("%s %s %q%s"):format(r.mode, tostring(r.range), tostring(r.text), r.err ~= "" and (" err " .. r.err) or "") end
local function same(a, b) return a.mode == b.mode and a.range == b.range and a.err == b.err end

-- the buffer text after keys in normal mode (bang: without maps), then undone
local function op(keys, bang)
  local cur = vim.api.nvim_win_get_cursor(0)
  local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local seq, modified = vim.fn.undotree().seq_cur, vim.bo.modified
  press(keys, bang)
  esc()
  local r = { lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), err = vim.v.errmsg }
  r.text = table.concat(r.lines, "\n")
  r.changed = r.text ~= table.concat(before, "\n")
  -- a :normal that ends in an error leaves its change unsynced, out of reach of :undo
  vim.o.undolevels = vim.o.undolevels
  if vim.fn.undotree().seq_cur ~= seq then vim.cmd("silent! undo " .. seq) end
  if table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n") ~= table.concat(before, "\n") then
    vim.api.nvim_buf_set_lines(0, 0, -1, false, before)
  end
  if not modified then vim.bo.modified = false end
  vim.api.nvim_win_set_cursor(0, cur)
  return r
end

-- markdown: prose is native, a fence parameter is the fence language's, nothing far away
open("doc.md")
at("Second paragraph here.")
for _, k in ipairs({ "ip", "ap" }) do
  local ours, native = sel(k), sel(k, true)
  check("md prose: v" .. k .. " is the built-in paragraph", same(ours, native) and native.mode == "V", show(ours) .. " vs built-in " .. show(native))
end
local dap, dap_native = op("dap"), op("dap", true)
check("md prose: dap deletes the built-in paragraph", dap.changed and dap.text == dap_native.text, ("%d lines, built-in %d"):format(#dap.lines, #dap_native.lines))

at("def add(a, b=2", "b=2")
local r = sel("ip")
check("md python fence: vip on a parameter selects it", r.text and vim.trim(r.text) == "b=2", show(r))
local row = at("def add(a, b=2", "b=2")
local c = op("cipX")
check("md python fence: cip changes only that parameter", c.changed and #c.lines == vim.api.nvim_buf_line_count(0) and c.lines[row]:find("X", 1, true) ~= nil
  and not c.lines[row]:find("b=2", 1, true) and c.lines[row]:find("a,", 1, true) ~= nil and c.lines[row]:find("*rest", 1, true) ~= nil, c.changed and c.lines[row] or "no change")

at("local function f(x, y)", "y)")
r = sel("ip")
check("md lua fence: vip on a parameter selects it", r.text and vim.trim(r.text) == "y", show(r))

-- far-edit cases: an object later in the buffer, in another fence or 20 lines away, is never reached
at("a += x", "x")
r = sel("ip")
check("md python fence, no parameter on the line: vip does nothing", r.nothing, show(r))
c = op("dip")
check("md python fence, no parameter on the line: dip edits nothing", not c.changed and c.err == "", c.changed and "changed" or c.err)
at("def add(a, b=2, *rest):", "):")
r = sel("ip")
check("md python fence, after the last parameter: vip does nothing (not the lua fence)", r.nothing, show(r))
at("for x in rest", "rest")
r = sel("ac")
check("md python fence: vac does nothing (no class around or later on the line)", r.nothing, show(r))
at("Prose between fences.")
r = sel("af")
check("md prose: vaf does nothing (not the function in the next fence)", r.nothing, show(r))

-- python file
open("a.py")
at("def add(a, b=2", "b=2")
r = sel("ip")
check("py: vip on a parameter selects it", r.text and vim.trim(r.text) == "b=2", show(r))
at("x = add(1, 2)")
r = sel("ip")
check("py: vip before a call on the same line selects its first argument", r.text and vim.trim(r.text) == "1", show(r))
at("total = a + b", "total")
r = sel("ip")
check("py: vip with no parameter on the line does nothing (not self 7 lines down)", r.nothing, show(r))
c = op("dip")
check("py: dip with no parameter on the line edits nothing", not c.changed and c.err == "", c.changed and "changed" or c.err)
at("import os")
r = sel("af")
check("py: vaf on import does nothing (not the def 3 lines down)", r.nothing, show(r))
at("def add(a, b=2")
r = sel("if")
check("py: vif on a def line selects that function's body", r.first == 5 and r.last >= 9 and r.last <= 11 and r.text:find("return total", 1, true) ~= nil, show(r))
at("total += x")
r = sel("ib")
check("py: vib inside a loop selects the loop body around the cursor", r.first == 8 and r.text and r.text:find("total += x", 1, true) ~= nil and not r.text:find("for x", 1, true), show(r))

-- plain text: every object is the built-in one, with counts and dot repeat
local PARAS = { "Alpha one.", "Alpha two.", "", "Beta one.", "", "Gamma one.", "Gamma two.", "Gamma three.", "", "Delta one.", "", "Epsilon one." }
vim.fn.writefile(PARAS, FIX .. "/paras.txt")
open("paras.txt")
at("Beta one.")
local ours, native = sel("3ip"), sel("3ip", true)
check("txt: v3ip selects three built-in paragraphs", same(ours, native) and native.first == 4 and native.last == 8, show(ours) .. " vs built-in " .. show(native))
at("Alpha one.")
local d2, d2n = op("d2ap"), op("d2ap", true)
check("txt: d2ap deletes two built-in paragraphs", d2.changed and d2.text == d2n.text and #d2.lines == #PARAS - 5, ("%d lines left, built-in %d"):format(#d2.lines, #d2n.lines))
at("Gamma one.")
local dot, dotn = op("dap."), op("dap.", true)
check("txt: dap then . deletes the next paragraph too", dot.changed and dot.text == dotn.text and #dot.lines == #PARAS - 6, ("%d lines left, built-in %d"):format(#dot.lines, #dotn.lines))
open("notes.txt")
at("still paragraph one", "with")
ours, native = sel("ib"), sel("ib", true)
check("txt: vib is the built-in () block", same(ours, native) and native.text == "with parens", show(ours) .. " vs built-in " .. show(native))
for _, k in ipairs({ "ip", "ap", "il", "al" }) do
  at("Paragraph two.")
  ours, native = sel(k), sel(k, true)
  check("txt: v" .. k .. " is the built-in", same(ours, native), show(ours) .. " vs built-in " .. show(native))
end

-- shell: the argument under the cursor
open("t.sh")
at("greet one two", "one")
r = sel("ip")
check("sh: vip on an argument selects it", r.text and vim.trim(r.text) == "one", show(r))
local ap, apn = sel("ap"), sel("ap", true)
check("sh: vap is the argument or the built-in paragraph, nothing further", same(ap, apn) or (ap.first == 5 and ap.last == 5 and ap.text:find("one", 1, true) ~= nil), show(ap))

-- injected code: JS in an HTML script, Lua in a Vim heredoc
open("page.html")
at("function hello(name", "name")
r = sel("ip")
check("html <script>: vip on a parameter selects it", r.text and vim.trim(r.text) == "name", show(r))
open("plug.vim")
at("local function hello(name", "name")
r = sel("ip")
check("vim lua << EOF: vip on a parameter selects it", r.text and vim.trim(r.text) == "name", show(r))
check("back in normal mode", vim.api.nvim_get_mode().mode == "n", vim.api.nvim_get_mode().mode)
