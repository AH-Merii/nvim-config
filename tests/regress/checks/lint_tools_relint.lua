-- @desc     a linter missing when a file opens is skipped without an error; once it appears and ToolsChanged says so, each loaded buffer of that root lints again with it, once
-- @areas    lint tools
-- @budget   25
-- A stand-in yamllint in the project's .venv/bin (a project-env path in the catalog) logs each run.
local tools = require("tools")
local root = FIX .. "/relint"
local log = root .. "/runs.log"
vim.fn.mkdir(root .. "/.venv/bin", "p")
local bufs = {}
for _, name in ipairs({ "a.yaml", "b.yaml" }) do
  vim.fn.writefile({ "name: " .. name }, root .. "/" .. name)
  vim.cmd.edit(root .. "/" .. name)
  bufs[name] = vim.api.nvim_get_current_buf()
end
local function runs()
  local ok, lines = pcall(vim.fn.readfile, log)
  local n = {}
  for _, l in ipairs(ok and lines or {}) do
    for name in pairs(bufs) do
      if l:find(name, 1, true) then n[name] = (n[name] or 0) + 1 end
    end
  end
  return n
end

local before = tools.wait("yamllint", root, 10000)
if not check("yamllint is missing in the project before the stand-in appears", before ~= nil and before.path == nil,
  before and ("%s %s"):format(before.source, tostring(before.path)) or "no answer within 10s") then return end
-- the open buffers' lint runs (BufEnter, BufReadPost) found no yamllint
vim.wait(1000)
check("the missing linter did not run", next(runs()) == nil, vim.inspect(runs()))

-- the stand-in reads the buffer from stdin like the real one and logs its first line, which names the file
local bin = root .. "/.venv/bin/yamllint"
vim.fn.writefile({
  "#!/bin/sh",
  'content=$(cat)',
  'printf "%s\\n" "$content" | head -n 1 >> ' .. vim.fn.shellescape(log),
}, bin)
vim.fn.setfperm(bin, "rwxr-xr-x")
local changed
vim.api.nvim_create_autocmd("User", {
  pattern = tools.event,
  callback = function(ev) if ev.data.root == root then changed = ev.data end end,
})
tools.refresh(root, "installed")
check("ToolsChanged names yamllint for the root", wait_until(function() return changed ~= nil end, 5000)
  and vim.list_contains(changed.tools, "yamllint"), vim.inspect(changed))

local relinted = wait_until(function()
  local n = runs()
  return (n["a.yaml"] or 0) > 0 and (n["b.yaml"] or 0) > 0
end, 5000)
check("every loaded buffer of the root lints again with the new linter", relinted, vim.inspect(runs()))
local extra = wait_until(function()
  local n = runs()
  return (n["a.yaml"] or 0) > 1 or (n["b.yaml"] or 0) > 1
end, 2000)
check("one ToolsChanged relints each buffer once", not extra, vim.inspect(runs()))
