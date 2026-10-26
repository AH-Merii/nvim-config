-- The plugin manager adapter: vim.pack (:h vim.pack) installs every module's plugins (features.plugins()) at the
-- revisions nvim-pack-lock.json pins, and this module loads each in its phase (lua/app/init.lua):
--
--   startup   in the plugins phase, before the first file opens
--   buffer    when the first file is read or created (BufReadPre, BufNewFile)
--   deferred  after the first screen, at VeryLazy (the default)
--   on_demand at the first of its `cmd`, for a plugin whose setup changes what loading it at VeryLazy would; or
--             when a module of it is first required, for one only some event needs (features/hover.lua)
--
-- A plugin in a later phase that is required earlier (a picker action that requires trouble, blink's lazydev
-- source) loads then, from a package loader below. Update plugins with :packupdate (:h :packupdate).
local M = {}

---@class app.Plugin
---@field src string "owner/repo" on GitHub, or any URL git clones
---@field name? string the plugin's directory; default the src's last part
---@field version? string|vim.VersionRange a branch, tag or commit, or the greatest tag in a range (:h vim.pack.Spec)
---@field phase? "startup"|"buffer"|"deferred"|"on_demand" default "deferred"
---@field cmd? string[] commands that load it if used before its phase (an on_demand plugin's only way in): each is
---   defined until the plugin loads, then runs as the plugin's own
---@field init? fun() runs in the plugins phase, before any plugin loads
---@field setup? fun() runs once the plugin is on the runtimepath
---@field build? fun(path: string) runs after vim.pack installs or updates it, once it is loaded
---@field dev? boolean with $NVIM_PLUGIN_DEV set to a directory holding a checkout of it, that checkout is loaded
---   instead (vim.pack copies a local source rather than linking it)

local list = {} ---@type app.Plugin[] in the order given, which is the order each phase loads them
local by_name = {} ---@type table<string, app.Plugin>
local loaded = {} ---@type table<string, true>
local builds = {} ---@type table<string, true> plugins whose build waits for them to load

---@param p app.Plugin
local function name_of(p) return p.name or (p.src:match("[^/]+$"):gsub("%.git$", "")) end

---@param name string
local function path_of(name) return vim.fs.joinpath(vim.fn.stdpath("data"), "site", "pack", "core", "opt", name) end

---@param name string
local function dev_dir(name)
  local dir = by_name[name].dev and vim.env.NVIM_PLUGIN_DEV
  dir = dir and vim.fs.joinpath(vim.fs.normalize(dir), name)
  return dir and vim.uv.fs_stat(dir) and dir or nil
end

---@param name string
---@param what string
---@param fn fun()
local function try(name, what, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    require("app").report(("%s: %s failed:\n%s"):format(name, what, err), "app.plugins")
  end
end

--- Puts plugin name on the runtimepath and runs its setup, once. During init.lua its plugin/ files are left to
--- Neovim's load-plugins step, which follows init.lua (:h load-plugins): :packadd would source them now and that step
--- again. Later, :packadd sources them before setup runs.
---@param name string
function M.load(name)
  local p = by_name[name]
  local dev = p and dev_dir(name)
  -- not on disk: its install failed, and setup() reported it
  if not p or loaded[name] or not (dev or vim.uv.fs_stat(path_of(name))) then
    return
  end
  loaded[name] = true
  if dev then
    vim.opt.rtp:prepend(dev)
    if vim.v.vim_did_init == 1 then
      for _, file in ipairs(vim.fn.glob(dev .. "/plugin/**/*.{vim,lua}", false, true)) do
        vim.cmd.source({ file, magic = { file = false } })
      end
    end
  else
    vim.cmd.packadd({ vim.fn.fnameescape(name), bang = vim.v.vim_did_init == 0, magic = { file = false } })
  end
  if p.setup then
    try(name, "setup", p.setup)
  end
  if builds[name] then
    builds[name] = nil
    try(name, "build", function() p.build(path_of(name)) end)
  end
end

--- Loads every plugin of phase, in order.
---@param phase "startup"|"buffer"|"deferred"
function M.load_phase(phase)
  for _, p in ipairs(list) do
    if (p.phase or "deferred") == phase then
      M.load(name_of(p))
    end
  end
end

--- The plugins given to setup(), and whether each is loaded, in order.
---@return { name: string, phase: string, loaded: boolean, path: string }[]
function M.list()
  return vim.tbl_map(function(p)
    local name = name_of(p)
    return { name = name, phase = p.phase or "deferred", loaded = loaded[name] == true, path = dev_dir(name) or path_of(name) }
  end, list)
end

--- Defines cmd until plugin name loads: the first use loads it, then runs the plugin's own cmd with the same range,
--- bang, arguments and modifiers.
---@param name string
---@param cmd string
function M.command(name, cmd)
  vim.api.nvim_create_user_command(cmd, function(ev)
    pcall(vim.api.nvim_del_user_command, cmd)
    M.load(name)
    if vim.fn.exists(":" .. cmd) ~= 2 then
      return vim.notify(("%s: loaded, but defines no :%s"):format(name, cmd), vim.log.levels.ERROR, { title = "app.plugins" })
    end
    vim.cmd({
      cmd = cmd,
      args = ev.fargs,
      bang = ev.bang,
      range = ev.range == 1 and { ev.line1 } or ev.range == 2 and { ev.line1, ev.line2 } or nil,
      mods = ev.smods,
    })
  end, { nargs = "*", range = true, bang = true, desc = ("Loads %s, then runs its :%s"):format(name, cmd) })
end

-- A module of a plugin not loaded yet loads that plugin, as when lazy.nvim loaded a plugin on require. Last in
-- package.loaders, so only a module no other loader finds gets here.
---@param modname string
local function loader(modname)
  local top = modname:match("^[^.]+")
  for _, p in ipairs(list) do
    local name = name_of(p)
    local lua = (dev_dir(name) or path_of(name)) .. "/lua/"
    if not loaded[name] and (vim.uv.fs_stat(lua .. top .. ".lua") or vim.uv.fs_stat(lua .. top)) then
      M.load(name)
      if package.loaded[modname] ~= nil then
        local mod = package.loaded[modname]
        return function() return mod end
      end
      local found = vim.loader.find(modname)[1]
      return found and assert(loadfile(found.modpath)) or ("\n\tapp.plugins: %s loaded, but has no module %s"):format(name, modname)
    end
  end
end

--- vim.pack drops a plugin that failed to install from the lockfile, and writes it before raising
--- (runtime/lua/vim/pack.lua:899-902, 1211-1213). Puts back each pin the file had before, so the committed lockfile
--- still names the plugin and the next start installs it at its revision.
---@param lockfile string
---@param pinned? string the file's text before vim.pack.add
local function restore_pins(lockfile, pinned)
  local ok, before = pcall(vim.json.decode, pinned or "")
  local fd = io.open(lockfile, "r")
  local ok_now, now = pcall(vim.json.decode, fd and fd:read("*a") or "")
  if fd then
    fd:close()
  end
  if not (ok and ok_now and type(before.plugins) == "table" and type(now.plugins) == "table") then
    return
  end
  local restored = false
  for name, pin in pairs(before.plugins) do
    if now.plugins[name] == nil then
      now.plugins[name], restored = pin, true
    end
  end
  if restored then
    local out = assert(io.open(lockfile, "w"))
    out:write(vim.json.encode(now, { indent = "  ", sort_keys = true }), "\n")
    out:close()
  end
end

--- Installs what is missing, runs every init, and loads the startup plugins. Called once, by the plugins phase.
---@param plugins app.Plugin[]
function M.setup(plugins)
  -- The runtimepath and packpath lazy.nvim set (lazy/core/config.lua:295-313): the config, vim.pack's site dir and
  -- Neovim's own, without the system's site dirs from $XDG_DATA_DIRS (/usr/share/nvim/site and their after/)
  local lib = vim.fn.fnamemodify(vim.v.progpath, ":p:h:h") .. "/lib"
  lib = (vim.uv.fs_stat(lib .. "64") and (lib .. "64") or lib) .. "/nvim"
  local site = vim.fs.joinpath(vim.fn.stdpath("data"), "site")
  vim.opt.rtp = { vim.fn.stdpath("config"), site, vim.env.VIMRUNTIME, lib, vim.fn.stdpath("config") .. "/after" }
  vim.go.packpath = site .. "," .. vim.env.VIMRUNTIME
  -- The runtime plugins lazy.nvim kept off the runtimepath (disabled_plugins), by their own guards: gzip.vim:10,
  -- tarPlugin.vim:15, tutor.vim:7, zipPlugin.vim:24. Nightly's zip.lua has another guard, and lazy left it loaded too
  vim.g.loaded_gzip = 1
  vim.g.loaded_tarPlugin = 1
  vim.g.loaded_tutor_mode_plugin = 1
  vim.g.loaded_zipPlugin = 1

  local specs = {} ---@type vim.pack.Spec[]
  for _, p in ipairs(plugins) do
    local name = name_of(p)
    if by_name[name] then
      require("app").report(("%s is given twice; the second is skipped"):format(name), "app.plugins")
    else
      by_name[name] = p
      list[#list + 1] = p
      local src = p.src:find("://", 1, true) and p.src or ("https://github.com/" .. p.src)
      specs[#specs + 1] = { src = src, name = name, version = p.version }
    end
  end

  -- Before the first vim.pack call, which installs what the lockfile has and the disk lacks (:h vim.pack-events)
  vim.api.nvim_create_autocmd("PackChanged", {
    group = vim.api.nvim_create_augroup("app.plugins", { clear = true }),
    callback = function(ev)
      local p = by_name[ev.data.spec.name]
      if p and p.build and (ev.data.kind == "install" or ev.data.kind == "update") then
        if loaded[ev.data.spec.name] then
          try(ev.data.spec.name, "build", function() p.build(ev.data.path) end)
        else
          builds[ev.data.spec.name] = true
        end
      end
    end,
  })
  -- Installed and locked, not loaded: each phase loads its own. vim.pack.add raises once it has added every plugin
  -- that is on disk if any failed to install (runtime/lua/vim/pack.lua:1217-1234); the rest still load, without it
  local lockfile = vim.go.packlockfile
  local fd = io.open(lockfile, "r")
  local pinned = fd and fd:read("*a")
  if fd then
    fd:close()
  end
  local ok, err = pcall(vim.pack.add, specs, { load = function() end, confirm = false })
  if not ok then
    -- vim.pack keeps the lockfile in memory (runtime/lua/vim/pack.lua:1125-1127): its next write this session, an
    -- update, drops the restored pins again
    local msg = "vim.pack could not install every plugin; the others load. Restart Neovim before :packupdate, which"
      .. " would drop the failed plugins from the lockfile:\n%s"
    require("app").report(msg:format(err), "app.plugins")
    restore_pins(lockfile, pinned)
  end

  for _, p in ipairs(list) do
    if p.init then
      try(name_of(p), "init", p.init)
    end
  end
  table.insert(package.loaders, loader)
  for _, p in ipairs(list) do
    for _, cmd in ipairs(p.cmd or {}) do
      M.command(name_of(p), cmd)
    end
  end
  M.load_phase("startup")
end

return M
