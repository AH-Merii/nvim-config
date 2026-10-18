-- @desc     startup records its phases once each, in order (options, registries, tools, plugins, servers), each timed; the deferred phase waits for VeryLazy, then is recorded once, last
-- @areas    startup
-- @budget   20
-- The order is the contract (lua/app/init.lua): mapleader before any <leader> row, the registries before the tool
-- resolver that reads them, the resolver before the plugins that look tools up, nvim-lspconfig on the runtimepath
-- before the servers, and the plugins that load at VeryLazy before the features' callbacks.
local STARTUP = { "options", "registries", "tools", "plugins", "servers" }
local ALL = vim.list_extend(vim.deepcopy(STARTUP), { "deferred" })

local function names(times) return vim.tbl_map(function(t) return t.name end, times) end

-- The harness has fired VeryLazy by now
local times = require("app").times()
check("each phase is recorded once, in order", vim.deep_equal(names(times), ALL), table.concat(names(times), ","))
local untimed = vim.tbl_filter(function(t) return not (type(t.ms) == "number" and t.ms > 0) end, times)
check("each phase has its time", #times > 0 and #untimed == 0, vim.inspect(untimed))

vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
local again = names(require("app").times())
check("VeryLazy fired again records no phase again", vim.deep_equal(again, ALL), table.concat(again, ","))

-- A headless nvim with no harness never gets VeryLazy (lazy fires it once a UI enters): only the startup phases run
local out = vim.fn.tempname()
local child = vim.system({
  vim.env.NV,
  vim.env.V,
  "--headless",
  "-c",
  ("lua vim.fn.writefile(vim.tbl_map(function(t) return t.name end, require('app').times()), %q)"):format(out),
  "-c",
  "qa!",
}, { stdin = false }):wait(15000)
local before = vim.fn.filereadable(out) == 1 and vim.fn.readfile(out) or {}
os.remove(out)
check(
  "before VeryLazy, only the startup phases are recorded: the deferred one waits",
  vim.deep_equal(before, STARTUP),
  ("exit %s: %s"):format(tostring(child.code), table.concat(before, ","))
)
