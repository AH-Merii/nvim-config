-- @desc     after lazy runs the spec modules again (as after :Lazy install, update or sync), every key need that held in a buffer holds again there and in a buffer opened afterwards, and a gated git key (<leader>gf) still opens its picker
-- @areas    keys git
-- @budget   40
-- @args     main.lua
local buf = vim.api.nvim_get_current_buf()
wait_attach(buf, (lsp_expected(buf)), 15000)
wait_until(function() return vim.b[buf].gitsigns_status_dict ~= nil end, 5000)

local keys = require("keys")
-- every need a row names
local needs = {}
for _, row in ipairs(keys.list()) do
  for _, need in ipairs(row.need or {}) do
    needs[need] = true
  end
end
needs = vim.tbl_keys(needs)
table.sort(needs)
local function holding(b)
  return vim.tbl_filter(function(need) return keys.holds(need, b) end, needs)
end
-- remote and repo lookups are asynchronous
local before
wait_until(function()
  before = holding(buf)
  return vim.list_contains(before, "git file")
end, 5000)
if not check("main.lua holds the git needs before", vim.list_contains(before, "git file"), table.concat(before, ", ")) then return end

-- what lazy does after an install or update: unload each spec module and run it again (lazy/manage/init.lua:92)
require("lazy.core.plugin").load()

local function same(b)
  local now
  local ok = wait_until(function()
    now = holding(b)
    return vim.deep_equal(now, before)
  end, 5000)
  local lost = vim.tbl_filter(function(need) return not vim.list_contains(now, need) end, before)
  local gained = vim.tbl_filter(function(need) return not vim.list_contains(before, need) end, now)
  return ok, ("%d held; lost: %s; gained: %s"):format(#before, table.concat(lost, ", "), table.concat(gained, ", "))
end
check("the open buffer holds the same needs after the specs run again", same(buf))
vim.cmd("bwipeout! " .. buf)
vim.cmd.edit("main.lua")
local again = vim.api.nvim_get_current_buf()
wait_attach(again, (lsp_expected(again)), 15000)
wait_until(function() return vim.b[again].gitsigns_status_dict ~= nil end, 5000)
check("a buffer opened afterwards holds the same needs", same(again))

local hit
local real = Snacks.picker
Snacks.picker = setmetatable({}, {
  __index = function(_, k) return function() hit = k end end,
  __call = function(_, source) hit = tostring(source) end,
})
feed("<leader>gf")
Snacks.picker = real
check("<leader>gf opens the file's git log", hit == "git_log_file", "picker: " .. tostring(hit))
