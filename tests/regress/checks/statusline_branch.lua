-- @desc     the statusline shows the git branch of the file's checkout, in a main worktree (a .git dir) and in a linked worktree beside it (a .git file), and none outside a repo
-- @areas    ui git
-- @budget   15
-- @fixture  tobj
-- tobj is no git repo, so nothing above the linked worktree holds a .git dir, as for a worktree next to its main checkout
local function git(cwd, ...)
  local r = vim.system({ "git", "-c", "user.name=check", "-c", "user.email=check@example.invalid", ... }, { cwd = cwd, text = true }):wait()
  return r.code == 0, vim.trim(r.stdout .. r.stderr)
end
local repo = FIX .. "/repo"
vim.fn.mkdir(repo, "p")
vim.fn.writefile({ "return 1" }, repo .. "/main.lua")
local steps = {
  { "init", "-q", "-b", "in-repo-check" },
  { "add", "main.lua" },
  { "commit", "-q", "-m", "first" },
  { "worktree", "add", "-q", "-b", "in-linked-check", "../linked" },
}
for _, args in ipairs(steps) do
  local ok, out = git(repo, unpack(args))
  if not check("set up: git " .. args[1], ok, out) then return end
end
check("set up: the linked worktree's .git is a file", vim.fn.filereadable(FIX .. "/linked/.git") == 1)

local function statusline()
  require("lualine").refresh({ place = { "statusline" }, force = true })
  return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win(), maxwidth = 400 }).str
end
local function shows(branch) return statusline():find(branch, 1, true) ~= nil end
for _, case in ipairs({
  { where = "a main worktree", file = "repo/main.lua", branch = "in-repo-check" },
  { where = "a linked worktree", file = "linked/main.lua", branch = "in-linked-check" },
}) do
  vim.cmd.edit(case.file)
  check(("a file in %s shows its branch %s"):format(case.where, case.branch), wait_until(function() return shows(case.branch) end, 2000), statusline())
end
vim.cmd.edit("t.sh")
-- lualine finds the branch on BufEnter; give a stale one the same time to go
wait_until(function() return not shows("-check") end, 500)
check("a file outside any repo shows no branch", not shows("-check"), statusline())
