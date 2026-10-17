-- @desc     with a hunk staged by git outside Neovim, a key the which-key popup lists in that buffer with a label that says it unstages leaves the index clean and the edit in the working tree
-- @areas    keys git which-key
-- @budget   20
-- From the keys-tidy patch to nvim-sbx-keys/checks2/git.lua (section 4). The key is found by its label in the popup
-- saying "unstage", not by its lhs or its map; with no such key nothing is pressed (info only). A hunk staged
-- outside the session is the case gitsigns' undo_stage_hunk cannot undo.

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
local function git(...) return vim.system({ "git", ... }, { text = true }):wait() end

local D = FIX .. "/.nvr-unstage"
local F = D .. "/f.txt"
local base = { "alpha", "beta", "gamma" }
git("init", "-q", D)
vim.fn.writefile(base, F)
git("-C", D, "add", "f.txt")
local r = git("-C", D, "-c", "user.name=nvr", "-c", "user.email=nvr@localhost", "-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", "init")
assert(r.code == 0, "git commit in " .. D .. ": " .. (r.stderr or ""))
vim.fn.writefile(vim.list_extend({ "staged-by-git" }, base), F)
git("-C", D, "add", "f.txt")
local function staged() return vim.trim(git("-C", D, "diff", "--cached", "--name-only").stdout) end
local function unstaged() return vim.trim(git("-C", D, "diff", "--name-only").stdout) end

section("the unstage key unstages a hunk git staged")
vim.cmd.edit(vim.fn.fnameescape(F))
local buf = vim.api.nvim_get_current_buf()
local attached = wait_until(function() return (vim.b[buf].gitsigns_status_dict or {}).added ~= nil end, 5000)
expect(attached and staged() == "f.txt", "gitsigns attached and git has f.txt staged (index: %q)", staged())
local ok, cache = pcall(function() return require("gitsigns.cache").cache end)
local seen = ok and wait_until(function() return cache[buf] ~= nil and #(cache[buf].hunks_staged or {}) > 0 end, 5000)
expect(seen, "gitsigns sees the staged hunk")

-- the keys the popup lists here whose label says they unstage
local keys = {}
for lhs, label in pairs(wk_menu(buf, "n")) do
  if type(label) == "string" and label:lower():find("unstage") then keys[lhs] = label end
end
if not next(keys) then info("the popup lists no normal-mode key that says it unstages; nothing to press") end
for lhs, label in pairs(keys) do
  if staged() ~= "f.txt" then
    git("-C", D, "add", "f.txt")
    wait_until(function() return ok and cache[buf] ~= nil and #(cache[buf].hunks_staged or {}) > 0 end, 5000)
  end
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  feed(lhs)
  vim.wait(5000, function() return staged() == "" end, 100)
  info(("pressed %s (%s)"):format(lhs, label))
  expect(staged() == "" and unstaged() == "f.txt", "%s (%s): index clean (%q), edit still in the tree (%q)", lhs, label, staged(), unstaged())
  expect(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "staged-by-git", "%s: the buffer keeps the edit", lhs)
end
done()
vim.cmd("bwipeout!")
