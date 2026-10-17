-- @desc     every key row with an action has its global map, and the map's desc is the row's label, so :map and the keymaps picker (<leader>sk) describe it, gated or not
-- @areas    keys which-key
-- @budget   20
-- @args     main.lua
-- language rows are buffer maps placed on FileType; keys_test covers them
local rows = vim.tbl_filter(function(row) return row.action ~= nil and row.ft == nil end, require("keys").list())
if not check("the config has global key rows", #rows > 20, #rows .. " rows") then return end

-- a slot's map carries the first acting row's label; later rows on the same mode and lhs are its alternatives
local first, bad, gated = {}, {}, 0
for _, row in ipairs(rows) do
  local id = row.mode .. vim.keycode(row.lhs)
  if not first[id] then
    first[id] = true
    local map = vim.fn.maparg(row.lhs, row.mode, false, true)
    if map.expr == 1 then gated = gated + 1 end
    if map.lhs == nil or map.buffer == 1 or map.desc ~= row.label then
      bad[#bad + 1] = ("%s %s: want %q, map %s"):format(row.mode, row.lhs, tostring(row.label), map.lhs and ("desc " .. tostring(map.desc)) or "missing")
    end
  end
end
check("gated rows are among them", gated > 0, gated .. " expr maps")
check("each row's map has the row's label as desc", #bad == 0, #bad > 0 and table.concat(bad, "; ") or (vim.tbl_count(first) .. " maps"))
