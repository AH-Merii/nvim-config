-- @desc     the FastAPI routes key is listed by which-key, and opens neoblocks' route picker when pressed, only while the cwd's Python project depends on FastAPI, and follows a :cd
-- @areas    keys which-key
-- @budget   20
-- Judged by pressing the key and reading which-key's popup, never by which maps exist. Snacks' picker is stood in
-- for, so nothing opens; neoblocks' fastapi module reads the project's routes with the suite's Python parser.

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
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end

local KEY = "<leader>sF"
local ROOT = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
-- a FastAPI project: its pyproject.toml names the dependency, main.py has a route
local API = ROOT .. "/fastapi-project"
vim.fn.mkdir(API, "p")
vim.fn.writefile({ "[project]", 'name = "api"', 'dependencies = ["fastapi[standard]"]' }, API .. "/pyproject.toml")
vim.fn.writefile({ "from fastapi import FastAPI", "app = FastAPI()", '@app.get("/items")', "def items(): ..." }, API .. "/main.py")
-- a Python project without FastAPI
local PLAIN = ROOT .. "/plain-project"
vim.fn.mkdir(PLAIN, "p")
vim.fn.writefile({ "[project]", 'name = "plain"', 'dependencies = ["requests"]' }, PLAIN .. "/pyproject.toml")

-- what pressing the key in the scratch buffer opens: the Snacks picker it calls, nil for none. Typed under :silent!,
-- so where the key isn't mapped Vim's own keys run, and what they edit is put back.
local scratch = vim.api.nvim_create_buf(true, false)
local function opens()
  vim.api.nvim_set_current_buf(scratch)
  local hit
  local picker = Snacks.picker
  Snacks.picker = setmetatable({}, { __index = function(_, k) return function() hit = "picker:" .. k end end })
  pcall(vim.cmd, ("silent! call nvim_feedkeys(%s, 'mx', v:false)"):format(vim.fn.string(vim.keycode(KEY))))
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  flush()
  Snacks.picker = picker
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, {})
  vim.bo[scratch].modified = false
  return hit
end

section("the FastAPI routes key follows the cwd")
for _, case in ipairs({ { API, true }, { PLAIN, false }, { API, true }, { ROOT, false } }) do
  vim.cmd.cd(case[1])
  flush()
  local listed = wk_lists(scratch, "n", KEY) ~= nil
  local hit = opens()
  local got = ("%s %s"):format(listed and "listed" or "unlisted", hit or "nothing")
  local want = case[2] and "listed picker:pick" or "unlisted nothing"
  expect(got == want, "cwd %s: %s, want %s", vim.fn.fnamemodify(case[1], ":t"), got, want)
end
vim.cmd.cd(FIX)

done()
