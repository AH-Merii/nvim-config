-- Finds each tool's binary per project root, asynchronously, and installs what is missing on request.
-- Order, first hit wins: project env (.venv/bin, node_modules/.bin, upward from the root), the project's mise
-- config if the user accepted it, global mise tools, the system PATH (without mise shims, mise install dirs
-- and Mason's bin dir). Results are cached per (tool, root); User ToolsChanged says when they change.

local catalog = require("tools.catalog")
local mise = require("tools.mise")
local state = require("tools.state")

local M = {}

M.catalog = catalog
M.event = "ToolsChanged"

---@alias tools.Source "project-env"|"project-mise"|"global-mise"|"system"|"missing"

---@class tools.Install
---@field kind "global"|"component"|"project"|"none" `mise use -g`, `rustup component add`, project `mise install`, or nothing to offer
---@field spec? string for global: the full `mise use -g` argument, e.g. "ruff@latest"
---@field component? string for component: the rustup component

---@class tools.Result
---@field name string catalog binary
---@field root string
---@field path? string absolute executable to run (entry.run's sibling when set); nil when missing
---@field source tools.Source
---@field env? table<string, string> env to run with (PATH etc.) when the tool needs a runtime; nil means inherit
---@field reason? string why it is missing, or why a candidate was skipped
---@field install? tools.Install set when missing

---@class tools.Project
---@field root string
---@field configs string[] project mise config files read in root, nearest first; empty when there is none
---@field untrusted? string an untrusted config that makes mise refuse every call in root; resolution uses global only
---@field choice? tools.Choice the remembered answer; nil when not asked yet or the configs changed since
---@field pins table<string, { version: string, installed: boolean, source: string }> mise tool name -> project pin
---@field missing string[] pinned mise tool names not installed
---@field active boolean whether resolution uses the project's pins
---@field dirs string[] bin dirs of the project's installed pins
---@field all string[] bin dirs of every tool active in root

---@class tools.Slot
---@field done? boolean
---@field value? any
---@field waiting? fun(value: any)[]

local shared = {} ---@type table<string, tools.Slot> "global" -> global mise bin dirs
local projects = {} ---@type table<string, tools.Slot> root -> tools.Project
local envs = {} ---@type table<string, tools.Slot> scope -> env
local results = {} ---@type table<string, table<string, tools.Slot>> root -> name -> tools.Result

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

---@param cb fun(dirs: string[])
local function global_dirs(cb)
  memo(shared, "global", function(done)
    mise.bin_paths("/", function(dirs) done(dirs or {}) end)
  end, cb)
end

---@param root string
---@param cb fun(project: tools.Project)
local function scan(root, cb)
  memo(projects, root, function(done)
    mise.scan_project(root, function(s)
      local choice = #s.configs > 0 and state.get(s.configs) or nil
      local project = { root = root, configs = s.configs, untrusted = s.untrusted, choice = choice, pins = {}, missing = {}, dirs = s.dirs, all = s.all }
      for tool, pin in pairs(s.pins) do
        project.pins[tool] = { version = pin.version, installed = pin.installed, source = pin.source }
        if not pin.installed then
          table.insert(project.missing, tool)
        end
      end
      table.sort(project.missing)
      project.active = not s.untrusted and (choice == "use" or choice == "installed")
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
    memo(envs, scope, function(done) mise.env(scope, path, done) end, cb)
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

---@param entry tools.Entry
---@param env? table<string, string>
---@param candidates { path: string, source: tools.Source }[]
---@param cb fun(found?: { path: string, source: tools.Source }, skipped: string[])
local function first_accepted(entry, env, candidates, cb)
  local skipped = {}
  local function try(i)
    local candidate = candidates[i]
    if not candidate or not entry.accept then
      return cb(candidate, skipped)
    end
    mise.run({ candidate.path, "--version" }, { env = env }, function(out)
      if out.code == 0 and entry.accept(out.stdout) then
        return cb(candidate, skipped)
      end
      table.insert(skipped, ("%s skipped (version %s)"):format(candidate.path, vim.trim(out.stdout ~= "" and out.stdout or out.stderr)))
      try(i + 1)
    end)
  end
  try(1)
end

---@param name string
---@param root string
---@param done fun(result: tools.Result)
local function compute(name, root, done)
  local entry = catalog.tools[name] or {}
  scan(root, function(project)
    global_dirs(function(gdirs)
      scope_env(project, function(env)
        local run_env = entry.runtime and env or nil
        local candidates = {}
        for _, path in ipairs(project_env(root, entry.project or {}, name)) do
          table.insert(candidates, { path = path, source = "project-env" })
        end
        for _, layer in ipairs({
          { "project-mise", project.active and project.dirs or {} },
          { "global-mise", gdirs },
          { "system", mise.clean_path() },
        }) do
          local path = find_in(layer[2], name)
          if path then
            table.insert(candidates, { path = path, source = layer[1] })
          end
        end

        first_accepted(entry, run_env, candidates, function(found, skipped)
          ---@type tools.Result
          local result = { name = name, root = root, source = "missing", reason = #skipped > 0 and table.concat(skipped, "; ") or nil }
          local function missing(reason, install)
            result.reason = table.concat(vim.list_extend(vim.list_slice(skipped), { reason }), "; ")
            result.install = install
            done(result)
          end
          local pinned = entry.spec and project.pins[entry.spec]
          if not found then
            if pinned and not pinned.installed and project.choice == "use" then
              return missing("pinned by the project but not installed", { kind = "project" })
            elseif entry.component then
              return missing("rustup not found", { kind = "global", spec = catalog.runtimes.rust.spec })
            elseif entry.spec then
              return missing("not installed", { kind = "global", spec = entry.spec .. "@latest" })
            end
            return missing("not on PATH; install it with the system package manager", { kind = "none" })
          end

          local function finish()
            local runtime = entry.runtime and entry.runtime ~= "rust" and catalog.runtimes[entry.runtime]
            if runtime and not find_in(vim.split(env.PATH, ":", { plain = true }), runtime.bin) then
              return missing(("needs %s on PATH"):format(runtime.bin), { kind = "global", spec = runtime.spec })
            end
            result.path = entry.run and vim.fs.joinpath(vim.fs.dirname(found.path), entry.run) or found.path
            result.source, result.env = found.source, run_env
            done(result)
          end
          if not entry.component then
            return finish()
          end
          -- rust-analyzer, rustfmt and cargo-clippy are rustup proxies that exist whether or not the component does
          local dirs = { vim.fs.dirname(found.path), unpack(vim.split(env.PATH, ":", { plain = true })) }
          local rustup = find_in(dirs, "rustup")
          if not rustup then
            return missing("rustup not found", { kind = "global", spec = catalog.runtimes.rust.spec })
          end
          mise.run({ rustup, "which", name }, { cwd = root, env = env }, function(out)
            if out.code ~= 0 then
              return missing(vim.trim(out.stderr):match("[^\n]*"), { kind = "component", component = entry.component })
            end
            finish()
          end)
        end)
      end)
    end)
  end)
end

---@param a? tools.Result
---@param b tools.Result
local function same(a, b) return a ~= nil and a.path == b.path and a.source == b.source and a.reason == b.reason end

local changed = {} ---@type table<string, { tools: table<string, true>, reason: string }> root -> pending event
local reasons = { resolved = 1, refresh = 2, accepted = 3, installed = 4 }

--- Queues name in the next ToolsChanged for root; events for one root within a tick are merged.
---@param root string
---@param name string
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
  pending.tools[name] = true
end

local refresh_reason = "refresh" ---@type "refresh"|"accepted"|"installed"
local previous = {} ---@type table<string, table<string, tools.Result>> root -> name -> result before the last refresh

--- The project buf belongs to: the nearest dir with a mise config, .venv, node_modules or a language project file,
--- else the git root; nil outside any project.
---@param buf? integer
---@return string?
function M.project_root(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local root = vim.fs.root(buf, {
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
  })
  return root and norm(root)
end

--- The root used for buf's tools: its project root, else the file's dir.
---@param buf? integer
---@return string
function M.root(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local name = vim.api.nvim_buf_get_name(buf)
  return M.project_root(buf) or norm(name ~= "" and vim.fs.dirname(name) or vim.fn.getcwd())
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
--- for those whose result changed. Run after anything that may move a binary.
---@param root? string
---@param reason? "refresh"|"accepted"|"installed" ToolsChanged reason, default "refresh"
function M.refresh(root, reason)
  refresh_reason = reason or "refresh"
  local roots = root and { norm(root) } or vim.tbl_keys(results)
  -- Global tools and runtimes may have moved too (`mise use -g` in a terminal), and every root whose project
  -- is not active shares the global env
  shared, envs = {}, {}
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
end

--- Whether installs may run: never with vim.g.install_tools = "off" or without a UI (headless, tests).
function M.can_install() return vim.g.install_tools ~= "off" and #vim.api.nvim_list_uis() > 0 end

---@param cmd string[]
---@param opts { cwd?: string, env?: table<string, string> }
---@param cb fun(ok: boolean, err?: string)
local function install_run(cmd, opts, cb)
  if not M.can_install() then
    return vim.schedule(function() cb(false, "installs are off (vim.g.install_tools or no UI)") end)
  end
  mise.run(cmd, opts, function(out)
    if out.code ~= 0 then
      return cb(false, ("%s: %s"):format(table.concat(cmd, " "), vim.trim(out.stderr ~= "" and out.stderr or out.stdout)))
    end
    cb(true)
  end)
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

--- `mise use -g <specs>` (into the global config), then refresh. Specs are full, e.g. "ruff@latest" (tools.Install.spec).
---@param specs string[]
---@param cb? fun(ok: boolean, err?: string)
function M.install_global(specs, cb)
  local bin = mise.bin()
  if not bin then
    return reporter(cb, "Tools")(false, "mise is not installed")
  end
  -- cwd /: an untrusted project config with [env] would make mise refuse
  install_run({ bin, "use", "-g", unpack(specs) }, { cwd = "/", env = { MISE_YES = "1" } }, reporter(cb, "Tools"))
end

--- `rustup component add <component>` in root, then refresh.
---@param component string
---@param root string
---@param cb? fun(ok: boolean, err?: string)
function M.install_component(component, root, cb)
  root = norm(root)
  scan(root, function(project)
    scope_env(project, function(env)
      local rustup = find_in(vim.split(env.PATH, ":", { plain = true }), "rustup")
      if not rustup then
        return reporter(cb, "Tools")(false, "rustup not found")
      end
      install_run({ rustup, "component", "add", component }, { cwd = root, env = env }, reporter(cb, "Tools"))
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
  local bin = mise.bin()
  if not bin then
    return report(false, "mise is not installed")
  end
  local trusted = {} ---@type table<string, true>
  local choice ---@type tools.Choice?
  ---@param project tools.Project
  local function trust(project)
    if #project.configs == 0 then
      return report(false, "no project mise config in " .. root)
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
      install_run({ bin, "install" }, { cwd = root, env = { MISE_YES = "1" } }, report)
    end
    if #pending == 0 then
      return next_step()
    end
    install_run({ bin, "trust", unpack(pending) }, { cwd = root }, function(ok, err)
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

--- Installs whatever each named tool's result offers (global ones in one `mise use -g`), then refreshes.
---@param names string[]
---@param root string
---@param cb? fun(ok: boolean, errs: string[])
function M.install(names, root, cb)
  M.resolve_all(names, root, function(found)
    local specs, components, project, errs, left = {}, {}, false, {}, 1
    for _, result in pairs(found) do
      local install = result.install or { kind = "none" }
      if install.kind == "global" and not vim.list_contains(specs, install.spec) then
        table.insert(specs, install.spec)
      elseif install.kind == "component" and not vim.list_contains(components, install.component) then
        table.insert(components, install.component)
      elseif install.kind == "project" then
        project = true
      end
    end
    local function step(ok, err)
      if not ok then
        table.insert(errs, err)
      end
      left = left - 1
      if left == 0 and cb then
        cb(#errs == 0, errs)
      end
    end
    if #specs > 0 then
      left = left + 1
      M.install_global(specs, step)
    end
    for _, component in ipairs(components) do
      left = left + 1
      M.install_component(component, root, step)
    end
    if project then
      left = left + 1
      M.install_project(root, step)
    end
    step(true)
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

---@param list string[]
---@param name string
local function add(list, name)
  if not vim.list_contains(list, name) then
    table.insert(list, name)
  end
end

--- The servers, formatters and linters configured for a filetype, and the catalog binaries behind them.
--- Uses each adapter's own lookup: servers match the whole filetype, conform the whole filetype then the most
--- specific part, nvim-lint the whole filetype else every part. Loads conform and nvim-lint.
---@param ft string
---@param buf? integer passed to a conform formatters_by_ft function
---@return { servers: string[], formatters: string[], linters: string[], tools: string[] }
function M.for_filetype(ft, buf)
  local out = { servers = {}, formatters = {}, linters = {}, tools = {} }
  for _, server in ipairs(catalog.servers()) do
    local ok, config = pcall(function() return vim.lsp.config[server] end)
    if ok and config and vim.list_contains(config.filetypes or {}, ft) and vim.lsp.is_enabled(server) then
      add(out.servers, server)
      add(out.tools, catalog.binary("server", server))
    end
  end

  local has_conform, conform = pcall(require, "conform")
  if has_conform then
    local parts = vim.iter(vim.split(ft, ".", { plain = true })):rev():totable()
    for _, key in ipairs({ ft, unpack(parts) }) do
      local formatters = conform.formatters_by_ft[key]
      if type(formatters) == "function" then
        formatters = buf and formatters(buf) or {}
      end
      if type(formatters) == "table" and next(formatters) then
        -- An entry may be a list of alternatives
        for _, item in ipairs(formatters) do
          for _, name in ipairs(type(item) == "table" and item or { item }) do
            add(out.formatters, name)
            add(out.tools, catalog.binary("formatter", name) or name)
          end
        end
        break
      end
    end
  end

  local has_lint, lint = pcall(require, "lint")
  if has_lint then
    for _, name in ipairs(lint._resolve_linter_by_ft(ft)) do
      add(out.linters, name)
      add(out.tools, catalog.binary("linter", name) or name)
    end
  end
  return out
end

--- File patterns of the mise configs a project may have; writing one refreshes everything
M.config_patterns = { "mise.toml", ".mise.toml", "mise.local.toml", ".tool-versions", "*/mise/config.toml", "*/.mise/config.toml", "*/.config/mise.toml" }

function M.setup()
  require("tools.filetypes").setup()
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
