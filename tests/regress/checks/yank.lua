-- @desc     yanking highlights the yanked text, through a call that is not deprecated on this version
-- @areas    editing ui
-- @budget   20
-- @version-sensitive
vim.cmd.edit("main.lua")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local function hl_marks()
  local n = 0
  for _, ns in pairs(vim.api.nvim_get_namespaces()) do
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, ns, { 0, 0 }, { 0, -1 }, { details = true })) do
      if m[4].hl_group then n = n + 1 end
    end
  end
  return n
end
local before = hl_marks()
feed("yy")
check("yank highlights the yanked line", wait_until(function() return hl_marks() > before end, 1000))
local dep = deprecations()
check("checkhealth vim.deprecated completed", dep ~= "TIMEOUT")
check("no vim.highlight deprecation", not dep:find("vim.highlight", 1, true))
check("no vim.hl.on_yank deprecation", not dep:find("on_yank", 1, true))
