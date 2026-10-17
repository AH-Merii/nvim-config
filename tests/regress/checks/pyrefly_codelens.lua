-- @desc     pyrefly's Run and Test lenses are drawn, and grx runs them with the project's Python: the file, pytest or unittest on the test, or a warning instead of a terminal when that Python lacks pytest
-- @areas    lsp keys
-- @budget   45
-- @needs    pyrefly
-- The project's Python is a fake in .venv/bin that records how it was run and fakes pytest's presence by a marker
-- file; anything else (pyrefly asking it about the environment) goes to the system python3.
local root = vim.fs.joinpath(FIX, "lensproj")
local bin = vim.fs.joinpath(root, ".venv", "bin")
vim.fn.mkdir(bin, "p")
local calls, has_pytest = vim.fs.joinpath(root, "calls.txt"), vim.fs.joinpath(root, "has-pytest")
local fake = vim.fs.joinpath(bin, "python")
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = -c ]; then',
  '  [ "$2" = "import pytest" ] && { [ -e "' .. has_pytest .. '" ]; exit $?; }',
  '  exec python3 "$@"',
  "fi",
  'echo "$*" >> "' .. calls .. '"',
}, fake)
vim.uv.fs_chmod(fake, 493)
vim.fn.writefile({ "[project]", 'name = "lensproj"' }, vim.fs.joinpath(root, "pyproject.toml"))
local file = vim.fs.joinpath(root, "t.py")
vim.fn.writefile({
  "import unittest",
  "",
  "",
  "def test_plain():",
  "    assert True",
  "",
  "",
  "class TestCase1(unittest.TestCase):",
  "    def test_method(self):",
  "        pass",
  "",
  "",
  'if __name__ == "__main__":',
  "    unittest.main()",
}, file)

vim.cmd.edit(file)
local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local missing = wait_attach(buf, { "pyrefly" }, 20000)
if not check("pyrefly attaches", #missing == 0, table.concat(missing, " ")) then
  return
end

--- The lens titles drawn in buf, as "<row (1-based)> <text>", sorted
local function lenses()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    if m[4].virt_lines_above then
      out[#out + 1] = ("%d %s"):format(m[2] + 1, vim.trim(vim.iter(m[4].virt_lines[1]):map(function(c) return c[1] end):join("")))
    end
  end
  table.sort(out)
  return out
end
wait_until(function()
  vim.cmd.redraw()
  return #lenses() >= 4
end, 15000)
check("the Run and Test lenses are drawn", vim.deep_equal(lenses(), { "13 Run", "4 Test", "8 Test", "9 Test" }), vim.inspect(lenses()))

local notes = {}
local notify = vim.notify
vim.notify = function(msg, level, opts)
  notes[#notes + 1] = { msg = msg, level = level }
  return notify(msg, level, opts)
end
local function ran() return vim.uv.fs_stat(calls) and vim.fn.readfile(calls) or {} end
local function terminals()
  return #vim.tbl_filter(function(b) return vim.bo[b].buftype == "terminal" end, vim.api.nvim_list_bufs())
end
--- Runs the lens on row with grx from the source window, waits for the fake Python to record one more run
local function grx(row)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_cursor(win, { row, 0 })
  local before = #ran()
  feed("grx")
  wait_until(function() return #ran() > before end, 5000)
  return ran()[before + 1]
end

-- without pytest: a warning that names the Python and how to get pytest, and nothing runs
vim.api.nvim_set_current_win(win)
vim.api.nvim_win_set_cursor(win, { 4, 0 })
feed("grx")
local warned = wait_until(function()
  return vim.iter(notes):any(function(n) return n.level == vim.log.levels.WARN and n.msg:find(fake, 1, true) and n.msg:find("pytest", 1, true) end)
end, 5000)
check("a test lens warns, naming the Python, when it lacks pytest", warned, vim.inspect(notes))
check("and runs nothing", #ran() == 0 and terminals() == 0, vim.inspect(ran()) .. " terminals: " .. terminals())

vim.fn.writefile({}, has_pytest)
local want = { [4] = "-m pytest " .. file .. "::test_plain", [9] = "-m unittest t.TestCase1.test_method", [13] = file }
for _, row in ipairs({ 4, 9, 13 }) do
  local got = grx(row)
  check(("the lens on line %d runs %s"):format(row, want[row]), got == want[row], tostring(got))
end
