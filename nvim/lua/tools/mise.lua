-- Async mise queries and the PATH the resolver searches. Every query runs with stdin closed and calls back on the main loop.

local M = {}

---@class tools.Run
---@field code integer
---@field stdout string
---@field stderr string

--- Runs cmd and calls back with its result on the main loop; a missing executable is code -1.
---@param cmd string[]
---@param opts? { cwd?: string, env?: table<string, string> }
---@param on_exit fun(result: tools.Run)
function M.run(cmd, opts, on_exit)
  opts = opts or {}
  local done = vim.schedule_wrap(function(out) on_exit({ code = out.code, stdout = out.stdout or "", stderr = out.stderr or "" }) end)
  local ok, err = pcall(vim.system, cmd, { cwd = opts.cwd, env = opts.env, text = true, stdin = false }, done)
  if not ok then
    vim.schedule(function() on_exit({ code = -1, stdout = "", stderr = tostring(err) }) end)
  end
end

local function data_dir()
  local xdg = vim.env.XDG_DATA_HOME or vim.fs.joinpath(vim.uv.os_homedir(), ".local/share")
  return vim.fs.normalize(vim.env.MISE_DATA_DIR or vim.fs.joinpath(xdg, "mise"))
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
  M.run({ bin, unpack(args) }, opts, on_exit)
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

return M
