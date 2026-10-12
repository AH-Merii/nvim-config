-- @desc     in diff mode ]c and [c jump to the next and previous change even in a buffer where the config maps them (a treesitter class move), and outside diff mode such a map still moves the cursor
-- @areas    keys treesitter
-- @budget   20
-- From the keys-tidy patch to nvim-sbx-keys/checks2/textobjects.lua (section 6). Where ]c lands outside diff
-- mode is the map's business: the file is a tracked repo file with a hunk and two classes, so a class or hunk move both move.

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
local function any_map(buf, mode, lhs)
  local raw = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhsraw == raw or m.lhsrawalt == raw then return m end
  end
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhsraw == raw or m.lhsrawalt == raw then return m end
  end
end
local function git(...) return vim.system({ "git", ... }):wait() end
local function jump(keys, from)
  vim.api.nvim_win_set_cursor(0, { from, 0 })
  feed(keys)
  return vim.fn.line(".")
end

local D = FIX .. "/.nvr-diff"
local old = { "class A:", "    def f(self):", "        return 1", "", "", "x = 1", "y = 2", "", "", "class B:", "    pass" }
local CHANGE, LAST = 6, #old
local new = vim.deepcopy(old)
new[CHANGE] = "x = 10"
git("init", "-q", D)
vim.fn.writefile(old, D .. "/a.py")
git("-C", D, "add", "a.py")
local r = git("-C", D, "-c", "user.name=nvr", "-c", "user.email=nvr@localhost", "-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", "init")
assert(r.code == 0, "git commit in " .. D .. ": " .. (r.stderr or ""))
vim.fn.writefile(new, D .. "/a.py")
vim.fn.writefile(old, D .. "/b.py")

vim.cmd("only | edit " .. vim.fn.fnameescape(D .. "/a.py"))
local buf = vim.api.nvim_get_current_buf()
flush()
-- only a hunk move would need gitsigns; the config's ]c does not, so this is not asserted
wait_until(function() return (vim.b[buf].gitsigns_status_dict or {}).added ~= nil end, 3000)
local mapped = {}
for _, lhs in ipairs({ "]c", "[c" }) do
  local m = any_map(buf, "n", lhs)
  if m then mapped[lhs] = true end
  info(("%s outside diff mode: %s"):format(lhs, m and (m.desc or "mapped, no desc") or "not mapped"))
end

section("]c and [c jump to the change in diff mode")
vim.cmd("diffthis | vsplit " .. vim.fn.fnameescape(D .. "/b.py") .. " | diffthis | wincmd p")
flush()
if expect(vim.api.nvim_get_current_buf() == buf and vim.wo.diff, "a.py is current and in diff mode") then
  local dn, dp = jump("]c", 1), jump("[c", LAST)
  expect(dn == CHANGE and dp == CHANGE, "]c from 1 and [c from %d land on the change at %d (got %d, %d)", LAST, CHANGE, dn, dp)
end

section("outside diff mode a ]c or [c map still moves")
vim.cmd("diffoff! | only")
flush()
expect(not vim.wo.diff, "diff mode is off")
if mapped["]c"] then
  local cn = jump("]c", 1)
  expect(cn ~= 1, "]c from 1 moved (got %d)", cn)
end
if mapped["[c"] then
  local cp = jump("[c", LAST)
  expect(cp ~= LAST, "[c from %d moved (got %d)", LAST, cp)
end
if not next(mapped) then info("neither ]c nor [c is mapped: Neovim's own diff jump, nothing to move outside diff mode") end
done()
vim.cmd("%bwipeout!")
