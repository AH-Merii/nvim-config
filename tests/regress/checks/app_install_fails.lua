-- @desc     a plugin that fails to install (gitsigns, from an unreachable source) or a phase that raises (options) stops nothing else: every phase runs, the other plugins load, the servers are enabled, both failures are reported, and the committed lockfile keeps the plugin's pin
-- @areas    startup installer lsp
-- @budget   60
-- A child nvim on its own home and data dir: the suite's plugins and parsers less gitsigns.nvim, and a config whose
-- lockfile and gitsigns spec point at a source that does not exist, so vim.pack's install fails offline
-- (lua/app/plugins.lua).
local NAME = "gitsigns.nvim"
-- under the check's fixture, on disk: the seed is ~100 MB, too much for a tmpfs /tmp
local root = vim.env.FIX .. "/.nvr-install-fails"
local home, data = root .. "/home", root .. "/data"
local cfg = home .. "/config/nvim"
vim.fn.mkdir(home .. "/config", "p")
vim.fn.mkdir(home .. "/state", "p")
vim.fn.mkdir(home .. "/cache", "p")
vim.fn.mkdir(data .. "/nvim", "p")
local function cp(from, to) return vim.system({ "cp", "-a", "--reflink=auto", from, to }):wait().code == 0 end
local seeded = cp(vim.fn.stdpath("config"), cfg) and cp(vim.fn.stdpath("data") .. "/site", data .. "/nvim/site")
vim.fn.delete(data .. "/nvim/site/pack/core/opt/" .. NAME, "rf")

local lockfile = cfg .. "/nvim-pack-lock.json"
local lock = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
local pin = (lock.plugins[NAME] or {}).rev
if not check("precondition: the lockfile pins " .. NAME .. " and the seed copied", seeded and pin ~= nil) then return end
-- both sources vim.pack installs from: the lockfile's, then the spec's
local nowhere = "file://" .. root .. "/nowhere/" .. NAME
lock.plugins[NAME].src = nowhere
vim.fn.writefile(vim.split(vim.json.encode(lock, { indent = "  ", sort_keys = true }), "\n"), lockfile)
local spec_file = cfg .. "/lua/features/git.lua"
local src = table.concat(vim.fn.readfile(spec_file), "\n")
local moved, n = src:gsub('"lewis6991/gitsigns%.nvim"', ('"%s"'):format(nowhere))
if not check("precondition: the gitsigns spec's source was replaced", n == 1) then return end
vim.fn.writefile(vim.split(moved, "\n"), spec_file)
-- and the options phase raises, after setting every option (lua/options.lua is the phase's first step)
vim.fn.writefile({ 'error("nvr: injected options failure")' }, cfg .. "/lua/options.lua", "a")

local out, probe = root .. "/out.json", root .. "/probe.lua"
vim.fn.writefile({
  "vim.g.did_very_lazy = true",
  "vim.api.nvim_exec_autocmds('User', { pattern = 'VeryLazy', modeline = false })",
  "vim.wait(100)",
  "local ok, plugins = pcall(function() return require('app.plugins').list() end)",
  "vim.fn.writefile({ vim.json.encode({",
  "  phases = vim.tbl_map(function(t) return t.name end, require('app').times()),",
  "  plugins = ok and plugins or {},",
  "  servers = vim.tbl_count(vim.lsp._enabled_configs or {}),",
  "  messages = vim.api.nvim_exec2('messages', { output = true }).output,",
  "}) }, vim.env.NVR_OUT)",
}, probe)
local child = vim.system({ vim.env.NV, vim.env.V, "--headless", "-c", "luafile " .. probe, "-c", "qa!", "main.lua" }, {
  stdin = false,
  env = { NVR_HOME = home, NVR_STATE = home .. "/state", NVR_DATA = data, NVR_OUT = out },
}):wait(40000)
local got = vim.fn.filereadable(out) == 1 and vim.json.decode(table.concat(vim.fn.readfile(out), "\n")) or nil
if not check("the child started and reported", got ~= nil, ("exit %s: %s"):format(tostring(child.code), child.stderr or "")) then
  vim.fn.delete(root, "rf")
  return
end

local ALL = { "options", "registries", "tools", "plugins", "servers", "buffer", "deferred" }
check("every phase runs", vim.deep_equal(got.phases, ALL), table.concat(got.phases, ","))
local unloaded = {}
for _, p in ipairs(got.plugins) do
  if p.name ~= NAME and p.phase ~= "on_demand" and not p.loaded then table.insert(unloaded, p.name) end
end
check("every other plugin loads", #got.plugins > 1 and #unloaded == 0, #got.plugins .. " listed; not loaded: " .. table.concat(unloaded, ","))
local failed = vim.iter(got.plugins):find(function(p) return p.name == NAME end)
check(NAME .. " is reported not loaded", failed ~= nil and failed.loaded == false, vim.inspect(failed))
check("the servers are enabled", got.servers > 0, got.servers .. " enabled")
check("the failure is reported, naming the plugin", got.messages:find(NAME, 1, true) ~= nil, got.messages)
check("the options phase's error is reported", got.messages:find("options phase failed", 1, true) ~= nil
  and got.messages:find("nvr: injected options failure", 1, true) ~= nil, got.messages)
local after = vim.json.decode(table.concat(vim.fn.readfile(lockfile), "\n"))
check("the lockfile keeps " .. NAME .. "'s pin", (after.plugins[NAME] or {}).rev == pin, vim.inspect(after.plugins[NAME]))
vim.fn.delete(root, "rf")
