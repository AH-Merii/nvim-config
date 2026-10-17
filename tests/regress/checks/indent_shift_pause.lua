-- @desc     < and > in visual mode shift the lines with the indent scope animation paused, and it resumes afterwards
-- @areas    ui keys
-- @budget   15
vim.fn.writefile({ "local t = {", "    a = 1,", "    b = 2,", "}" }, "shift.lua")
vim.cmd.edit("shift.lua")
local buf = vim.api.nvim_get_current_buf()
local function animates() return Snacks.animate.enabled({ buf = buf, name = "indent" }) end

for _, case in ipairs({ { key = ">", sign = 1 }, { key = "<", sign = -1 } }) do
  -- the animation is on before the key: a key pressed on its own animates (snacks.lua's on_key policy)
  vim.b[buf].snacks_animate_indent = nil
  check(case.key .. ": the indent animation is on before the key", animates() == true)
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local before = vim.fn.indent(2)
  feed("V" .. case.key)
  local paused = animates() == false
  local moved = vim.fn.indent(2) - before
  feed("<Esc>")
  check(case.key .. ": shifts the selected line", moved * case.sign > 0, ("indent %d -> %d"):format(before, before + moved))
  check(case.key .. ": the indent animation is paused right after the shift", paused)
  check(case.key .. ": and resumes afterwards", wait_until(function() return animates() == true end, 1000))
end
