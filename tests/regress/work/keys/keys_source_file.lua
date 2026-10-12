-- @desc     a key that sources the current file exists only in Lua and Vim script buffers, where :source runs them, and there it sources the file once; in other buffers no key sources the file, neither a buffer-local nor a global map
-- @areas    keys editing
-- @budget   20
-- Ported from nvim-sbx-keys/checks2/source.lua. The key is found by what its rhs or callback runs, not by its lhs or desc.

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

-- the code a map runs: its rhs, or the source lines of its callback
local files = {}
local function body(m)
  if m.rhs and m.rhs ~= "" then return m.rhs end
  if not m.callback then return "" end
  local i = debug.getinfo(m.callback, "S")
  if not i or i.source:sub(1, 1) ~= "@" or i.linedefined < 1 then return "" end
  local path = i.source:sub(2)
  if files[path] == nil then
    local ok, lines = pcall(vim.fn.readfile, path)
    files[path] = ok and lines or false
  end
  if not files[path] then return "" end
  return table.concat(files[path], "\n", i.linedefined, math.min(i.lastlinedefined, #files[path]))
end
local function sources(text)
  local t = text:lower()
  return t:find("%f[%a]so%a*%s*%%") or t:find("%f[%a]so%a*%s*<cr>") or t:find("%f[%a]so%a*%s*|")
    or t:find("vim%.cmd%.so") or t:find("vim%.cmd%s*%(?%s*[\"']so") or t:find("luafile") or t:find("dofile")
end
-- normal-mode maps that would run in buf and look like they source a file: buffer-local, then unshadowed global
local function candidates(buf)
  local out, local_raw = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    local_raw[m.lhsraw] = true
    if sources(body(m)) then out[m.lhsraw] = m.lhs end
  end
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    if not local_raw[m.lhsraw] and sources(body(m)) then out[m.lhsraw] = m.lhs end
  end
  return out
end
-- times the file sourced itself when lhs is typed
local function press(raw)
  vim.g.nvr_src = 0
  pcall(vim.api.nvim_feedkeys, raw, "mx", false)
  pcall(vim.api.nvim_feedkeys, vim.keycode("<Esc>"), "nx", false)
  flush()
  return vim.g.nvr_src
end
local function names(set)
  local t = vim.tbl_map(vim.fn.keytrans, vim.tbl_keys(set))
  table.sort(t)
  return table.concat(t, " ")
end

local D = FIX .. "/.nvr-src"
vim.fn.mkdir(D, "p")
local vimscript = { "let g:nvr_src = get(g:, 'nvr_src', 0) + 1" }
vim.fn.writefile({ "vim.g.nvr_src = (vim.g.nvr_src or 0) + 1" }, D .. "/a.lua")
vim.fn.writefile(vimscript, D .. "/b.vim")
-- valid Vim script in the others too, so a map that sources them anyway is seen, not just an error
vim.fn.writefile(vimscript, D .. "/c.txt")
vim.fn.writefile(vimscript, D .. "/d.py")

section("a key sources the file in Lua and Vim script buffers")
local keys = {} -- lhsraw -> true, every key that sourced a sourceable buffer
for _, f in ipairs({ "a.lua", "b.vim" }) do
  vim.cmd.edit(D .. "/" .. f)
  local buf = vim.api.nvim_get_current_buf()
  flush()
  local hits = {}
  info(("%s: candidates %s"):format(f, names(candidates(buf))))
  for raw in pairs(candidates(buf)) do
    local times = press(raw)
    if times > 0 then
      hits[raw] = true
      keys[raw] = true
      expect(times == 1, "%s (%s): %s sourced it %d times", f, vim.bo[buf].filetype, vim.fn.keytrans(raw), times)
    end
  end
  expect(next(hits) ~= nil, "%s (%s): no key sources it (candidates: %s)", f, vim.bo[buf].filetype, names(candidates(buf)))
  info(("%s: sourced by %s"):format(f, names(hits)))
end

section("no key sources the file in other buffers")
for _, f in ipairs({ "c.txt", "d.py" }) do
  vim.cmd.edit(D .. "/" .. f)
  local buf = vim.api.nvim_get_current_buf()
  flush()
  local try = vim.tbl_extend("keep", {}, keys, candidates(buf))
  local hits = {}
  for raw in pairs(try) do
    if press(raw) > 0 then hits[raw] = true end
  end
  expect(next(hits) == nil, "%s (%s): sourced by %s", f, vim.bo[buf].filetype, names(hits))
end
done()
