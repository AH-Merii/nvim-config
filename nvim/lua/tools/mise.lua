-- The mise backend: async mise queries, the PATH the resolver searches, and mise's installs. The resolver reaches it
-- through the tools.Backend interface (tools/init.lua); every query runs with stdin closed and calls back on the main loop.

local proc = require("tools.proc")

local M = {}

local function data_dir()
  local xdg = vim.env.XDG_DATA_HOME or vim.fs.joinpath(vim.uv.os_homedir(), ".local/share")
  return vim.fs.normalize(vim.env.MISE_DATA_DIR or vim.fs.joinpath(xdg, "mise"))
end

--- The version of a binary in mise's install dir (installs/<tool>/<version>/...), following alias links such as
--- "latest"; nil for a binary elsewhere.
---@param path string
---@return string?
function M.install_version(path)
  local dir, alias = vim.fs.normalize(path):match("^(" .. vim.pesc(data_dir()) .. "/installs/[^/]+/)([^/]+)/")
  if not dir then
    return nil
  end
  local real = vim.uv.fs_realpath(dir .. alias)
  return real and vim.fs.basename(real) or alias
end

local function config_dir()
  local xdg = vim.env.XDG_CONFIG_HOME or vim.fs.joinpath(vim.uv.os_homedir(), ".config")
  return vim.fs.normalize(vim.env.MISE_CONFIG_DIR or vim.fs.joinpath(xdg, "mise"))
end

--- Whether a mise config path is the global one (or another non-project one) rather than a project's.
---@param path string
function M.is_global_config(path)
  path = vim.fs.normalize(path)
  local global = vim.env.MISE_GLOBAL_CONFIG_FILE and vim.fs.normalize(vim.env.MISE_GLOBAL_CONFIG_FILE)
  return path == global or vim.startswith(path, config_dir() .. "/") or vim.startswith(path, "/etc/mise/")
end

--- PATH entries that may hide the real binary: mise shims, mise install dirs (they belong to whatever dir
--- Neovim started in) and Mason's bin dir.
---@param dir string
local function stale(dir)
  local data = data_dir()
  return dir == ""
    or dir == data .. "/shims"
    or vim.startswith(dir, data .. "/installs/")
    or dir:find("/mise/shims/?$") ~= nil
    or dir:find("/mise/installs/") ~= nil
    or dir:find("/mason/bin/?$") ~= nil
end

--- Neovim's PATH without the stale entries.
---@return string[]
function M.clean_path()
  return vim.tbl_filter(function(dir) return not stale(vim.fs.normalize(dir)) end, vim.split(vim.env.PATH or "", ":", { plain = true }))
end

local mise_bin ---@type string|false|nil

--- Absolute path of mise, from the cleaned PATH; false when it is not installed.
---@return string|false
function M.bin()
  if mise_bin == nil then
    mise_bin = false
    for _, dir in ipairs(M.clean_path()) do
      local path = vim.fs.joinpath(dir, "mise")
      if vim.fn.executable(path) == 1 then
        mise_bin = path
        break
      end
    end
  end
  return mise_bin
end

--- Runs `mise <args>`, failing with code -1 when mise is not installed.
---@param args string[]
---@param opts? { cwd?: string, env?: table<string, string> }
---@param on_exit fun(result: tools.Run)
function M.mise(args, opts, on_exit)
  local bin = M.bin()
  if not bin then
    return vim.schedule(function() on_exit({ code = -1, stdout = "", stderr = "mise is not installed" }) end)
  end
  proc.run({ bin, unpack(args) }, opts, on_exit)
end

---@param text string
---@return string? path of an untrusted config named in mise's error
function M.untrusted(text) return text:match("Config files in (.-) are not trusted") end

--- Bin dirs of the tools active in scope, in PATH order. scope "/" is global tools only.
---@param scope string
---@param cb fun(dirs?: string[], err?: string)
function M.bin_paths(scope, cb)
  M.mise({ "bin-paths", "-C", scope }, nil, function(out)
    if out.code ~= 0 then
      return cb(nil, vim.trim(out.stderr))
    end
    cb(vim.tbl_filter(function(line) return line ~= "" end, vim.split(out.stdout, "\n", { plain = true })))
  end)
end

--- mise tool name -> the version the user's global configs make mise use, with whether it is installed and the file
--- that sets it; the config's own file (tools_file) is left out, as installing into it is the usual global install.
---@param cb fun(pins: table<string, { version: string, installed: boolean, source: string }>)
function M.global_pins(cb)
  M.mise({ "ls", "--current", "--json", "-C", "/" }, nil, function(out)
    local pins = {}
    local ok, tools = pcall(vim.json.decode, out.stdout)
    local own = M.tools_file()
    for tool, versions in pairs(out.code == 0 and ok and type(tools) == "table" and tools or {}) do
      for _, v in ipairs(versions) do
        local source = v.source and v.source.path and vim.fs.normalize(v.source.path)
        -- The first version listed is the one on PATH
        if source and source ~= own and not pins[tool] then
          pins[tool] = { version = v.version, installed = v.installed == true, source = source }
        end
      end
    end
    cb(pins)
  end)
end

---@class tools.ProjectScan
---@field configs string[] project config files mise reads in root, nearest first
---@field untrusted? string a config that blocks every mise call in root until trusted ([env] etc.)
---@field pins table<string, { version: string, installed: boolean, source: string, dir: string }> tools the project configs pin
---@field dirs string[] bin dirs of the project's pinned, installed tools, in PATH order
---@field all string[] bin dirs of every tool active in root (project and global), in PATH order
---@field err? string

--- What the project's mise configs pin in root.
---@param root string
---@param cb fun(scan: tools.ProjectScan)
function M.scan_project(root, cb)
  local scan = { configs = {}, pins = {}, dirs = {}, all = {} } ---@type tools.ProjectScan
  M.mise({ "config", "ls", "--json" }, { cwd = root }, function(out)
    if out.code ~= 0 then
      scan.untrusted = M.untrusted(out.stderr)
      scan.err = vim.trim(out.stderr)
      if scan.untrusted then
        scan.configs = { vim.fs.normalize(scan.untrusted) }
      end
      return cb(scan)
    end
    local ok, list = pcall(vim.json.decode, out.stdout)
    for _, config in ipairs(ok and list or {}) do
      if not M.is_global_config(config.path) then
        table.insert(scan.configs, vim.fs.normalize(config.path))
      end
    end
    if #scan.configs == 0 then
      return cb(scan)
    end
    M.mise({ "ls", "--current", "--json" }, { cwd = root }, function(ls)
      local decoded, tools = pcall(vim.json.decode, ls.stdout)
      for tool, versions in pairs(ls.code == 0 and decoded and tools or {}) do
        for _, v in ipairs(versions) do
          local source = v.source and v.source.path and vim.fs.normalize(v.source.path)
          if source and vim.list_contains(scan.configs, source) then
            -- install_path is versioned but bin-paths may go through a "latest" link, so match the tool's dir
            scan.pins[tool] = { version = v.version, installed = v.installed == true, source = source, dir = vim.fs.dirname(v.install_path) }
          end
        end
      end
      M.bin_paths(root, function(dirs, err)
        scan.err, scan.all = err, dirs or {}
        for _, dir in ipairs(dirs or {}) do
          for _, pin in pairs(scan.pins) do
            if vim.startswith(dir, pin.dir .. "/") then
              table.insert(scan.dirs, dir)
              break
            end
          end
        end
        cb(scan)
      end)
    end)
  end)
end

--- Env for a tool that needs a runtime: mise's env for scope with PATH = scope's bin dirs, then the cleaned PATH.
---@param scope string
---@param dirs string[] scope's bin dirs
---@param cb fun(env: table<string, string>)
function M.env(scope, dirs, cb)
  M.mise({ "env", "--json", "-C", scope }, nil, function(out)
    local ok, env = pcall(vim.json.decode, out.stdout)
    env = out.code == 0 and ok and type(env) == "table" and env or {}
    env.PATH = table.concat(vim.list_extend(vim.deepcopy(dirs), M.clean_path()), ":")
    cb(env)
  end)
end

--- Why installs can't run: mise is not installed; nil when they can.
---@return string?
function M.missing() return not M.bin() and "mise is not installed" or nil end

--- The global config file the config installs into: conf.d/nvim-config.toml in mise's config dir, which mise reads as
--- global config, so the user's config.toml (often a dotfiles file) is left alone. MISE_GLOBAL_CONFIG_FILE replaces
--- every global file, conf.d included, so with it set the tools go there.
---@return string
function M.tools_file()
  local global = vim.env.MISE_GLOBAL_CONFIG_FILE
  return global and global ~= "" and vim.fs.normalize(global) or config_dir() .. "/conf.d/nvim-config.toml"
end

--- `mise use --path <tools_file> <specs>`: a global install into the config's own file. Specs are full, e.g. "ruff@latest".
---@param specs string[]
---@param cb fun(ok: boolean, err?: string)
function M.use_global(specs, cb)
  -- cwd /: an untrusted project config with [env] would make mise refuse
  proc.install({ M.bin(), "use", "--path", M.tools_file(), unpack(specs) }, { cwd = "/", env = { MISE_YES = "1" } }, cb)
end

--- Tools for root's project only: `mise install <specs>`, then `mise config set --file <root>/mise.local.toml
--- tools.<tool> <version>` for each, creating the file when there is none (config set edits existing files only).
--- Every call runs from /, and neither writer trusts anything: `mise use --path` would trust the whole root, and with
--- MISE_YES in the root's dir mise trusts and reads (exec templates included) a mise.toml a `git pull` just brought.
--- A tool-only file needs no trust. A mise name with a dot or a bracket can't be written. A mise.local.toml that is a
--- link is refused (a repo could point it outside), and a file created here is removed when mise refuses to write it
--- (paranoid mode refuses untrusted files), so no empty config is left behind.
---@param root string
---@param specs string[]
---@param cb fun(ok: boolean, err?: string)
function M.use_local(root, specs, cb)
  local file = vim.fs.joinpath(root, "mise.local.toml")
  proc.install({ M.bin(), "install", unpack(specs) }, { cwd = "/", env = { MISE_YES = "1" } }, function(ok, err)
    if not ok then
      return cb(false, err)
    end
    local stat = vim.uv.fs_lstat(file)
    if stat and stat.type == "link" then
      return cb(false, ("not writing %s: it is a link to %s"):format(file, vim.uv.fs_readlink(file)))
    end
    local handle, open_err = io.open(file, "a")
    if not handle then
      return cb(false, ("couldn't create %s: %s"):format(file, open_err))
    end
    handle:close()
    local function set(i)
      local spec = specs[i]
      if not spec then
        return cb(true)
      end
      local tool, version = spec:match("^(.*)@([^@]*)$")
      proc.install({ M.bin(), "config", "set", "--file", file, "tools." .. tool, version }, { cwd = "/" }, function(set_ok, set_err)
        if not set_ok then
          if not stat then
            os.remove(file)
          end
          return cb(false, set_err)
        end
        set(i + 1)
      end)
    end
    set(1)
  end)
end

--- `mise install <specs>` from /, e.g. "ruff@0.15.0": a project's pinned versions land in mise's shared store without
--- trusting the project or changing its config, and the project then finds them.
---@param specs string[]
---@param cb fun(ok: boolean, err?: string)
function M.install(specs, cb) proc.install({ M.bin(), "install", unpack(specs) }, { cwd = "/", env = { MISE_YES = "1" } }, cb) end

--- `mise trust <configs>` in root.
---@param configs string[]
---@param root string
---@param cb fun(ok: boolean, err?: string)
function M.trust(configs, root, cb) proc.install({ M.bin(), "trust", unpack(configs) }, { cwd = root }, cb) end

--- `mise install` in root: every tool the project's configs pin.
---@param root string
---@param cb fun(ok: boolean, err?: string)
function M.install_project(root, cb) proc.install({ M.bin(), "install" }, { cwd = root, env = { MISE_YES = "1" } }, cb) end

return M
