-- A fake tool backend (tools.Backend) for unit tests: mise's answers come from a table, and each tool it holds is a
-- real executable in a throwaway install dir whose `--version` prints its version. It supports only what the unit
-- tests use: global tools, a project's pins, and global installs; the other installs raise.
--
--   local backend = fake({
--     global = { ruff = "0.17.0", node = "22.0.0" },            -- catalog binary (or runtime binary) -> version
--     projects = { [root] = { ruff = "0.15.0", tsc = { version = "7.0.2", installed = false } } },
--   })
--   tools.setup({ backend = backend })
--   backend.calls                                               -- { { "use_global", { "ruff@latest" } }, ... }

local catalog = require("tools.catalog")
local h = require("helper")

---@class fake.Pin
---@field version string
---@field installed? boolean default true

---@param opts { global?: table<string, string>, projects?: table<string, table<string, string|fake.Pin>>, latest?: string }
return function(opts)
  local dir = h.tmpdir()
  local global = vim.deepcopy(opts.global or {}) ---@type table<string, string>
  local B = { calls = {} } ---@type tools.Backend|{ calls: { [1]: string, [2]: any }[] }

  ---@param bin string
  ---@param version string
  ---@return string bin dir
  local function install(bin, version)
    local bindir = ("%s/installs/%s/%s/bin"):format(dir, bin, version)
    h.bin(bindir .. "/" .. bin, version)
    return bindir
  end

  --- The mise tool name a binary comes from: its catalog spec, or the runtime's name.
  ---@param bin string
  local function tool_of(bin)
    local entry = catalog.tools[bin]
    return entry and entry.spec or bin
  end

  ---@param tool string mise tool name, e.g. "npm:yaml-language-server" or "node"
  ---@return string[] the binaries it provides
  local function bins_of(tool)
    local bins = {}
    for bin, entry in pairs(catalog.tools) do
      if entry.spec == tool then
        table.insert(bins, bin)
      end
    end
    for _, runtime in pairs(catalog.runtimes) do
      if runtime.spec:match("^(.*)@") == tool then
        table.insert(bins, runtime.bin)
      end
    end
    return bins
  end

  local function global_dirs()
    local dirs = {}
    for bin, version in vim.spairs(global) do
      table.insert(dirs, install(bin, version))
    end
    return dirs
  end

  function B.bin_paths(scope, cb)
    assert(scope == "/", "fake backend: bin_paths only for the global scope")
    local dirs = global_dirs()
    vim.schedule(function() cb(dirs) end)
  end

  function B.scan_project(root, cb)
    local scan = { configs = {}, pins = {}, dirs = {}, all = {} } ---@type tools.ProjectScan
    local pins = (opts.projects or {})[root]
    if pins then
      local config = root .. "/mise.toml"
      local lines = { "[tools]" }
      for bin, pin in vim.spairs(pins) do
        pin = type(pin) == "string" and { version = pin } or pin
        local installed = pin.installed ~= false
        local bindir = ("%s/installs/%s/%s/bin"):format(dir, bin, pin.version)
        scan.pins[tool_of(bin)] = { version = pin.version, installed = installed, source = config, dir = vim.fs.dirname(bindir) }
        if installed then
          table.insert(scan.dirs, install(bin, pin.version))
        end
        table.insert(lines, ('"%s" = "%s"'):format(tool_of(bin), pin.version))
      end
      h.write(config, lines)
      scan.configs = { config }
      scan.all = vim.list_extend(vim.list_slice(scan.dirs), global_dirs())
    end
    vim.schedule(function() cb(scan) end)
  end

  function B.env(_, dirs, cb)
    local path = table.concat(vim.list_extend(vim.list_slice(dirs), B.clean_path()), ":")
    vim.schedule(function() cb({ PATH = path }) end)
  end

  function B.install_version(path) return path:match("^" .. vim.pesc(dir) .. "/installs/[^/]+/([^/]+)/") end

  function B.clean_path()
    return vim.tbl_filter(function(d) return not vim.startswith(d, dir .. "/") end, vim.split(vim.env.PATH or "", ":", { plain = true }))
  end

  function B.missing() return nil end

  --- Installs each spec's binaries globally, at opts.latest (default "1.0.0") for "latest" and "lts".
  function B.use_global(specs, cb)
    table.insert(B.calls, { "use_global", specs })
    for _, spec in ipairs(specs) do
      local tool, version = spec:match("^(.*)@([^@]*)$")
      local bins = bins_of(tool)
      assert(#bins > 0, "fake backend: no binary for " .. spec)
      for _, bin in ipairs(bins) do
        global[bin] = (version == "latest" or version == "lts") and (opts.latest or "1.0.0") or version
      end
    end
    vim.schedule(function() cb(true) end)
  end

  for _, op in ipairs({ "install", "trust", "install_project" }) do
    B[op] = function() error("fake backend: " .. op .. " is not supported") end
  end

  return B
end
