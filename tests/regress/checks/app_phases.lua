-- @desc     startup records its phases once each, in order (options, registries, tools, plugins, servers), each timed; the deferred phase waits for VeryLazy and the buffer phase for the first file, each then recorded once
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

-- The buffer phase waits for the first file read or created, then is recorded once
vim.cmd.edit("main.lua")
vim.cmd.edit("not-yet-a-file.lua")
local edited = names(require("app").times())
local WITH_BUFFER = vim.list_extend(vim.deepcopy(ALL), { "buffer" })
check("the first file read records the buffer phase once, after the others", vim.deep_equal(edited, WITH_BUFFER),
  table.concat(edited, ","))

-- A headless nvim with no harness never gets VeryLazy (lua/app/init.lua fires it once a UI enters): only the startup
-- phases run, and the buffer phase too when a file is given at launch
local function child_phases(...)
  local out = vim.fn.tempname()
  local child = vim.system({
    vim.env.NV,
    vim.env.V,
    "--headless",
    "-c",
    ("lua vim.fn.writefile(vim.tbl_map(function(t) return t.name end, require('app').times()), %q)"):format(out),
    "-c",
    "qa!",
    ...,
  }, { stdin = false }):wait(15000)
  local got = vim.fn.filereadable(out) == 1 and vim.fn.readfile(out) or {}
  os.remove(out)
  return got, ("exit %s: %s"):format(tostring(child.code), table.concat(got, ","))
end
local before, why = child_phases()
check("before VeryLazy, only the startup phases are recorded: the deferred one waits", vim.deep_equal(before, STARTUP), why)
local with_file
with_file, why = child_phases("main.lua")
check("a file given at launch records the buffer phase after the startup ones",
  vim.deep_equal(with_file, vim.list_extend(vim.deepcopy(STARTUP), { "buffer" })), why)
