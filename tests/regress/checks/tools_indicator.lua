-- @desc     the statusline shows a wrench with the number of a buffer's missing tools, a "?" for an unanswered project mise config, and nothing when every tool is found and no project config waits for an answer
-- @areas    tools ui
-- @budget   25
-- @needs    lua-language-server stylua
-- The indicator tracks buffers only with a UI, so the UI is stubbed (nvim_list_uis); installs are off, so nothing
-- prompts. Which tools are missing depends on the suite's mise: lua's are there, the Dockerfile's are not.
local tools = require("tools")
vim.g.install_tools = "off"
vim.api.nvim_list_uis = function() return { { width = 120, height = 40 } } end
local wrench = "󰖷"

local function statusline()
  require("lualine").refresh({ place = { "statusline" }, force = true })
  return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win(), maxwidth = 400 }).str
end
--- Opens path and returns the statusline once its tools have resolved, or the last one seen after ms.
local function open(path, lines, want)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  vim.cmd.edit(path)
  local root = tools.root(0)
  local names = tools.for_filetype(vim.bo.filetype, 0).tools
  local results
  tools.resolve_all(names, root, function(r) results = r end)
  wait_until(function() return results ~= nil end, 10000)
  local line = statusline()
  wait_until(function()
    line = statusline()
    return want(line)
  end, 3000)
  return line, results or {}
end

local line, results = open(FIX .. "/dock/Dockerfile", { "FROM scratch" }, function(l) return l:find(wrench, 1, true) ~= nil end)
local missing = vim.tbl_filter(function(r) return not r.path end, vim.tbl_values(results))
if check("the Dockerfile has missing tools in the suite", #missing > 0, vim.inspect(vim.tbl_keys(results))) then
  check(("missing tools: the statusline shows a wrench and the count (%d)"):format(#missing),
    line:find(wrench .. " " .. #missing .. "%f[^%d?]") ~= nil, line)
end

line, results = open(FIX .. "/lua/main.lua", { "return 1" }, function(l) return not l:find(wrench, 1, true) end)
missing = vim.tbl_filter(function(r) return not r.path end, vim.tbl_values(results))
if check("every tool of a lua file is found in the suite", #missing == 0, vim.inspect(missing)) then
  check("nothing missing and no project config: no wrench", not line:find(wrench, 1, true), line)
end

vim.fn.mkdir(FIX .. "/pinned", "p")
vim.fn.writefile({ "[tools]", 'stylua = "latest"' }, FIX .. "/pinned/mise.toml")
line = open(FIX .. "/pinned/main.lua", { "return 1" }, function(l) return l:find(wrench .. " ?", 1, true) ~= nil end)
check("an unanswered project config: a wrench and ?", line:find(wrench .. " ?", 1, true) ~= nil, line)
