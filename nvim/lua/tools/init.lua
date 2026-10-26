-- Finds each tool's binary per project root, asynchronously, and installs what is missing on request.
-- Order, first hit wins: project env (.venv/bin, node_modules/.bin, upward from the root), the project's mise
-- config if the user accepted it, global mise tools, the system PATH (without mise shims, mise install dirs
-- and Mason's bin dir). Results are cached per (tool, root); User ToolsChanged says when they change.

local catalog = require("tools.catalog")
local proc = require("tools.proc")
local state = require("tools.state")

local M = {}

M.catalog = catalog
M.event = "ToolsChanged"

---@alias tools.Source "project-env"|"project-mise"|"global-mise"|"system"|"missing"

---@class tools.Install
---@field kind "global"|"component"|"pinned"|"project"|"local"|"none" a global `mise use` (tools.mise.tools_file), `rustup component add`, `mise install <tool>@<pinned version>` (the project's pin, or the global config's), project `mise install`, `mise use` into the project's mise.local.toml, or nothing to offer
---@field spec? string global, local: the tool's `mise use` argument, e.g. "ruff@latest", nil when only its runtime is missing; pinned: "ruff@0.15.0"
---@field runtime? string global: a runtime (catalog.runtimes) missing from PATH, installed in the same step, e.g. "node"
---@field component? string component: the rustup component; global with runtime "rust": the component added after rust
---@field toolchain? string component: the toolchain the project pins in rust-toolchain(.toml), e.g. "1.92"
---@field version? string pinned: the version the project pins
---@field config? string pinned, project: file name of the config that pins it
---@field scope? "global" pinned: the user's global mise config pins the version, not the project
---@field global? tools.Install pinned: the global install offered instead
---@field project_only? tools.Install global: the same tool for this project only (kind "local"), offered alongside in a project

---@class tools.Copy
---@field path string
---@field version string
---@field where string ".venv" or "node_modules" for the project env, the config's file name for a mise pin

---@class tools.Result
---@field name string catalog binary
---@field root string
---@field path? string absolute executable to run (entry.run's sibling when set); nil when missing
---@field source tools.Source
---@field env? table<string, string> env to run with (PATH etc.) when the tool needs a runtime; nil means inherit
---@field reason? string why it is missing, or why a candidate was skipped
---@field install? tools.Install set when missing
---@field version? string known without running the tool: a mise install dir's version, a rustup toolchain, a checked --version; see M.version
---@field skipped? { source: tools.Source, version?: string }[] copies passed over for being older than the catalog's min
---@field offers? tools.Install[] installs offered for a found tool: the project's pinned version when another copy is used
---@field conflict? { env: tools.Copy, mise: tools.Copy, prefer?: tools.Prefer } the project env and the project's mise pin hold different versions

---@class tools.Project
---@field root string
---@field configs string[] project mise config files read in root, nearest first; empty when there is none or they pin no tools
---@field files string[] every project mise config file read in root, pinning tools or not (the untrusted one when mise refuses)
---@field untrusted? string an untrusted config that makes mise refuse every call in root; resolution uses global only
---@field choice? tools.Choice the remembered answer; nil when not asked yet or the configs changed since
---@field pins table<string, { version: string, installed: boolean, source: string }> mise tool name -> project pin
---@field missing string[] pinned mise tool names not installed
---@field active boolean whether resolution uses the project's pins
---@field dirs string[] bin dirs of the project's installed pins
---@field all string[] bin dirs of every tool active in root

---@class tools.Backend where tools come from and how they are installed: tools.mise, or a fake in tests/unit
---@field bin_paths fun(scope: "/", cb: fun(dirs?: string[], err?: string)) bin dirs of the global tools, in PATH order
---@field global_pins fun(cb: fun(pins: table<string, { version: string, installed: boolean, source: string }>)) mise tool name -> the version the user's global configs make mise use, outside the config's own file
---@field scan_project fun(root: string, cb: fun(scan: tools.ProjectScan)) what the project's configs pin in root
---@field env fun(scope: string, dirs: string[], cb: fun(env: table<string, string>)) env for a tool that needs a runtime
---@field install_version fun(path: string): string? the version of a binary in the backend's install dir
---@field clean_path fun(): string[] Neovim's PATH without the backend's shims and install dirs (the system layer)
---@field missing fun(): string? why installs can't run, nil when they can
---@field use_global fun(specs: string[], cb: fun(ok: boolean, err?: string)) global install into the config's own global mise file, e.g. "ruff@latest"
---@field use_local fun(root: string, specs: string[], cb: fun(ok: boolean, err?: string)) install for root's project only, into its mise.local.toml
---@field install fun(specs: string[], cb: fun(ok: boolean, err?: string)) a pinned version, e.g. "ruff@0.15.0"
---@field trust fun(configs: string[], root: string, cb: fun(ok: boolean, err?: string))
---@field install_project fun(root: string, cb: fun(ok: boolean, err?: string)) every tool the project pins

local backend = require("tools.mise") ---@type tools.Backend

---@class tools.Slot
---@field done? boolean
---@field value? any
---@field waiting? fun(value: any)[]

local shared = {} ---@type table<string, tools.Slot> "global" -> global mise bin dirs, "pins" -> global pins
local projects = {} ---@type table<string, tools.Slot> root -> tools.Project
local envs = {} ---@type table<string, tools.Slot> scope -> env
local results = {} ---@type table<string, table<string, tools.Slot>> root -> name -> tools.Result
local asks = {} ---@type table<string, string> root -> what the project prompt depends on, as of the root's last scan

--- Calls cb with the value in cache[key], starting the work once and queueing callers while it runs.
--- A slot dropped by refresh while running still answers its callers but is not kept.
---@param cache table<string, tools.Slot>
---@param key string
---@param start fun(done: fun(value: any))
---@param cb fun(value: any)
local function memo(cache, key, start, cb)
  local slot = cache[key]
  if slot and slot.done then
    return cb(slot.value)
  elseif slot then
    return table.insert(slot.waiting, cb)
  end
  slot = { waiting = { cb } }
  cache[key] = slot
  start(function(value)
    if cache[key] == slot then
      slot.done, slot.value = true, value
    end
    local waiting = slot.waiting or {}
    slot.waiting = nil
    for _, w in ipairs(waiting) do
      -- One caller's error must not leave the others waiting forever; it is raised on its own
      local ok, err = xpcall(w, debug.traceback, value)
      if not ok then
        vim.schedule(function() error(err, 0) end)
      end
    end
  end)
end

---@param root string
local function norm(root) return vim.fs.normalize(vim.fs.abspath(root)) end

-- What makes a dir a project root (vim.fs.root's markers: the first list wins over .git)
local project_markers = {
  {
    "mise.toml",
    ".mise.toml",
    "mise.local.toml",
    ".mise",
    ".tool-versions",
    ".venv",
    "node_modules",
    "pyproject.toml",
    "package.json",
    "Cargo.toml",
    "go.mod",
  },
  ".git",
}

--- Whether root is a project's root (holds one of its markers), not just the dir of a file outside any project. HOME
--- and / never are: a ~/.venv makes HOME a root, and a mise.local.toml there would apply to every dir below it.
---@param root string
local function is_project(root)
  -- Real paths: HOME may be a link to the dir the root names. HOME or a dir above it would put the file over every
  -- project below; an empty or unresolvable HOME can't be told apart from any root
  local real, home = vim.uv.fs_realpath(root), vim.uv.fs_realpath(vim.uv.os_homedir() or "")
  if not real or not home or real == "/" or real == home or vim.startswith(home, real .. "/") then
    return false
  end
  for _, marker in ipairs(vim.iter(project_markers):flatten():totable()) do
    if vim.uv.fs_stat(vim.fs.joinpath(root, marker)) then
      return true
    end
  end
  return false
end

---@param cb fun(dirs: string[])
local function global_dirs(cb)
  memo(shared, "global", function(done)
    backend.bin_paths("/", function(dirs) done(dirs or {}) end)
  end, cb)
end

--- The versions the user's global mise configs pin, once until the next refresh.
---@param cb fun(pins: table<string, { version: string, installed: boolean, source: string }>)
local function global_pins(cb)
  memo(shared, "pins", function(done) backend.global_pins(done) end, cb)
end

--- The global pin of a mise tool when it isn't installed: mise reads the user's config.toml after the config's own
--- conf.d file and lets it win, so installing "latest" there would leave the tool missing.
---@param tool string
---@param cb fun(pin?: { version: string, source: string })
local function missing_global_pin(tool, cb)
  global_pins(function(pins)
    local pin = pins[tool]
    cb(pin and not pin.installed and pin or nil)
  end)
end

---@param root string
---@param cb fun(project: tools.Project)
local function scan(root, cb)
  memo(projects, root, function(done)
    backend.scan_project(root, function(s)
      -- A config that pins no tools (one that only sets [env], say) changes nothing here and is not asked about,
      -- unless it is untrusted: then mise refuses every call in root until it is trusted
      local configs = (s.untrusted or next(s.pins)) and s.configs or {}
      local choice = #configs > 0 and state.get(configs) or nil
      local project =
        { root = root, configs = configs, files = s.configs, untrusted = s.untrusted, choice = choice, pins = {}, missing = {}, dirs = s.dirs, all = s.all }
      for tool, pin in pairs(s.pins) do
        project.pins[tool] = { version = pin.version, installed = pin.installed, source = pin.source }
        if not pin.installed then
          table.insert(project.missing, tool)
        end
      end
      table.sort(project.missing)
      project.active = not s.untrusted and (choice == "use" or choice == "installed")
      asks[root] = table.concat(configs, "\0") .. "\0" .. tostring(choice) .. "\0" .. tostring(s.untrusted)
      done(project)
    end)
  end, cb)
end

---@param project tools.Project
---@param cb fun(env: table<string, string>)
local function scope_env(project, cb)
  local scope = project.active and project.root or "/"
  global_dirs(function(dirs)
    -- mise leaves a pinned tool that is not installed out of the project's bin dirs, global copy included;
    -- the global dirs after them make that pin fall back to global (node, go)
    local path = project.active and vim.list_extend(vim.list_slice(project.all), dirs) or dirs
    memo(envs, scope, function(done) backend.env(scope, path, done) end, cb)
  end)
end

---@param dirs string[]
---@param bin string
---@return string?
local function find_in(dirs, bin)
  for _, dir in ipairs(dirs) do
    local path = vim.fs.joinpath(dir, bin)
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
end

---@param list string[]
---@param name string
local function add(list, name)
  if not vim.list_contains(list, name) then
    table.insert(list, name)
  end
end

--- Project copies of bin under rel dirs, from root upward; HOME itself and above are not searched.
---@param root string
---@param rels string[]
---@param bin string
---@return string[]
local function project_env(root, rels, bin)
  local found = {}
  local home = vim.fs.normalize(vim.uv.os_homedir() or "")
  for dir in vim.fs.parents(vim.fs.joinpath(root, "_")) do
    if dir == home then
      break
    end
    local path = find_in(vim.tbl_map(function(rel) return vim.fs.joinpath(dir, rel) end, rels), bin)
    if path then
      table.insert(found, path)
    end
  end
  return found
end

---@param text string
---@return string?
local function parse_version(text) return text:match("%d+%.%d+[%w.+-]*") end

-- A tool's --version must not hold up its row or its resolution for long
local version_timeout = 5000

---@class tools.Candidate
---@field path string
---@field source tools.Source
---@field version? string

---@param entry tools.Entry
---@param env? table<string, string>
---@param candidates tools.Candidate[]
---@param cb fun(found?: tools.Candidate, skipped: { path: string, source: tools.Source, version?: string, output: string }[])
local function first_accepted(entry, env, candidates, cb)
  local skipped = {}
  local function try(i)
    local candidate = candidates[i]
    if not candidate or not entry.min then
      return cb(candidate, skipped)
    end
    proc.run({ candidate.path, "--version" }, { env = env, timeout = version_timeout }, function(out)
      local version = out.code == 0 and parse_version(out.stdout) or nil
      local parsed = version and vim.version.parse(version, { strict = false })
      if parsed and vim.version.ge(parsed, entry.min) then
        candidate.version = version
        return cb(candidate, skipped)
      end
      local output = vim.trim(out.stdout ~= "" and out.stdout or out.stderr)
      table.insert(skipped, { path = candidate.path, source = candidate.source, version = version, output = output })
      try(i + 1)
    end)
  end
  try(1)
end

--- The project env dir a copy lives in: ".venv" or "node_modules", from the catalog entry's project dirs.
---@param entry tools.Entry
---@param path string
---@return string
local function env_dir(entry, path)
  for _, rel in ipairs(entry.project or {}) do
    if path:find("/" .. vim.pesc(rel) .. "/", 1) then
      return (rel:match("^[^/]+"))
    end
  end
  return "project env"
end
M.env_dir = env_dir

--- When the project config is in use and both the project env and a mise pin hold the tool, in different versions,
--- the two copies and the remembered answer to which one to use; nil otherwise.
---@param name string
---@param entry tools.Entry
---@param project tools.Project
---@param env_path? string
---@param mise_path? string
---@param env? table<string, string>
---@param cb fun(conflict?: { env: tools.Copy, mise: tools.Copy, prefer?: tools.Prefer })
local function find_conflict(name, entry, project, env_path, mise_path, env, cb)
  local pinned = entry.spec and project.pins[entry.spec]
  if not (project.active and env_path and mise_path and pinned) then
    return cb(nil)
  end
  proc.run({ env_path, "--version" }, { env = env, timeout = version_timeout }, function(out)
    local version = parse_version(out.stdout)
    if not version or version == pinned.version then
      return cb(nil)
    end
    cb({
      env = { path = env_path, version = version, where = env_dir(entry, env_path) },
      mise = { path = mise_path, version = pinned.version, where = vim.fs.basename(pinned.source) },
      prefer = state.prefer(project.configs, name),
    })
  end)
end

--- The toolchain a rust-toolchain(.toml) at or above root pins, e.g. "1.92"; nil when there is none.
---@param root string
---@return string?
local function pinned_toolchain(root)
  local file = vim.fs.find({ "rust-toolchain.toml", "rust-toolchain" }, { path = root, upward = true, type = "file" })[1]
  local ok, lines = pcall(vim.fn.readfile, file or "")
  if not file or not ok then
    return nil
  end
  local text = table.concat(lines, "\n")
  return text:match('channel%s*=%s*"([^"]+)"') or (not file:find("%.toml$") and vim.trim(lines[1] or "")) or nil
end

--- A rustup toolchain's name without its host triple: "stable-x86_64-unknown-linux-gnu" -> "stable".
---@param toolchain string
local function short_toolchain(toolchain)
  for _, arch in ipairs({ "x86_64", "aarch64", "i686", "armv7", "arm", "riscv64", "powerpc64le", "s390x", "loongarch64" }) do
    local name = toolchain:match("^(.-)%-" .. arch .. "%-")
    if name then
      return name
    end
  end
  return toolchain
end

--- Whether runtime's binary is on env's PATH.
---@param runtime string
---@param env table<string, string>
local function has_runtime(runtime, env) return find_in(vim.split(env.PATH or "", ":", { plain = true }), catalog.runtimes[runtime].bin) ~= nil end

---@param name string
---@param root string
---@param done fun(result: tools.Result)
local function compute(name, root, done)
  local entry = catalog.tools[name] or {}
  if entry.spec then
    -- Asked alongside the global bin dirs, so a missing tool's result doesn't wait one more mise call after the
    -- others' (a statusline that counts the missing tools would drop it in between)
    global_pins(function() end)
  end
  scan(root, function(project)
    global_dirs(function(gdirs)
      scope_env(project, function(env)
        local run_env = entry.runtime and env or nil
        local env_paths = project_env(root, entry.project or {}, name)
        local mise_path = project.active and find_in(project.dirs, name) or nil
        find_conflict(name, entry, project, env_paths[1], mise_path, run_env, function(conflict)
          ---@type tools.Candidate[]
          local candidates = {}
          -- The project env comes first unless the user picked the mise pin over it
          local mise_first = conflict and conflict.prefer == "mise"
          if mise_path and mise_first then
            table.insert(candidates, { path = mise_path, source = "project-mise" })
          end
          for _, path in ipairs(env_paths) do
            table.insert(candidates, { path = path, source = "project-env" })
          end
          if mise_path and not mise_first then
            table.insert(candidates, { path = mise_path, source = "project-mise" })
          end
          for _, layer in ipairs({ { "global-mise", gdirs }, { "system", backend.clean_path() } }) do
            local path = find_in(layer[2], name)
            if path then
              table.insert(candidates, { path = path, source = layer[1] })
            end
          end

          first_accepted(entry, run_env, candidates, function(found, skipped)
            ---@type tools.Result
            local result = { name = name, root = root, source = "missing", conflict = conflict }
            if #skipped > 0 then
              result.reason = table.concat(vim.tbl_map(function(s) return ("%s skipped (version %s)"):format(s.path, s.output) end, skipped), "; ")
              result.skipped = vim.tbl_map(function(s) return { source = s.source, version = s.version } end, skipped)
            end
            local function missing(reason, install)
              result.reason = table.concat(vim.list_extend(result.reason and { result.reason } or {}, { reason }), "; ")
              result.install = install
              done(result)
            end
            local runtime = entry.runtime and entry.runtime ~= "rust" and not has_runtime(entry.runtime, env) and entry.runtime or nil
            local pinned = entry.spec and project.pins[entry.spec]
            local pin_missing = pinned and not pinned.installed and not project.untrusted
            -- D100: in a project the tool can go to the project alone (its mise.local.toml), unless the project pins
            -- it, its mise config isn't in use (the file would join an unanswered or declined config) or a runtime
            -- is missing too
            local project_only = entry.spec
                and not pinned
                and not runtime
                and not project.untrusted
                and (#project.configs == 0 or project.active)
                and is_project(root)
                -- `mise config set` can't write a key with a dot or a bracket (tools.mise.use_local)
                and not entry.spec:find("[.%[]")
                and { kind = "local", spec = entry.spec .. "@latest" }
              or nil
            local global = entry.spec and { kind = "global", spec = entry.spec .. "@latest", runtime = runtime, project_only = project_only } or nil
            ---@type tools.Install?
            local for_project = pin_missing
                and project.choice == "installed"
                and {
                  kind = "pinned",
                  spec = ("%s@%s"):format(entry.spec, pinned.version),
                  version = pinned.version,
                  config = vim.fs.basename(pinned.source),
                  global = global,
                }
              or nil
            if not found then
              if pin_missing and project.choice == "use" then
                return missing("pinned by the project but not installed", { kind = "project", config = vim.fs.basename(pinned.source) })
              elseif for_project then
                return missing("pinned by the project but not installed", for_project)
              elseif entry.component then
                return missing("rustup not found", { kind = "global", runtime = "rust", component = entry.component })
              elseif global then
                return missing_global_pin(entry.spec, function(pin)
                  if pin then
                    local config = vim.fs.basename(pin.source)
                    local spec = ("%s@%s"):format(entry.spec, pin.version)
                    return missing(
                      ("pinned by your global %s but not installed"):format(config),
                      -- A project's mise.local.toml outranks the global pin, so the project-only install works too
                      { kind = "pinned", spec = spec, version = pin.version, config = config, scope = "global", project_only = project_only }
                    )
                  end
                  missing(runtime and ("not installed, and %s is not on PATH"):format(runtime) or "not installed", global)
                end)
              end
              return missing("not on PATH; install it with the system package manager", { kind = "none" })
            end

            local function finish()
              if runtime then
                return missing(("needs %s on PATH"):format(runtime), { kind = "global", runtime = runtime })
              end
              result.path = entry.run and vim.fs.joinpath(vim.fs.dirname(found.path), entry.run) or found.path
              result.source, result.env = found.source, run_env
              result.version = result.version or found.version or backend.install_version(found.path)
              -- The project pins a version that is not installed while another copy is used: offer the pinned one
              result.offers = for_project and found.source ~= "project-env" and { for_project } or nil
              done(result)
            end
            if not entry.component then
              return finish()
            end
            -- rust-analyzer, rustfmt and cargo-clippy are rustup proxies that exist whether or not the component does
            local dirs = { vim.fs.dirname(found.path), unpack(vim.split(env.PATH, ":", { plain = true })) }
            local rustup = find_in(dirs, "rustup")
            if not rustup then
              return missing("rustup not found", { kind = "global", runtime = "rust", component = entry.component })
            end
            proc.run({ rustup, "which", name }, { cwd = root, env = env }, function(out)
              if out.code ~= 0 then
                return missing(vim.trim(out.stderr):match("[^\n]*"), { kind = "component", component = entry.component, toolchain = pinned_toolchain(root) })
              end
              local toolchain = vim.trim(out.stdout):match("/toolchains/([^/]+)/")
              result.version = toolchain and short_toolchain(toolchain)
              finish()
            end)
          end)
        end)
      end)
    end)
  end)
end

local versions = {} ---@type table<string, string|false> path -> version its --version reports, false when none

--- Calls cb with a found tool's version: result.version when known, else what its --version reports (cached per
--- path until the next refresh); nil when it is missing or reports none.
---@param result tools.Result
---@param cb fun(version?: string)
function M.version(result, cb)
  if result.version or not result.path then
    return cb(result.version)
  end
  local path = result.path
  if versions[path] ~= nil then
    return cb(versions[path] or nil)
  end
  proc.run({ path, "--version" }, { env = result.env, timeout = version_timeout }, function(out)
    versions[path] = parse_version(out.stdout) or parse_version(out.stderr) or false
    cb(versions[path] or nil)
  end)
end

---@param a? tools.Result
---@param b tools.Result
local function same(a, b) return a ~= nil and a.path == b.path and a.source == b.source and a.reason == b.reason end

local changed = {} ---@type table<string, { tools: table<string, true>, reason: string }> root -> pending event
local reasons = { resolved = 1, refresh = 2, accepted = 3, installed = 4 }

--- Queues name, if any, in the next ToolsChanged for root; events for one root within a tick are merged.
---@param root string
---@param name? string
---@param reason "resolved"|"refresh"|"accepted"|"installed"
local function notify(root, name, reason)
  local pending = changed[root]
  if not pending then
    pending = { tools = {}, reason = reason }
    changed[root] = pending
    vim.schedule(function()
      changed[root] = nil
      local tools = vim.tbl_keys(pending.tools)
      table.sort(tools)
      vim.api.nvim_exec_autocmds("User", { pattern = M.event, modeline = false, data = { root = root, tools = tools, reason = pending.reason } })
    end)
  elseif reasons[reason] > reasons[pending.reason] then
    pending.reason = reason
  end
  if name then
    pending.tools[name] = true
  end
end

local refresh_reason = "refresh" ---@type "refresh"|"accepted"|"installed"
local previous = {} ---@type table<string, table<string, tools.Result>> root -> name -> result before the last refresh

--- Whether buf is a file: named, no 'buftype' and no scheme:// name (health://, oil://, fugitive://).
---@param buf integer
---@return boolean
local function is_file(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  return name ~= "" and vim.bo[buf].buftype == "" and not name:match("^%a[%w+.-]*://")
end

--- The project buf belongs to: the nearest dir with a mise config, .venv, node_modules or a language project file,
--- else the git root; nil outside any project.
---@param buf? integer
---@return string?
function M.project_root(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local root = vim.fs.root(buf, project_markers)
  return root and norm(root)
end

--- The root used for buf's tools: its project root, else the file's dir, or the cwd for a buffer that isn't a file.
---@param buf? integer
---@return string
function M.root(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  return M.project_root(buf) or norm(is_file(buf) and vim.fs.dirname(vim.api.nvim_buf_get_name(buf)) or vim.fn.getcwd())
end

--- The cached result for name in root, or nil if it was never resolved or is being resolved again.
---@param name string catalog binary
---@param root string
---@return tools.Result?
function M.get(name, root)
  local slot = (results[norm(root)] or {})[name]
  return slot and slot.done and slot.value or nil
end

--- Resolves name in root. Returns the result when cached and then calls cb at once; otherwise returns nil,
--- starts the work, and calls cb on the main loop when done. Concurrent calls share one resolution.
---@param name string catalog binary; another name is searched without project paths or install offers
---@param root string
---@param cb? fun(result: tools.Result)
---@return tools.Result?
function M.resolve(name, root, cb)
  root = norm(root)
  results[root] = results[root] or {}
  local sync ---@type tools.Result?
  local returned = false
  memo(results[root], name, function(done)
    local slot = results[root][name]
    compute(name, root, function(result)
      -- A resolution a later refresh dropped says nothing: get() would not return it, and the one replacing it
      -- still needs the result from before the refresh to tell what moved
      if (results[root] or {})[name] ~= slot then
        return done(result)
      end
      local old = (previous[root] or {})[name]
      if not same(old, result) then
        notify(root, name, old and refresh_reason or "resolved")
      end
      if previous[root] then
        previous[root][name] = nil
      end
      done(result)
    end)
  end, function(result)
    if not returned then
      sync = result
    end
    if cb then
      cb(result)
    end
  end)
  returned = true
  return sync
end

--- Resolves several tools and calls cb once with all of them, keyed by name.
---@param names string[]
---@param root string
---@param cb fun(results: table<string, tools.Result>)
function M.resolve_all(names, root, cb)
  local out, left = {}, #names
  if left == 0 then
    return cb(out)
  end
  for _, name in ipairs(names) do
    M.resolve(name, root, function(result)
      out[name] = result
      left = left - 1
      if left == 0 then
        cb(out)
      end
    end)
  end
end

--- Blocks (processing events) until name in root is resolved or timeout ms pass; for sync callers like conform's
--- command function. Returns nil on timeout, or at once when called in a fast event and nothing is cached.
---@param name string
---@param root string
---@param timeout? integer default 2000
---@return tools.Result?
function M.wait(name, root, timeout)
  local result = M.resolve(name, root)
  if result or vim.in_fast_event() then
    return result
  end
  vim.wait(timeout or 2000, function() return M.get(name, root) ~= nil end, 10)
  return M.get(name, root)
end

--- The project's mise config state for root. Same calling convention as resolve.
---@param root string
---@param cb? fun(project: tools.Project)
---@return tools.Project?
function M.project(root, cb)
  local sync ---@type tools.Project?
  local returned = false
  scan(norm(root), function(project)
    if not returned then
      sync = project
    end
    if cb then
      cb(project)
    end
  end)
  returned = true
  return sync
end

--- Drops cached results (for root, or everywhere) and resolves the dropped tools again; ToolsChanged fires
--- for those whose result changed, and with no tools for a root whose project configs, answer to the project prompt
--- or trust changed. Run after anything that may move a binary.
---@param root? string
---@param reason? "refresh"|"accepted"|"installed" ToolsChanged reason, default "refresh"
function M.refresh(root, reason)
  refresh_reason = reason or "refresh"
  local roots = root and { norm(root) } or vim.tbl_keys(results)
  -- Global tools and runtimes may have moved too (`mise use -g` in a terminal), and every root whose project
  -- is not active shares the global env
  shared, envs, versions = {}, {}, {}
  if not root then
    projects = {}
  end
  for _, r in ipairs(roots) do
    projects[r], envs[r] = nil, nil
    previous[r] = previous[r] or {}
    for name, slot in pairs(results[r] or {}) do
      previous[r][name] = slot.done and slot.value or previous[r][name]
    end
    local names = vim.tbl_keys(results[r] or {})
    results[r] = {}
    for _, name in ipairs(names) do
      M.resolve(name, r)
    end
  end
  -- Scan again every root scanned before, with or without tools, so a new config or an answer shows (the "?" of the
  -- statusline's tools indicator) even when no tool's result changes
  local why = refresh_reason
  for r, before in pairs(root and { [norm(root)] = asks[norm(root)] } or vim.deepcopy(asks)) do
    scan(r, function()
      if asks[r] ~= before then
        notify(r, nil, why)
      end
    end)
  end
end

--- Whether installs may run: never with vim.g.install_tools = "off" or without a UI (headless, tests).
function M.can_install() return vim.g.install_tools ~= "off" and #vim.api.nvim_list_uis() > 0 end

---@param start fun(cb: fun(ok: boolean, err?: string)) runs the install
---@param cb fun(ok: boolean, err?: string)
local function install_run(start, cb)
  if not M.can_install() then
    return vim.schedule(function() cb(false, "installs are off (vim.g.install_tools or no UI)") end)
  end
  start(cb)
end

---@param cb? fun(ok: boolean, err?: string)
---@param title string
local function reporter(cb, title)
  return function(ok, err)
    M.refresh(nil, "installed")
    if cb then
      cb(ok, err)
    elseif not ok then
      vim.notify(err or "failed", vim.log.levels.ERROR, { title = title })
    end
  end
end

--- A global `mise use <specs>` (into the config's own global file, tools.mise.tools_file), then refresh. Specs are full, e.g. "ruff@latest" (tools.Install.spec).
---@param specs string[]
---@param cb? fun(ok: boolean, err?: string)
function M.install_global(specs, cb)
  local missing = backend.missing()
  if missing then
    return reporter(cb, "Tools")(false, missing)
  end
  install_run(function(done) backend.use_global(specs, done) end, reporter(cb, "Tools"))
end

--- `mise install <specs>` from /, then refresh. For a project's pinned versions, e.g. "ruff@0.15.0": they land in
--- mise's shared store without trusting the project or changing its config, and the project then finds them.
---@param specs string[]
---@param cb? fun(ok: boolean, err?: string)
function M.install_pinned(specs, cb)
  local missing = backend.missing()
  if missing then
    return reporter(cb, "Tools")(false, missing)
  end
  install_run(function(done) backend.install(specs, done) end, reporter(cb, "Tools"))
end

--- `rustup component add <components>` in root, so they land in the toolchain root uses, then refresh.
---@param components string|string[]
---@param root string
---@param cb? fun(ok: boolean, err?: string)
function M.install_component(components, root, cb)
  root = norm(root)
  components = type(components) == "string" and { components } or components
  scan(root, function(project)
    scope_env(project, function(env)
      local rustup = find_in(vim.split(env.PATH, ":", { plain = true }), "rustup")
      if not rustup then
        return reporter(cb, "Tools")(false, "rustup not found")
      end
      install_run(function(done) proc.install({ rustup, "component", "add", unpack(components) }, { cwd = root, env = env }, done) end, reporter(cb, "Tools"))
    end)
  end)
end

--- `mise trust` on the project's configs, then `mise install` in root, then refresh. Trusting is part of it:
--- mise install trusts its active config anyway.
---@param root string
---@param cb? fun(ok: boolean, err?: string)
function M.install_project(root, cb)
  root = norm(root)
  local report = reporter(cb, "Tools")
  local missing = backend.missing()
  if missing then
    return report(false, missing)
  end
  local trusted = {} ---@type table<string, true>
  local choice ---@type tools.Choice?
  ---@param project tools.Project
  local function trust(project)
    if #project.configs == 0 then
      -- A trusted config that turns out to pin no tools leaves nothing to install
      return report(next(trusted) ~= nil, "no project mise config in " .. root)
    end
    -- Read here: set_choice stores the answer after the scan cached in projects was made
    choice = choice or state.get(project.configs)
    local pending = vim.tbl_filter(function(path) return not trusted[path] end, project.configs)
    if project.untrusted and #pending == 0 then
      return report(false, project.untrusted .. " is still not trusted after mise trust")
    end
    local function next_step()
      if project.untrusted then
        -- mise names only the first untrusted config it meets and hides the others; look again
        projects[root] = nil
        return scan(root, trust)
      end
      -- The answer was stored for the configs known before trusting, and mise may read more of them now
      if choice then
        state.set(project.configs, choice)
      end
      install_run(function(done) backend.install_project(root, done) end, report)
    end
    if #pending == 0 then
      return next_step()
    end
    install_run(function(done) backend.trust(pending, root, done) end, function(ok, err)
      if not ok then
        return report(false, err)
      end
      for _, path in ipairs(pending) do
        trusted[path] = true
      end
      next_step()
    end)
  end
  scan(root, trust)
end

local git_local_vars ---@type string[]? what `git rev-parse --local-env-vars` lists, once per session

--- Options for a git call in root that finds root's own repo: Neovim's env without the variables that point git at
--- a repo (GIT_DIR, GIT_WORK_TREE, …: `git rev-parse --local-env-vars`), which a bare-repo dotfiles setup exports.
---@param root string
---@param cb fun(opts: { cwd: string, env: table<string, string>, clear_env: boolean })
local function git_opts(root, cb)
  local function done()
    local env = vim.fn.environ()
    for _, var in ipairs(git_local_vars) do
      env[var] = nil
    end
    cb({ cwd = root, env = env, clear_env = true })
  end
  if git_local_vars then
    return done()
  end
  proc.run({ "git", "rev-parse", "--local-env-vars" }, { cwd = "/" }, function(out)
    git_local_vars = out.code == 0 and vim.split(vim.trim(out.stdout), "\n", { trimempty = true }) or {}
    done()
  end)
end

--- Appends mise.local.toml to the .gitignore at path, adding a newline first when the file doesn't end in one, unless
--- it is a link (a stowed .gitignore, say: the edit would land outside the repo). Returns the notification to show.
---@param path string
---@return { [1]: string, [2]: integer }
local function append_ignore(path)
  local name = "mise.local.toml"
  local link = vim.uv.fs_readlink(path)
  if link then
    return { ("Not adding %s to .gitignore: it is a link to %s"):format(name, vim.fn.fnamemodify(link, ":~")), vim.log.levels.WARN }
  end
  local file = io.open(path, "rb")
  local text = file and file:read("*a") or ""
  if file then
    file:close()
  end
  local written, err = false, nil
  file, err = io.open(path, "ab")
  if file then
    written, err = file:write((text ~= "" and not text:find("\n$")) and "\n" or "", name, "\n")
    file:close()
  end
  if not written then
    return { ("Couldn't add %s to .gitignore: %s"):format(name, err or "write failed"), vim.log.levels.ERROR }
  end
  return { ("Added %s to .gitignore"):format(name), vim.log.levels.INFO }
end

--- Puts mise.local.toml in the top-level .gitignore of the git repo root is in, when the repo's rules neither ignore
--- it nor un-ignore it ("!mise.local.toml") and the repo doesn't track it. A bare name ignores it in every dir, so it
--- is one line per repo. cb gets the notification to show: what changed, or why .gitignore was left alone; nil when
--- nothing needed changing.
---@param root string
---@param cb fun(note?: { [1]: string, [2]: integer })
local function ignore_local(root, cb)
  local name = "mise.local.toml"
  git_opts(root, function(opts)
    -- -n -v: exit 1 only when no pattern matches; --no-index: by the rules alone; outside a repo: 128
    proc.run({ "git", "check-ignore", "--no-index", "-n", "-v", name }, opts, function(check)
      if check.code ~= 1 then
        return cb(nil)
      end
      proc.run({ "git", "ls-files", "--error-unmatch", name }, opts, function(tracked)
        if tracked.code == 0 then
          return cb(nil)
        end
        proc.run({ "git", "rev-parse", "--show-toplevel" }, opts, function(out)
          if out.code ~= 0 then
            return cb(nil)
          end
          -- core.worktree can put the work tree outside the checkout that holds root, and a dotfiles repo checked out
          -- in HOME holds every project below it that has no repo of its own
          local top = vim.fs.normalize(vim.trim(out.stdout))
          local real = vim.uv.fs_realpath(root) or root
          local in_top = (real == top or vim.startswith(real, top .. "/")) and vim.uv.fs_stat(top .. "/.git")
          if not in_top or vim.uv.fs_realpath(top) == vim.uv.fs_realpath(vim.uv.os_homedir() or "") then
            local text = ("Not adding %s to .gitignore: git's top level %s is not this project's checkout"):format(name, vim.fn.fnamemodify(top, ":~"))
            return cb({ text, vim.log.levels.WARN })
          end
          cb(append_ignore(vim.fs.joinpath(top, ".gitignore")))
        end)
      end)
    end)
  end)
end

--- Tools for root's project only (D100): installed, then added to root's mise.local.toml (tools.mise.use_local, which
--- trusts nothing), then refresh. The answer to the project prompt carries over so the tools are used at once ("installed"
--- when there was no config), but only when the configs are the ones a fresh scan saw before the install, unchanged, plus
--- mise.local.toml: one a terminal `git pull` added or changed meanwhile is asked about. mise.local.toml itself is the
--- file the install writes, so its change is no reason to ask (D164). In a git repo the file goes into the repo's
--- .gitignore (ignore_local), with a toast.
---@param specs string[]
---@param root string
---@param cb? fun(ok: boolean, err?: string)
function M.install_local(specs, root, cb)
  root = norm(root)
  local report = reporter(cb, "Tools")
  local missing = backend.missing()
  if missing then
    return report(false, missing)
  end
  ---@param files string[]
  local function key(files)
    local real = vim.tbl_map(function(path) return vim.uv.fs_realpath(path) or path end, files)
    table.sort(real)
    return table.concat(vim.fn.uniq(real), "\0")
  end
  local file = vim.fs.joinpath(root, "mise.local.toml")
  ---@param files string[]
  local function others(files)
    local real = vim.uv.fs_realpath(file) or file
    return vim.tbl_filter(function(path) return (vim.uv.fs_realpath(path) or path) ~= real end, files)
  end
  projects[root] = nil
  scan(root, function(before)
    -- The answer is saved for the configs' contents, which the install changes when mise.local.toml was among them
    local answered, unchanged = state.hash(before.configs), state.hash(others(before.configs))
    install_run(function(done) backend.use_local(root, specs, done) end, function(ok, err)
      if not ok then
        return report(false, err)
      end
      projects[root] = nil
      scan(root, function(project)
        local same = not before.untrusted
          and not project.untrusted
          and key(project.files) == key(vim.list_extend({ file }, before.files))
          and state.hash(others(before.configs)) == unchanged
        if same and #project.configs > 0 then
          if #before.configs == 0 then
            state.set(project.configs, "installed")
          elseif before.active and state.get(before.configs, answered) == before.choice then
            state.set(project.configs, before.choice)
          end
        end
        ignore_local(root, function(note)
          if note then
            vim.notify(note[1], note[2], { title = "Tools" })
          end
          report(true)
        end)
      end)
    end)
  end)
end

---@class tools.InstallItem
---@field name string catalog binary
---@field install tools.Install

--- Runs installs, then refreshes: global ones in one `mise use` together with the runtimes they miss (a rustup
--- component that needed rust is added once rust is in), pinned versions in one `mise install`, components in one
--- `rustup component add`. cb gets mise's or rustup's errors and the names whose install failed.
---@param items tools.InstallItem[]
---@param root string
---@param cb? fun(ok: boolean, errs: string[], failed: string[])
function M.apply(items, root, cb)
  root = norm(root)
  local global = { specs = {}, names = {}, components = {} }
  local pinned = { specs = {}, names = {} }
  local component = { components = {}, names = {} }
  local project = {} ---@type string[]
  local here = { specs = {}, names = {} }
  for _, item in ipairs(items) do
    local inst = item.install
    if inst.kind == "global" then
      add(global.names, item.name)
      if inst.spec then
        add(global.specs, inst.spec)
      end
      if inst.runtime then
        add(global.specs, catalog.runtimes[inst.runtime].spec)
      end
      if inst.component then
        add(global.components, inst.component)
      end
    elseif inst.kind == "pinned" then
      add(pinned.specs, inst.spec)
      add(pinned.names, item.name)
    elseif inst.kind == "component" then
      add(component.components, inst.component)
      add(component.names, item.name)
    elseif inst.kind == "project" then
      add(project, item.name)
    elseif inst.kind == "local" then
      add(here.specs, inst.spec)
      add(here.names, item.name)
    end
  end

  local errs, failed, left = {}, {}, 1
  ---@param names string[]
  local function step(names)
    return function(ok, err)
      if not ok then
        table.insert(errs, err or "failed")
        vim.list_extend(failed, names)
      end
      left = left - 1
      if left == 0 and cb then
        cb(#errs == 0, errs, failed)
      end
    end
  end
  if #global.specs > 0 then
    left = left + 1
    M.install_global(global.specs, function(ok, err)
      if not ok or #global.components == 0 then
        return step(global.names)(ok, err)
      end
      M.install_component(global.components, root, step(global.names))
    end)
  end
  if #pinned.specs > 0 then
    left = left + 1
    M.install_pinned(pinned.specs, step(pinned.names))
  end
  if #component.components > 0 then
    left = left + 1
    M.install_component(component.components, root, step(component.names))
  end
  if #project > 0 then
    left = left + 1
    M.install_project(root, step(project))
  end
  if #here.specs > 0 then
    left = left + 1
    M.install_local(here.specs, root, step(here.names))
  end
  step({})(true)
end

--- Installs what each named tool's result offers (see M.apply); with opts.global, a pinned version's global
--- alternative instead.
---@param names string[]
---@param root string
---@param cb? fun(ok: boolean, errs: string[], failed: string[])
---@param opts? { global?: boolean }
function M.install(names, root, cb, opts)
  M.resolve_all(names, root, function(found)
    local items = {}
    for _, name in ipairs(names) do
      local inst = found[name].install
      if inst and opts and opts.global and inst.global then
        inst = inst.global
      end
      if inst and inst.kind ~= "none" then
        table.insert(items, { name = name, install = inst })
      end
    end
    M.apply(items, root, cb)
  end)
end

--- Remembers which copy of name to use in root's project when the project env and the mise pin differ, then refreshes.
---@param root string
---@param name string catalog binary
---@param prefer tools.Prefer
---@param cb? fun(ok: boolean, err?: string)
function M.set_prefer(root, name, prefer, cb)
  root = norm(root)
  scan(root, function(project)
    if #project.configs == 0 then
      return cb and cb(false, "no project mise config in " .. root)
    end
    state.set_prefer(project.configs, name, prefer)
    M.refresh(nil, "accepted")
    if cb then
      cb(true)
    end
  end)
end

--- Remembers the answer to the project prompt for root's configs; "use" also runs install_project.
---@param root string
---@param choice tools.Choice
---@param cb? fun(ok: boolean, err?: string)
function M.set_choice(root, choice, cb)
  root = norm(root)
  scan(root, function(project)
    if #project.configs == 0 then
      return cb and cb(false, "no project mise config in " .. root)
    end
    state.set(project.configs, choice)
    if choice == "use" then
      return M.install_project(root, cb) -- refreshes with reason "installed", even when installs are off
    end
    M.refresh(nil, "accepted")
    if cb then
      cb(true)
    end
  end)
end

--- File patterns of the mise configs a project may have; writing one refreshes everything
M.config_patterns = {
  "mise.toml",
  ".mise.toml",
  "mise.local.toml",
  ".tool-versions",
  "*/mise/config.toml",
  "*/mise/conf.d/*.toml",
  "*/.mise/config.toml",
  "*/.mise/conf.d/*.toml",
  "*/.config/mise.toml",
}

--- opts.backend replaces where tools come from (default tools.mise) and drops every cached answer.
---@param opts? { backend?: tools.Backend }
function M.setup(opts)
  if opts and opts.backend then
    backend, shared, projects, envs, results, versions, previous, asks = opts.backend, {}, {}, {}, {}, {}, {}, {}
  end
  local group = vim.api.nvim_create_augroup("tools", { clear = true })
  -- Start the mise queries for a file's project as it opens, so formatters and linters rarely wait
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].buftype == "" and vim.api.nvim_buf_get_name(ev.buf) ~= "" then
        M.project(M.root(ev.buf))
        global_dirs(function() end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, pattern = M.config_patterns, callback = function() M.refresh() end })
end

return M
