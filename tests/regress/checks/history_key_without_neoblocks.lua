-- @desc     <leader>n in a session without neoblocks.nvim (it failed to install or load) says so, rather than raising
-- @areas    ui keys
-- @budget   15
-- The config loads neoblocks; this hides it as a failed install leaves it: require("neoblocks") fails and the Neoblocks
-- global is unset.
for name in pairs(package.loaded) do
  if name == "neoblocks" or name:find("^neoblocks%.") then
    package.loaded[name] = nil
  end
end
_G.Neoblocks = nil
package.preload["neoblocks"] = function() error("module 'neoblocks' not found") end

local seen = {} ---@type { msg: string, level: integer? }[]
local notify = vim.notify
vim.notify = function(msg, level) seen[#seen + 1] = { msg = tostring(msg), level = level } end
vim.v.errmsg = ""
feed("<Space>n")
vim.notify = notify

check("<leader>n raises no error", vim.v.errmsg == "", vim.v.errmsg)
local said = vim.iter(seen):find(function(n) return n.msg:find("neoblocks.nvim", 1, true) ~= nil end)
check("<leader>n says neoblocks.nvim isn't loaded", said ~= nil and said.level == vim.log.levels.WARN, vim.inspect(seen))
