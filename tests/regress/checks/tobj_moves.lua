-- @desc     ]/[ moves reach the host's and the injected languages' objects (markdown fences, HTML script, Vim lua heredoc) in n, x and o with counts, stay the built-in or Neovim's default where no language has the object (.txt, diff-mode ]c), never take ]C/[C, and leave ; and , repeating f/t
-- @areas    treesitter keys
-- @budget   40
-- @version-sensitive
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
local function row_of(pat)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find(pat, 1, true) then return i end
  end
  error("no line " .. pat)
end

local function esc()
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
end

local yank
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() yank = table.concat(vim.v.event.regcontents, "\n") .. " " .. vim.v.event.regtype end,
})

-- what keys do from the cursor, then undone: buffer, cursor (row, 0-based col), visual mode, yank, text change, error.
-- how: nil typed with maps, true without (normal!), or a function standing in for a default map
local function effect(keys, how)
  local buf, cur = vim.api.nvim_get_current_buf(), vim.api.nvim_win_get_cursor(0)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  local seq, modified = vim.fn.undotree().seq_cur, vim.bo[buf].modified
  yank = nil
  vim.v.errmsg = ""
  if type(how) == "function" then
    local ok, e = pcall(how)
    if not ok then vim.v.errmsg = tostring(e) end
  else
    vim.cmd("silent! normal" .. (how and "! " or " ") .. vim.keycode(keys))
  end
  local now = vim.api.nvim_win_get_cursor(0)
  local r = {
    buf = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"),
    row = now[1],
    col = now[2],
    mode = vim.fn.mode():gsub("\22", "^V"),
    yank = yank,
    err = vim.v.errmsg:match("E%d+:") or vim.v.errmsg,
  }
  -- nvim-origami's on_key takes the / of ]/ for a search, and the next key then fails with E490: not the key's effect
  if r.err == "E490:" then r.err = "" end
  esc()
  r.switched = vim.api.nvim_get_current_buf() ~= buf
  if r.switched then vim.cmd("silent! buffer " .. buf) end
  r.changed = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= text
  -- a :normal that ends in an error leaves its change unsynced, out of reach of :undo
  vim.o.undolevels = vim.o.undolevels
  if vim.fn.undotree().seq_cur ~= seq then vim.cmd("silent! undo " .. seq) end
  if table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= text then vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(text, "\n")) end
  if not modified then vim.bo[buf].modified = false end
  vim.api.nvim_win_set_cursor(0, cur)
  return r
end
local function show(r)
  return ("%s %d:%d %s%s%s%s"):format(r.buf, r.row, r.col, r.mode, r.yank and (" yank " .. ("%q"):format(r.yank:sub(1, 40))) or "",
    r.changed and " changed" or "", r.err ~= "" and (" err " .. r.err:sub(1, 40)) or "")
end
local function same(a, b)
  return a.buf == b.buf and a.row == b.row and a.col == b.col and a.mode == b.mode and a.yank == b.yank and a.changed == b.changed and a.err == b.err
end
-- a treesitter move: the cursor went to row (and col) of this buffer, nothing edited, no error
local function moved(r, buf, row, col)
  return r.buf == buf and not r.switched and r.row == row and (col == nil or r.col == col) and not r.changed and r.err == ""
end

-- markdown: the fences' objects from prose and from fence to fence
open("doc.md")
local fdef, ffor, flua, fend = row_of("def add(a"), row_of("for x in rest"), row_of("local function f"), row_of("    return a")
at("# Title")
local r = effect("]f")
check("md title: ]f goes to the python function in the fence", moved(r, "doc.md", fdef, 0), show(r))
r = effect("]p")
check("md title: ]p goes to the fence's first parameter, pastes nothing", moved(r, "doc.md", fdef, ("def add("):len()), show(r))
r = effect("]l")
check("md title: ]l goes to the fence's loop", moved(r, "doc.md", ffor), show(r))
r = effect("]F")
check("md title: ]F goes to the end of the fence's function", moved(r, "doc.md", fend), show(r))
r = effect("]c")
check("md title: ]c goes to the next heading", moved(r, "doc.md", row_of("## Second heading"), 0), show(r))
r = effect("]b")
check("md title: ]b moves within the buffer, no :bnext", r.buf == "doc.md" and not r.switched and r.row > 1 and not r.changed and r.err == "", show(r))
local two, twice = effect("2]f"), effect("]f]f")
check("md title: 2]f is ]f twice, into the lua fence", moved(two, "doc.md", flua) and same(two, twice), show(two) .. " vs " .. show(twice))
at("for x in rest", "rest")
r = effect("]f")
check("md python fence: ]f goes to the function in the lua fence", moved(r, "doc.md", flua), show(r))
at("Last paragraph.")
r = effect("[f")
check("md prose: [f goes back to the lua fence's function", moved(r, "doc.md", flua), show(r))

-- x and o: the same targets, as a selection and as an operator's range
at("# Title")
r = effect("v]f")
check("md x: v]f extends the selection to the fence's function", r.mode == "v" and r.row == fdef and r.col == 0 and not r.changed, show(r))
r = effect("v]l")
check("md x: v]l extends the selection to the fence's loop", r.mode == "v" and r.row == ffor and not r.changed, show(r))
r = effect("y]f")
check("md o: y]f yanks from the cursor to the fence's function", r.yank ~= nil and vim.startswith(r.yank, "# Title") and r.yank:find("```python", 1, true) ~= nil
  and not r.yank:find("add(", 1, true) and not r.changed, show(r))
at("Last paragraph.")
r = effect("y[f")
check("md o: y[f yanks back from the lua fence's function", r.yank ~= nil and vim.startswith(r.yank, "local function f") and r.row == flua, show(r))

-- python: counts
open("a.py")
at("import os")
r = effect("]f")
check("py: ]f goes to the next def", moved(r, "a.py", row_of("def add"), 0), show(r))
two, twice = effect("2]f"), effect("]f]f")
check("py: 2]f is ]f twice", moved(two, "a.py", row_of("def size")) and same(two, twice), show(two) .. " vs " .. show(twice))
local three, thrice = effect("3]p"), effect("]p]p]p")
check("py: 3]p is ]p three times", three.err == "" and same(three, thrice), show(three) .. " vs " .. show(thrice))
r = effect("]c")
check("py: ]c goes to the class", moved(r, "a.py", row_of("class Box"), 0), show(r))

-- plain text: no language, every key is the built-in or Neovim's default map
vim.fn.writefile({ "x" }, FIX .. "/other.txt")
open("other.txt")
open("notes.txt")
local txt = vim.api.nvim_get_current_buf()
at("Paragraph two.")
for _, k in ipairs({ { "]b", "bnext" }, { "[b", "bprevious" }, { "]l", "lnext" }, { "[l", "lprevious" }, { "]a", "next" }, { "[a", "previous" } }) do
  local ours, native = effect(k[1]), effect(k[1], function() vim.cmd("silent " .. k[2]) end)
  check(("txt: %s is :%s"):format(k[1], k[2]), same(ours, native), show(ours) .. " vs " .. show(native))
end
vim.fn.setloclist(0, { { bufnr = txt, lnum = 1, col = 1, text = "one" }, { bufnr = txt, lnum = 4, col = 1, text = "two" } })
local function first() vim.cmd("silent! ll 1") at("Plain text") end
first()
local ours = effect("]l")
first()
local native = effect("]l", function() vim.cmd("silent lnext") end)
check("txt with a loclist: ]l is :lnext", same(ours, native) and native.row == 4, show(ours) .. " vs " .. show(native))
vim.fn.setloclist(0, {}, "f")
vim.fn.setreg("a", "PASTED", "l")
for _, k in ipairs({ "]f", "[f", '"a]p', '"a[p', "]c", "]/", "v]f", 'v"a]p', "y]f", "y]p" }) do
  at("Paragraph two.")
  ours, native = effect(k), effect(k, true)
  check("txt: " .. k .. " is the built-in", same(ours, native), show(ours) .. " vs " .. show(native))
end
at("Paragraph two.")
check("txt: the built-in \"a]p pastes", effect('"a]p', true).changed)

-- shell, HTML <script>, Vim heredoc: injected and host objects
open("t.sh")
at("greet() {")
r = effect("]p")
check("sh: ]p goes to the next argument", moved(r, "t.sh", row_of("greet one"), ("greet "):len()), show(r))
open("plug.vim")
at("lua << EOF")
r = effect("]f")
check("vim lua << EOF: ]f goes to the lua function in the heredoc", moved(r, "plug.vim", row_of("local function hello"), 0), show(r))
open("page.html")
at("<html>")
r = effect("]p")
check("html: ]p goes to the script's first parameter", moved(r, "page.html", row_of("function hello"), ("      function hello("):len()), show(r))

-- diff mode: ]c and [c are the built-in change jumps
open("a.py")
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
lines[row_of("    return total")] = "    return 0"
lines[row_of("        return w * h")] = "        return w + h"
vim.cmd("diffthis")
vim.cmd("vnew")
vim.bo.buftype = "nofile"
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
vim.cmd("diffthis")
vim.cmd("wincmd p")
at("import os")
ours, native = effect("]c"), effect("]c", true)
check("diff: ]c is the built-in next change, not the class", same(ours, native) and native.row == row_of("    return total"), show(ours) .. " vs " .. show(native))
at("x = add(1, 2)")
ours, native = effect("[c"), effect("[c", true)
check("diff: [c is the built-in previous change, not the class", same(ours, native) and native.row == row_of("        return w * h"), show(ours) .. " vs " .. show(native))
vim.cmd("diffoff!")
vim.cmd("only!")

-- ]C and [C: Neovim's own (multicursor on nightly, nothing on stable), never a class-end move
open("a.py")
for _, k in ipairs({ "]C", "v]C", "y]C" }) do
  at("class Box")
  ours, native = effect(k), effect(k, true)
  check("py: " .. k .. " is Neovim's own", same(ours, native), show(ours) .. " vs " .. show(native))
end
for _, k in ipairs({ "[C", "v[C", "y[C" }) do
  at("return w * h")
  ours, native = effect(k), effect(k, true)
  check("py: " .. k .. " is Neovim's own", same(ours, native), show(ours) .. " vs " .. show(native))
end

-- ; and , stay the f/t repeat after a ]/[ move: on the line, onto the f/t char, never to another def (flash's f does not run headless, so its own state may be empty)
at("x = add(1, 2)")
vim.cmd("normal! f(")
vim.cmd("silent! normal [f")
local here, line = vim.api.nvim_win_get_cursor(0), vim.fn.getline(".")
check("py: f( then [f reaches the previous def", here[1] == row_of("def size"), here[1])
for _, k in ipairs({ ";", "," }) do
  vim.api.nvim_win_set_cursor(0, here)
  r = effect(k)
  check("py: " .. k .. " after [f stays an f( repeat", r.err == "" and not r.changed and r.row == here[1] and (r.col == here[2] or line:sub(r.col + 1, r.col + 1) == "("), show(r))
end
check("back in normal mode", vim.api.nvim_get_mode().mode == "n", vim.api.nvim_get_mode().mode)
