-- @desc     git keys are listed by which-key, and act when pressed, only in their context: the gitsigns keys in buffers gitsigns is attached to (not after a detach or a :saveas out of the repo), each hunk key where it acts on a hunk, the Snacks git pickers while the cwd is in a repo, the log keys in repo files, gitbrowse with a remote (also after a fast rename), PR review with a GitHub remote
-- @areas    keys git which-key
-- @budget   40
-- Judged by pressing the keys and reading which-key's popup, never by which maps exist. Repos with remotes are
-- made inside the fixture copy; the outside-git dir is under Neovim's own tempdir, which Neovim removes on exit.

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
local function git(...) return real_system({ "git", ... }, { text = true }):wait() end

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

-- The git keys, from the config's key list, written out here so the check does not read the config's tables
-- <leader>Gu acts on a staged hunk only: keys_act_here and keys_git_unstage judge it
local HUNK_KEYS = { "]g", "[g", "<leader>gb", "<leader>gd", "<leader>Gr", "<leader>GR", "<leader>Gs", "<leader>Gd", "<leader>TG" }
-- the keys that act anywhere in a buffer gitsigns is attached to; the hunk keys also need a hunk (keys_act_here)
local ATTACH_KEYS = { "<leader>gb", "<leader>Gd", "<leader>TG" }
local PICKERS = { ["<leader>gB"] = "git_branches", ["<leader>gl"] = "git_log", ["<leader>gs"] = "git_status", ["<leader>gS"] = "git_stash", ["<leader>gD"] = "git_diff" }
local FILE_LOGS = { ["<leader>gL"] = "git_log_line", ["<leader>gf"] = "git_log_file" }
local BROWSE = "<leader>GB"
local PR = "<leader>p"

local function listed(buf, lhs, mode) return wk_lists(buf, mode or "n", lhs) ~= nil end
-- which of keys which-key lists in buf, as "lhs lhs ..."
local function listing(buf, keys)
  local out = {}
  for _, lhs in ipairs(keys) do
    if listed(buf, lhs) then out[#out + 1] = lhs end
  end
  return table.concat(out, " ")
end
local function keys_of(t)
  local out = vim.tbl_keys(t)
  table.sort(out)
  return out
end

-- what pressing lhs in the current buffer opens: the Snacks picker or gitbrowse it calls, nil for none. Snacks'
-- picker and gitbrowse are stood in for, so nothing opens. Typed under :silent!, so where the key is Vim's own (gf)
-- its error does not count.
local function opens(lhs, mode)
  local hit
  local picker, gitbrowse = Snacks.picker, Snacks.gitbrowse
  Snacks.picker = setmetatable({}, { __index = function(_, k) return function() hit = "picker:" .. k end end })
  Snacks.gitbrowse = function() hit = "gitbrowse" end
  local buf, lines = vim.api.nvim_get_current_buf(), vim.api.nvim_buf_get_lines(0, 0, -1, false)
  pcall(vim.cmd, ("silent! call nvim_feedkeys(%s, 'mx', v:false)"):format(vim.fn.string(vim.keycode((mode == "x" and "V" or "") .. lhs))))
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  flush()
  Snacks.picker, Snacks.gitbrowse = picker, gitbrowse
  -- Vim's own keys may have edited the text
  if vim.api.nvim_buf_is_valid(buf) and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= table.concat(lines, "\n") then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modified = false
  end
  return hit
end

section("gitsigns keys act where gitsigns is attached")
-- a tracked file with one unstaged hunk on line 3
local HR = W .. "/hunks"
local BASE = { "a", "b", "c", "d", "e", "f", "g" }
local EDITED = { "a", "b", "C", "d", "e", "f", "g" }
repo(HR, "f.txt", BASE)
vim.fn.writefile(EDITED, HR .. "/f.txt")
local hbuf = open(HR .. "/f.txt")
local function hunks() return #(require("gitsigns").get_hunks(hbuf) or {}) end
local function staged() return vim.trim(git("-C", HR, "diff", "--cached", "--name-only").stdout) end
expect(wait_until(function() return attach_done(hbuf) and hunks() == 1 end, 5000), "gitsigns attached to the edited file and sees its hunk")
local function windows() return #vim.api.nvim_list_wins() end
local function close_others()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then pcall(vim.api.nvim_win_close, w, true) end
  end
  vim.cmd("silent! only")
  if vim.api.nvim_get_current_buf() ~= hbuf then vim.cmd.buffer(hbuf) end
end
-- back to EDITED with its hunk, nothing staged, one window
local function restore()
  close_others()
  if staged() ~= "" then git("-C", HR, "reset", "-q") end
  if table.concat(vim.api.nvim_buf_get_lines(hbuf, 0, -1, false), "\n") ~= table.concat(EDITED, "\n") then
    vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, EDITED)
  end
  vim.cmd("silent write")
  vim.cmd("Gitsigns refresh")
  wait_until(function() return hunks() == 1 and staged() == "" end, 3000)
end
-- each key's effect, from a cursor on the line that is not in the hunk unless the key acts on the hunk
local said = function() return #Snacks.notifier.get_history() end
local ACTS = {
  ["]g"] = { from = { 1, 0 }, done = function() return vim.fn.line(".") == 3 end, what = "cursor to the hunk on line 3" },
  ["[g"] = { from = { 7, 0 }, done = function() return vim.fn.line(".") == 3 end, what = "cursor to the hunk on line 3" },
  ["<leader>gb"] = { from = { 3, 0 }, window = true, what = "a blame window" },
  ["<leader>gd"] = { from = { 3, 0 }, window = true, what = "a hunk preview window" },
  ["<leader>Gd"] = { from = { 3, 0 }, window = true, what = "a diff window" },
  ["<leader>Gs"] = { from = { 3, 0 }, done = function() return staged() == "f.txt" end, what = "the hunk staged" },
  ["<leader>Gr"] = { from = { 3, 0 }, done = function() return vim.api.nvim_buf_get_lines(hbuf, 2, 3, false)[1] == "c" end, what = "the hunk reset" },
  ["<leader>GR"] = { from = { 1, 0 }, done = function() return vim.api.nvim_buf_get_lines(hbuf, 2, 3, false)[1] == "c" end, what = "the buffer reset" },
  ["<leader>TG"] = { from = { 1, 0 }, label = true, what = "its which-key label flips" },
}
for _, lhs in ipairs(HUNK_KEYS) do
  local a = ACTS[lhs]
  restore()
  vim.api.nvim_win_set_cursor(0, a.from)
  local wins, notes, label = windows(), said(), wk_lists(hbuf, "n", lhs)
  feed(lhs)
  local ok = wait_until(function()
    if a.window then return windows() > wins end
    if a.notice then return said() > notes end
    if a.label then return true end
    return a.done()
  end, 3000)
  if a.label then
    ok = wk_lists(hbuf, "n", lhs) ~= label
    feed(lhs)
  end
  expect(ok, "%s: %s", vim.fn.keytrans(vim.keycode(lhs)), a.what)
end
restore()
vim.cmd.cd(FIX)

section("gitsigns keys are listed where gitsigns is attached")
-- the file outside git first: by the time gitsigns has finished attaching to the tracked file opened after it,
-- an attach to the outside file would have landed too
local plain = open(NOGIT .. "/plain.txt", NOGIT)
local gbuf = open(FIX .. "/main.lua")
expect(wait_until(function() return attach_done(gbuf) end, 5000), "gitsigns finished attaching to the fixture's main.lua")
flush()
local okc, gcache = pcall(function() return require("gitsigns.cache").cache end)
local cached = okc and type(gcache) == "table" and gcache[plain] ~= nil
expect(not attached(plain) and vim.b[plain].gitsigns_head == nil and not cached,
  "gitsigns has no state for a file outside git (status dict %s, head %s, cache %s)",
  tostring(attached(plain)), tostring(vim.b[plain].gitsigns_head), tostring(cached))
local all = table.concat(ATTACH_KEYS, " ")
wk_wait(gbuf, "n", ATTACH_KEYS[#ATTACH_KEYS], true)
expect(listing(gbuf, ATTACH_KEYS) == all, "a git buffer lists %s (lists: %s)", all, listing(gbuf, ATTACH_KEYS))
expect(listing(plain, HUNK_KEYS) == "", "a file outside git lists none (lists: %s)", listing(plain, HUNK_KEYS))
vim.cmd.cd(FIX)

section("gitsigns keys go when gitsigns detaches")
repo(W .. "/detach", "f.txt", { "a", "b" })
local dbuf = open(W .. "/detach/f.txt")
wait_until(function() return attach_done(dbuf) end, 5000)
wk_wait(dbuf, "n", ATTACH_KEYS[#ATTACH_KEYS], true)
expect(listing(dbuf, ATTACH_KEYS) == all, "repo buffer lists them all (lists: %s)", listing(dbuf, ATTACH_KEYS))
vim.cmd("Gitsigns detach")
wait_until(function() return not attached(dbuf) end, 3000)
wk_wait(dbuf, "n", ATTACH_KEYS[1], false, 3000)
expect(not attached(dbuf) and listing(dbuf, HUNK_KEYS) == "", "after :Gitsigns detach: lists %s", listing(dbuf, HUNK_KEYS))
vim.cmd("Gitsigns attach")
expect(wait_until(function() return attach_done(dbuf) end, 5000), "gitsigns re-attached on :Gitsigns attach")
wk_wait(dbuf, "n", ATTACH_KEYS[#ATTACH_KEYS], true)
expect(listing(dbuf, ATTACH_KEYS) == all, "after :Gitsigns attach: lists %s", listing(dbuf, ATTACH_KEYS))
vim.cmd("silent saveas! " .. vim.fn.fnameescape(NOGIT .. "/out/f.txt"))
wait_until(function() return not attached(dbuf) end, 3000)
wk_wait(dbuf, "n", ATTACH_KEYS[1], false, 3000)
expect(not attached(dbuf) and listing(dbuf, HUNK_KEYS) == "", "after :saveas out of the repo: lists %s", listing(dbuf, HUNK_KEYS))
vim.cmd.cd(FIX)

section("git pickers follow the cwd")
local scratch = vim.api.nvim_create_buf(true, false)
-- in the scratch buffer, where Vim's own keys can edit nothing that matters
local function pickers_here()
  vim.api.nvim_set_current_buf(scratch)
  local out = {}
  for _, lhs in ipairs(keys_of(PICKERS)) do
    local hit = opens(lhs)
    out[#out + 1] = ("%s %s %s"):format(lhs, listed(scratch, lhs) and "listed" or "unlisted", hit or "nothing")
  end
  return out
end
local function want_pickers(on)
  local out = {}
  for _, lhs in ipairs(keys_of(PICKERS)) do
    out[#out + 1] = ("%s %s %s"):format(lhs, on and "listed" or "unlisted", on and ("picker:" .. PICKERS[lhs]) or "nothing")
  end
  return out
end
for _, case in ipairs({ { FIX, true }, { NOGIT, false }, { FIX, true }, { FIX .. "/rs", true } }) do
  vim.cmd.cd(case[1])
  settle()
  local got = pickers_here()
  expect(vim.deep_equal(got, want_pickers(case[2])), "cwd %s: %s", vim.fn.fnamemodify(case[1], ":t"), table.concat(got, ", "))
end
vim.cmd.cd(FIX)

section("log keys follow the buffer's file")
for _, cwd in ipairs({ FIX, NOGIT }) do
  vim.cmd.cd(cwd)
  settle()
  local pbuf = open(NOGIT .. "/plain.txt")
  local mbuf = open(FIX .. "/main.lua")
  for _, lhs in ipairs(keys_of(FILE_LOGS)) do
    expect(listed(mbuf, lhs), "[cwd %s] a repo file lists %s", cwd, lhs)
    local hit = opens(lhs)
    expect(hit == "picker:" .. FILE_LOGS[lhs], "[cwd %s] %s in a repo file opens %s (got %s)", cwd, lhs, FILE_LOGS[lhs], tostring(hit))
    vim.api.nvim_set_current_buf(pbuf)
    expect(not listed(pbuf, lhs), "[cwd %s] a file outside git does not list %s", cwd, lhs)
    hit = opens(lhs)
    expect(hit == nil or not hit:match("^picker:git_log"), "[cwd %s] %s outside git does not open a git log (got %s)", cwd, lhs, tostring(hit))
    vim.api.nvim_set_current_buf(scratch)
    expect(not listed(scratch, lhs), "[cwd %s] an unnamed buffer does not list %s", cwd, lhs)
    vim.api.nvim_set_current_buf(mbuf)
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

section("gitbrowse needs a remote on the buffer's repo")
local function browse(buf)
  local l = listed(buf, BROWSE)
  return l, opens(BROWSE) == "gitbrowse"
end
for name, url in pairs(repos) do
  local buf = open(R .. "/" .. name .. "/file.txt")
  local l, o = browse(buf)
  expect(l == (url ~= "") and o == (url ~= ""), "the %s repo's buffer: gitbrowse listed %s, opens %s", name, tostring(l), tostring(o))
end
local l, o = browse(open(NOGIT .. "/plain.txt"))
expect(not l and not o, "outside git: gitbrowse listed %s, opens %s", tostring(l), tostring(o))
l, o = browse(open(FIX .. "/main.lua"))
expect(not l and not o, "the fixture repo, which has no remote: gitbrowse listed %s, opens %s", tostring(l), tostring(o))

section("a rename out of the repo before the remote check answers")
-- an attach begun before the rename can leave gitsigns on the old path for good, and its callbacks then fail on the untracked file
for i = 1, 3 do
  vim.fn.writefile({ "x" }, R .. "/github/race" .. i .. ".txt")
  vim.cmd.edit(R .. "/github/race" .. i .. ".txt")
  local rbuf = vim.api.nvim_get_current_buf()
  vim.cmd("silent file " .. vim.fn.fnameescape(NOGIT .. "/renamed" .. i .. ".txt"))
  settle()
  l, o = browse(rbuf)
  expect(not l and not o, "[%d] renamed out of the repo at once: gitbrowse listed %s, opens %s", i, tostring(l), tostring(o))
end

section("PR review needs a GitHub remote on the cwd's repo")
-- the plugin's commands, stood in for so a press runs nothing of it
local ran = {}
for _, c in ipairs({ "PRReviewMenu", "PRSuggestChange" }) do
  vim.api.nvim_create_user_command(c, function() ran[#ran + 1] = c end, { range = true, force = true })
end
local function pr_here()
  vim.api.nvim_set_current_buf(scratch)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "some text" })
  local out = {}
  for _, mode in ipairs({ "n", "x" }) do
    ran = {}
    opens(PR, mode)
    out[#out + 1] = ("%s %s %s"):format(mode, listed(scratch, PR, mode) and "listed" or "unlisted", ran[1] or "nothing")
  end
  return table.concat(out, ", ")
end
local ON, OFF = "n listed PRReviewMenu, x listed PRSuggestChange", "n unlisted nothing, x unlisted nothing"
for _, case in ipairs({ { "github", ON }, { "other", OFF }, { "none", OFF }, { "github", ON } }) do
  vim.cmd.cd(R .. "/" .. case[1])
  settle()
  local got = pr_here()
  expect(got == case[2], "cwd %s repo: %s", case[1], got)
end
vim.cmd.cd(NOGIT)
settle()
local got = pr_here()
expect(got == OFF, "cwd outside git: %s", got)
vim.cmd.cd(FIX)

section("every key git brings is judged")
-- the keys the popup gains in a file of a repo with a GitHub remote, cwd there, over a file outside git: each is
-- one of the git keys above
local Util = require("which-key.util")
local known = {}
for _, lhs in ipairs(vim.list_extend(vim.list_extend(vim.list_extend({ BROWSE }, HUNK_KEYS), keys_of(PICKERS)), keys_of(FILE_LOGS))) do
  known["n " .. Util.norm(lhs)] = true
end
known["n " .. Util.norm(PR)], known["x " .. Util.norm(PR)] = true, true
known["n " .. Util.norm("<leader>Gu")] = true
vim.cmd.cd(NOGIT)
settle()
local pbuf = open(NOGIT .. "/plain.txt")
local before = { n = wk_menu(pbuf, "n"), x = wk_menu(pbuf, "x") }
vim.cmd.cd(R .. "/github")
settle()
local gh = open(R .. "/github/file.txt")
wait_until(function() return attach_done(gh) end, 5000)
wk_wait(gh, "n", ATTACH_KEYS[#ATTACH_KEYS], true)
local gained, unknown = {}, {}
for _, mode in ipairs({ "n", "x" }) do
  for lhs, label in pairs(wk_menu(gh, mode)) do
    if before[mode][lhs] == nil then
      gained[#gained + 1] = mode .. " " .. lhs
      if not known[mode .. " " .. lhs] then unknown[#unknown + 1] = mode .. " " .. lhs .. " (" .. tostring(label) .. ")" end
    end
  end
end
table.sort(gained)
table.sort(unknown)
info("gained in a GitHub repo: " .. table.concat(gained, ", "))
expect(#gained > 0, "a repo file brings keys")
expect(#unknown == 0, "every key git brings is judged here; not judged: %s", table.concat(unknown, ", "))
vim.cmd.cd(FIX)
vim.system = real_system
done()
