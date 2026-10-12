-- @desc     git keys follow their context: gitsigns hunk maps only in buffers gitsigns is attached to (gone on detach and on :saveas out of the repo), Snacks git pickers only while the cwd is in a repo, log maps only in repo files, gitbrowse only with a remote (also after a fast rename), PR review only with a GitHub remote
-- @areas    keys git which-key
-- @budget   40
-- Ported from nvim-sbx-keys/checks2/git.lua. Repos with remotes are made inside the fixture copy; the
-- outside-git dir is under Neovim's own tempdir, which Neovim removes on exit.

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
-- async vim.system calls whose on_exit has not run yet (the remote checks behind gitbrowse and PR review)
local inflight = 0
local real_system = vim.system
vim.system = function(cmd, opts, on_exit)
  -- a language server runs under vim.system with stdin open and lives as long as the check
  if not on_exit or (opts and opts.stdin == true) then return real_system(cmd, opts, on_exit) end
  inflight = inflight + 1
  local ok, obj = pcall(real_system, cmd, opts, function(...)
    local okc, err = pcall(on_exit, ...)
    inflight = inflight - 1
    if not okc then error(err, 0) end
  end)
  if not ok then
    inflight = inflight - 1
    error(obj, 0)
  end
  return obj
end
-- wait until every started process has answered and what its answer scheduled has run
local function settle()
  for _ = 1, 5 do
    wait_until(function() return inflight == 0 end, 5000)
    flush()
    if inflight == 0 then return end
  end
end
local function buf_map(buf, mode, lhs)
  local raw = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhsraw == raw or m.lhsrawalt == raw then return m end
  end
end
local function global_map(mode, lhs)
  local raw = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhsraw == raw or m.lhsrawalt == raw then return m end
  end
end
local function any_map(buf, mode, lhs) return buf_map(buf, mode, lhs) or global_map(mode, lhs) end
local function git(...) return vim.system({ "git", ... }):wait() end

local NOGIT = vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/nogit"
vim.fn.mkdir(NOGIT .. "/out", "p")
vim.fn.writefile({ "plain text" }, NOGIT .. "/plain.txt")
local W = FIX .. "/.nvr-git"
vim.fn.mkdir(W, "p")
local function attached(buf) return vim.b[buf].gitsigns_status_dict ~= nil end
-- gitsigns' attach ends with its first diff, which adds the hunk counts; an attach asked for before then is dropped
local function attach_done(buf) return attached(buf) and vim.b[buf].gitsigns_status_dict.added ~= nil end
-- a repo with one commit, as a real one has: <leader>Gd diffs against HEAD
local function repo(dir, file, lines)
  git("init", "-q", dir)
  vim.fn.writefile(lines, dir .. "/" .. file)
  git("-C", dir, "add", file)
  local r = git("-C", dir, "-c", "user.name=nvr", "-c", "user.email=nvr@localhost", "-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", "init")
  assert(r.code == 0, "git commit in " .. dir .. ": " .. (r.stderr or ""))
end
local function open(file, lcd)
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  if lcd then vim.cmd.lcd(lcd) end
  settle()
  return buf
end

section("gitsigns maps where gitsigns attached")
-- the maps on_attach creates, found by running it on a scratch buffer
local on_attach = require("gitsigns.config").config.on_attach
local attach_maps = {}
if expect(type(on_attach) == "function", "gitsigns has an on_attach") then
  local probe = vim.api.nvim_create_buf(false, true)
  local function all_maps()
    local t = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(probe, "n")) do t[m.lhsraw] = m.lhs end
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do t[m.lhsraw] = t[m.lhsraw] or m.lhs end
    return t
  end
  local before = all_maps()
  vim.api.nvim_buf_call(probe, function() on_attach(probe) end)
  for raw, lhs in pairs(all_maps()) do
    if not before[raw] then attach_maps[#attach_maps + 1] = lhs end
  end
  table.sort(attach_maps)
  pcall(vim.api.nvim_buf_delete, probe, { force = true })
end
info("on_attach maps: " .. table.concat(vim.tbl_map(vim.fn.keytrans, attach_maps), " "))
expect(#attach_maps > 0, "on_attach creates maps")
local function count(buf)
  local c = 0
  for _, lhs in ipairs(attach_maps) do
    if buf_map(buf, "n", lhs) then c = c + 1 end
  end
  return c
end
-- the file outside git first: by the time gitsigns has finished attaching to the tracked file opened after it,
-- an attach to the outside file would have landed too
local plain = open(NOGIT .. "/plain.txt", NOGIT)
local gbuf = open(FIX .. "/main.lua")
expect(wait_until(function() return attach_done(gbuf) end, 5000), "gitsigns finished attaching to the fixture's main.lua")
-- gitsigns sets its status dict a few ms before it calls on_attach
wait_until(function() return count(gbuf) == #attach_maps end, 2000)
flush()
local okc, gcache = pcall(function() return require("gitsigns.cache").cache end)
local cached = okc and type(gcache) == "table" and gcache[plain] ~= nil
expect(not attached(plain) and vim.b[plain].gitsigns_head == nil and not cached,
  "gitsigns has no state for a file outside git (status dict %s, head %s, cache %s)",
  tostring(attached(plain)), tostring(vim.b[plain].gitsigns_head), tostring(cached))
for _, lhs in ipairs(attach_maps) do
  expect(buf_map(gbuf, "n", lhs) ~= nil, "git buffer has %s", vim.fn.keytrans(lhs))
  expect(any_map(plain, "n", lhs) == nil, "file outside git has no %s (neither local nor global)", vim.fn.keytrans(lhs))
end
vim.cmd.cd(FIX)

section("gitsigns maps go when gitsigns detaches")
repo(W .. "/detach", "f.txt", { "a", "b" })
local dbuf = open(W .. "/detach/f.txt")
wait_until(function() return attach_done(dbuf) end, 5000)
expect(count(dbuf) == #attach_maps, "repo buffer has all %d on_attach maps (has %d)", #attach_maps, count(dbuf))
vim.cmd("Gitsigns detach")
wait_until(function() return not attached(dbuf) and count(dbuf) == 0 end, 3000)
expect(not attached(dbuf) and count(dbuf) == 0, "after :Gitsigns detach: %d on_attach maps left", count(dbuf))
vim.cmd("Gitsigns attach")
expect(wait_until(function() return attach_done(dbuf) end, 5000), "gitsigns re-attached on :Gitsigns attach")
expect(count(dbuf) == #attach_maps, "after :Gitsigns attach: %d of %d maps back", count(dbuf), #attach_maps)
vim.cmd("silent saveas! " .. vim.fn.fnameescape(NOGIT .. "/out/f.txt"))
wait_until(function() return not attached(dbuf) and count(dbuf) == 0 end, 3000)
expect(not attached(dbuf) and count(dbuf) == 0, "after :saveas out of the repo: %d on_attach maps left", count(dbuf))
vim.cmd.cd(FIX)

-- what a map opens: the Snacks picker or gitbrowse its callback calls
local function opens(map)
  if not map.callback or map.expr == 1 then return nil end
  local hit
  local picker, gitbrowse = Snacks.picker, Snacks.gitbrowse
  Snacks.picker = setmetatable({}, { __index = function(_, k) return function() hit = "picker:" .. k end end })
  Snacks.gitbrowse = function() hit = "gitbrowse" end
  pcall(map.callback)
  Snacks.picker, Snacks.gitbrowse = picker, gitbrowse
  return hit
end
local leader = vim.g.mapleader or "\\"
local function under_git_prefix(m) return m.lhs:sub(1, #leader + 1) == leader .. "g" or m.lhs:sub(1, #leader + 1) == leader .. "G" end
-- lhs of maps under <leader>g/<leader>G whose callback satisfies pred
local function maps_opening(list, pred)
  local out = {}
  for _, m in ipairs(list) do
    if under_git_prefix(m) then
      local what = opens(m)
      if what and pred(what) then out[#out + 1] = m.lhs end
    end
  end
  table.sort(out)
  return out
end
local function git_picker(what) return what:match("^picker:git_") ~= nil end
local function global_pickers() return maps_opening(vim.api.nvim_get_keymap("n"), git_picker) end

section("git pickers follow the cwd")
open(FIX .. "/main.lua")
vim.cmd.cd(FIX)
settle()
local in_repo = global_pickers()
info("global git pickers, cwd in repo: " .. table.concat(in_repo, " "))
expect(#in_repo > 0, "global git picker maps exist while the cwd is a repo")
vim.cmd.cd(NOGIT)
settle()
local outside = global_pickers()
expect(#outside == 0, "no global git picker map once :cd leaves the repo (left: %s)", table.concat(outside, " "))
vim.cmd.cd(FIX)
settle()
expect(vim.deep_equal(global_pickers(), in_repo), "the same picker maps return after :cd back")
vim.cmd.cd(NOGIT .. "/..")
vim.cmd.cd(FIX .. "/rs")
settle()
expect(vim.deep_equal(global_pickers(), in_repo), "pickers stay in a subdirectory of the repo")
vim.cmd.cd(FIX)

section("log maps follow the buffer's file")
for _, cwd in ipairs({ FIX, NOGIT }) do
  vim.cmd.cd(cwd)
  settle()
  local pbuf = open(NOGIT .. "/plain.txt")
  local mbuf = open(FIX .. "/main.lua")
  local here = maps_opening(vim.api.nvim_buf_get_keymap(mbuf, "n"), git_picker)
  local there = maps_opening(vim.api.nvim_buf_get_keymap(pbuf, "n"), git_picker)
  expect(#here > 0, "[cwd %s] a repo file has buffer-local git log maps", cwd)
  expect(#there == 0, "[cwd %s] a file outside git has no buffer-local git picker map (has: %s)", cwd, table.concat(there, " "))
  local scratch = vim.api.nvim_create_buf(true, false)
  flush()
  expect(#maps_opening(vim.api.nvim_buf_get_keymap(scratch, "n"), git_picker) == 0, "[cwd %s] an unnamed buffer has none", cwd)
  for _, lhs in ipairs(here) do
    vim.api.nvim_buf_call(pbuf, function()
      local m = any_map(pbuf, "n", lhs)
      expect(m == nil or not (opens(m) or ""):match("^picker:git_log"), "[cwd %s] %s outside git does not open a git log", cwd, vim.fn.keytrans(lhs))
    end)
  end
end
vim.cmd.cd(FIX)

-- three repos: no remote, a non-GitHub remote, a GitHub remote
local R = W .. "/remote"
local repos = { none = "", other = "https://gitlab.com/x/y.git", github = "git@github.com:x/y.git" }
for name, url in pairs(repos) do
  repo(R .. "/" .. name, "file.txt", { "x" })
  if url ~= "" then git("-C", R .. "/" .. name, "remote", "add", "origin", url) end
end
local function browse_maps(buf) return maps_opening(vim.api.nvim_buf_get_keymap(buf, "n"), function(w) return w == "gitbrowse" end) end

section("gitbrowse needs a remote on the buffer's repo")
expect(#maps_opening(vim.api.nvim_get_keymap("n"), function(w) return w == "gitbrowse" end) == 0, "no global gitbrowse map")
for name, url in pairs(repos) do
  local buf = open(R .. "/" .. name .. "/file.txt")
  -- browse_maps runs every <leader>g/G callback, so the gitsigns ones are run only once they are mapped
  wait_until(function() return attach_done(buf) and count(buf) == #attach_maps end, 5000)
  expect(count(buf) == #attach_maps, "the %s repo's buffer has all %d on_attach maps (has %d)", name, #attach_maps, count(buf))
  local has = #browse_maps(buf) > 0
  expect(has == (url ~= ""), "gitbrowse map in the %s repo's buffer: %s", name, tostring(has))
end
expect(#browse_maps(open(NOGIT .. "/plain.txt")) == 0, "no gitbrowse map outside git")
expect(#browse_maps(open(FIX .. "/main.lua")) == 0, "no gitbrowse map in the fixture repo, which has no remote")

section("a rename out of the repo before the remote check answers")
-- an attach begun before the rename can leave gitsigns on the old path for good, and its callbacks then fail on the untracked file
local gitsigns_lhs = {}
for _, lhs in ipairs(attach_maps) do gitsigns_lhs[lhs] = true end
local function browse_maps_without_gitsigns(buf)
  local list = vim.tbl_filter(function(m) return not gitsigns_lhs[m.lhs] end, vim.api.nvim_buf_get_keymap(buf, "n"))
  return maps_opening(list, function(w) return w == "gitbrowse" end)
end
for i = 1, 3 do
  vim.fn.writefile({ "x" }, R .. "/github/race" .. i .. ".txt")
  vim.cmd.edit(R .. "/github/race" .. i .. ".txt")
  local rbuf = vim.api.nvim_get_current_buf()
  vim.cmd("silent file " .. vim.fn.fnameescape(NOGIT .. "/renamed" .. i .. ".txt"))
  settle()
  expect(#browse_maps_without_gitsigns(rbuf) == 0, "[%d] renamed out of the repo at once: gitbrowse map present", i)
end

section("PR review needs a GitHub remote on the cwd's repo")
local spec = require("lazy.core.config").plugins["github-pr-reviewer.nvim"]
if expect(spec ~= nil, "github-pr-reviewer.nvim is in the config, for the repo with a GitHub remote") then
  local cmds = spec.cmd or {}
  cmds = type(cmds) == "string" and { cmds } or cmds
  if expect(#cmds > 0, "github-pr-reviewer lazy-loads on its commands, so its maps can come and go") then
    local function pr_maps()
      local out = {}
      for _, mode in ipairs({ "n", "v" }) do
        for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
          for _, c in ipairs(cmds) do
            if (m.rhs or ""):find(c, 1, true) then out[#out + 1] = mode .. ":" .. m.lhs end
          end
        end
      end
      table.sort(out)
      return out
    end
    local seen
    for _, case in ipairs({ { "github", true }, { "other", false }, { "none", false }, { "github", true } }) do
      vim.cmd.cd(R .. "/" .. case[1])
      settle()
      local got = pr_maps()
      expect((#got > 0) == case[2], "cwd %s repo: PR maps %s", case[1], #got > 0 and table.concat(got, " ") or "none")
      if case[2] then
        expect(seen == nil or vim.deep_equal(seen, got), "the same PR maps each time")
        seen = got
      end
    end
    vim.cmd.cd(NOGIT)
    settle()
    expect(#pr_maps() == 0, "no PR maps with the cwd outside git")
  end
end
vim.cmd.cd(FIX)
vim.system = real_system
done()
