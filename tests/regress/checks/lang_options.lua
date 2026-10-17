-- @desc     each filetype whose language sets buffer options has them after every ftplugin ran, a runtime ftplugin that sets the same options included
-- @areas    editing tools
-- @budget   10
local lang = require("lang")
-- An ftplugin on the runtimepath that sets each option to something else, as Neovim's own ftplugins may
local rtp = FIX .. "/.nvr-ftplugin"
local fts = vim.tbl_filter(function(ft) return lang.of(ft).options ~= nil end, lang.filetypes())
check("some language sets buffer options", #fts > 0)
local function other(v)
  if type(v) == "boolean" then return not v end
  if type(v) == "number" then return v + 1 end
  return tostring(v) .. "x"
end
for _, ft in ipairs(fts) do
  local base = ft:match("^[^.]+")
  local lines = {}
  for name, value in pairs(lang.of(ft).options) do
    lines[#lines + 1] = ("vim.bo.%s = %s"):format(name, vim.inspect(other(value)))
  end
  vim.fn.mkdir(rtp .. "/ftplugin", "p")
  vim.fn.writefile(lines, ("%s/ftplugin/%s.lua"):format(rtp, base))
end
vim.opt.runtimepath:append(rtp)
for _, ft in ipairs(fts) do
  vim.cmd.enew()
  vim.bo.filetype = ft
  local got = {}
  for name in pairs(lang.of(ft).options) do
    got[name] = vim.bo[name]
  end
  check(ft .. " has its language's options", vim.deep_equal(got, lang.of(ft).options), vim.inspect({ got = got, want = lang.of(ft).options }))
end
