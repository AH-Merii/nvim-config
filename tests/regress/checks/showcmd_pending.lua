-- @desc     the statusline's pending keys leave out a lone key whose command runs at once (w, ^D, j) and keep counts, prefixes, operators, registers and Visual mode's selection size
-- @areas    ui
-- @budget   10
-- Headless no UI is attached, so ui2 and the hook are off; this checks the rule the hook applies.
local visible = require("config.ui2.showcmd").visible
local cases = {
  { "w", "" }, { "j", "" }, { "^D", "" }, { "^U", "" }, { "p", "" }, { "x", "" },
  { "5", "5" }, { "d", "d" }, { "c", "c" }, { "y", "y" }, { ">", ">" }, { '"', '"' }, { "f", "f" }, { "r", "r" },
  { "z", "z" }, { "Z", "Z" }, { "^W", "^W" }, { "q", "q" }, { "m", "m" }, { "@", "@" },
  { "5d", "5d" }, { '"ay', '"ay' }, { "d2", "d2" }, { "12", "12" }, { "3x5", "3x5" },
}
local wrong = {}
for _, case in ipairs(cases) do
  local got = visible(case[1])
  if got ~= case[2] then
    wrong[#wrong + 1] = ("%q -> %q, want %q"):format(case[1], got, case[2])
  end
end
check("each case shows what it should", #wrong == 0, table.concat(wrong, "; "))
