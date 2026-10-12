-- The install prompts, the :Tools view and the statusline indicator for the tool resolver (tools).
-- Asks once per project mise config (use + install / installed only / global only), then once per missing tool
-- that this file's filetype would run. Never asks for library code, git files, special buffers, or when installs
-- are off (vim.g.install_tools = "off", or no UI: headless runs and tests). After that, only the indicator and :Tools.

local tools = require("tools")
local catalog = require("tools.catalog")
local state = require("tools.state")

local M = {}

local title = "Tools"

-- Install offers already made, so each is asked only once: "global:<spec>" or "component:<name>"
M.file = vim.fs.joinpath(vim.fn.stdpath("state"), "tools", "offered.json")

local asked = {} ---@type table<string, true> offers and project prompts made this session, answered or dismissed
local tracked = {} ---@type table<integer, { root: string, ft: string, names: string[] }> buf -> its tools, for status()
local checked = {} ---@type table<integer, string> buf -> filetype its prompts ran for

---@return table<string, string>
local function read_offered()
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(M.file), "\n")) end)
  return ok and type(data) == "table" and data or {}
end

---@param key string
local function offered(key) return asked[key] or read_offered()[key] ~= nil end

---@param keys string[]
---@param persist boolean false for a dismissed prompt: not asked again this session only
local function remember(keys, persist)
  for _, key in ipairs(keys) do
    asked[key] = true
  end
  -- A project's own installs are covered by its project prompt, which asks again when its config changes
  keys = vim.tbl_filter(function(key) return not vim.startswith(key, "project:") end, keys)
  if not persist or #keys == 0 then
    return
  end
  local data = read_offered() -- re-read, another session may have written since
  for _, key in ipairs(keys) do
    data[key] = os.date("!%Y-%m-%d")
  end
  vim.fn.mkdir(vim.fs.dirname(M.file), "p")
  vim.fn.writefile({ vim.json.encode(data) }, M.file)
end

---@param path string
local function short(path) return vim.fn.fnamemodify(path, ":~") end

--------------------------------------------------------------------------------
-- Which buffers may prompt
--------------------------------------------------------------------------------

-- Installed packages and toolchain sources: site-packages, node_modules, the cargo registry, the Go module cache
local library_patterns = { "/site%-packages/", "/dist%-packages/", "/node_modules/", "/%.cargo/registry/", "/%.cargo/git/", "/pkg/mod/", "/rustlib/src/" }

---@return string[]
local function library_dirs()
  local home = vim.uv.os_homedir() or ""
  local cargo = vim.env.CARGO_HOME or vim.fs.joinpath(home, ".cargo")
  local dirs = { vim.fs.joinpath(cargo, "registry"), vim.fs.joinpath(cargo, "git") }
  if vim.env.GOMODCACHE then
    table.insert(dirs, vim.env.GOMODCACHE)
  end
  for _, gopath in ipairs(vim.split(vim.env.GOPATH or vim.fs.joinpath(home, "go"), ":", { trimempty = true })) do
    table.insert(dirs, vim.fs.joinpath(gopath, "pkg", "mod"))
  end
  return vim.tbl_map(function(dir) return vim.fs.normalize(dir) .. "/" end, dirs)
end

--- Whether path is installed library code rather than the user's own.
---@param path string
function M.is_library(path)
  path = vim.fs.normalize(path)
  for _, pattern in ipairs(library_patterns) do
    if path:find(pattern) then
      return true
    end
  end
  for _, dir in ipairs(library_dirs()) do
    if vim.startswith(path, dir) then
      return true
    end
  end
  return false
end

local skip_filetypes = { gitcommit = true, gitrebase = true, diff = true, help = true, [""] = true }

--- Whether opening buf may prompt: a real file the user edits, not library code, git files or a diff.
---@param buf integer
function M.eligible(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or skip_filetypes[vim.bo[buf].filetype] then
    return false
  end
  local name = vim.api.nvim_buf_get_name(buf)
  -- fugitive://, diffview:// and other plugin buffers; files inside .git (COMMIT_EDITMSG, rebase todo)
  if name == "" or name:match("^%a[%w+.-]*://") or name:find("/%.git/") then
    return false
  end
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.wo[win].diff then
      return false
    end
  end
  return not M.is_library(name)
end

--------------------------------------------------------------------------------
-- The tools a buffer runs
--------------------------------------------------------------------------------

---@param list string[]
---@param name string
local function add(list, name)
  if not vim.list_contains(list, name) then
    table.insert(list, name)
  end
end

--- The catalog binaries buf's filetype runs (servers, formatters, linters, and what they call), and per binary
--- the roles it has there, e.g. { "server ruff", "format ruff_fix" }. Loads conform and nvim-lint.
---@param buf integer
---@return string[] names, table<string, string[]> roles, string[] servers
local function needed(buf)
  local ok, found = pcall(tools.for_filetype, vim.bo[buf].filetype, buf)
  if not ok then
    return {}, {}, {}
  end
  local names, roles = {}, {}
  for _, role in ipairs({ { "server", found.servers }, { "formatter", found.formatters }, { "linter", found.linters } }) do
    for _, name in ipairs(role[2]) do
      local bin = catalog.binary(role[1], name)
      -- Names outside the catalog (conform's trim_whitespace, ...) are not binaries mise provides
      if bin then
        add(names, bin)
        roles[bin] = roles[bin] or {}
        table.insert(roles[bin], role[1] .. " " .. name)
        for _, required in ipairs(catalog.tools[bin].requires or {}) do
          add(names, required)
          roles[required] = roles[required] or { "used by " .. bin }
        end
      end
    end
  end
  return names, roles, found.servers
end

---@param install tools.Install
---@param root string
local function offer_key(install, root)
  if install.kind == "global" then
    return "global:" .. install.spec
  elseif install.kind == "component" then
    return "component:" .. install.component
  end
  return "project:" .. root
end

---@param install tools.Install
---@param root string
local function describe(install, root)
  if install.kind == "global" then
    return "mise use -g " .. install.spec
  elseif install.kind == "component" then
    return "rustup component add " .. install.component
  elseif install.kind == "project" then
    return ("mise install in %s (trusts its config)"):format(short(root))
  end
  return "nothing to install with mise"
end

--- What tools.install runs for these installs: global specs go into one `mise use -g`.
---@param installs tools.Install[]
---@param root string
local function describe_all(installs, root)
  local specs, commands = {}, {}
  for _, inst in ipairs(installs) do
    if inst.kind == "global" then
      add(specs, inst.spec)
    else
      add(commands, describe(inst, root))
    end
  end
  if #specs > 0 then
    table.insert(commands, 1, "mise use -g " .. table.concat(specs, " "))
  end
  return table.concat(commands, "; ")
end

--------------------------------------------------------------------------------
-- Installs, with a progress message and the result shown
--------------------------------------------------------------------------------

--- Runs an install, showing a progress message while it runs (the statusline's progress) and a notification when it ends.
--- tools refreshes after every install, which fires User ToolsChanged for each tool it moved.
---@param label string what runs, e.g. "mise use -g ruff@latest"
---@param start fun(cb: fun(ok: boolean, errs: string[]))
---@param on_done? fun(ok: boolean)
function M.run_install(label, start, on_done)
  local progress = { kind = "progress", source = "tools", title = title, status = "running" }
  progress.id = vim.api.nvim_echo({ { label } }, false, progress)
  start(function(ok, errs)
    progress.status = ok and "success" or "failed"
    vim.api.nvim_echo({ { label } }, false, progress)
    if ok then
      vim.notify(label .. ": done", vim.log.levels.INFO, { title = title })
    else
      vim.notify(("%s: failed\n%s"):format(label, table.concat(errs, "\n")), vim.log.levels.ERROR, { title = title })
    end
    if on_done then
      on_done(ok)
    end
  end)
end

---@param names string[]
---@param root string
---@param label string
---@param on_done? fun(ok: boolean)
local function install(names, root, label, on_done)
  M.run_install(label, function(cb) tools.install(names, root, cb) end, on_done)
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------

--- The project prompt: whether to use the project's mise config. Calls done when answered, dismissed or not needed.
---@param project tools.Project
---@param done fun()
---@param force? boolean ask even when answered before
function M.ask_project(project, done, force)
  -- Keyed by the configs' contents too: an edit drops the remembered answer, so it is asked again
  local key = project.configs[1] and ("project-config:%s:%s"):format(project.configs[1], state.hash(project.configs))
  if not key or (not force and (project.choice or asked[key])) then
    return done()
  end
  asked[key] = true
  local root = project.root
  local configs = table.concat(vim.tbl_map(short, project.configs), ", ")
  local pins = vim.tbl_keys(project.pins)
  table.sort(pins)
  local items = {
    { choice = "use", text = ("Use + install: trust %s and run mise install"):format(configs) },
    { choice = "installed", text = "Installed only: use the pinned tools already installed; no install, no trust" },
    { choice = "global", text = "Global only: ignore this config (.venv and node_modules still apply)" },
  }
  local prompt
  if project.untrusted then
    -- mise refuses every call under an untrusted config with [env], so only trusting it makes its pins usable
    table.remove(items, 2)
    prompt = ("%s is not trusted (it sets [env]); use it?"):format(short(project.untrusted))
  else
    prompt = ("%s pins %s%s; use it?"):format(
      configs,
      #pins > 0 and table.concat(pins, ", ") or "no tools",
      #project.missing > 0 and (" (%d not installed)"):format(#project.missing) or ""
    )
  end
  vim.ui.select(items, { prompt = prompt, kind = "tools.project", format_item = function(item) return item.text end }, function(item)
    if not item then
      return done()
    end
    if item.choice == "use" then
      asked["project:" .. root] = true -- set_choice installs; a failure is shown, not offered again
      return M.run_install(("mise install in %s"):format(short(root)), function(cb)
        tools.set_choice(root, "use", function(ok, err) cb(ok, { err }) end)
      end, function() done() end)
    end
    tools.set_choice(root, item.choice, function(ok, err)
      if not ok then
        vim.notify(err or "failed", vim.log.levels.ERROR, { title = title })
      end
      done()
    end)
  end)
end

--- The missing-tool prompt: one batched offer of everything buf's filetype runs that is missing and not offered before.
---@param buf integer
---@param root string
---@param done fun()
local function offer_tools(buf, root, done)
  local names = needed(buf)
  tools.resolve_all(names, root, function(results)
    local offer, keys, installs = {}, {}, {}
    for _, name in ipairs(names) do
      local result = results[name]
      local inst = result and not result.path and result.install
      if inst and inst.kind ~= "none" then
        local key = offer_key(inst, root)
        if not offered(key) and not vim.list_contains(keys, key) then
          table.insert(offer, name)
          table.insert(keys, key)
          table.insert(installs, inst)
        end
      end
    end
    if #offer == 0 or not vim.api.nvim_buf_is_valid(buf) then
      return done()
    end
    local label = describe_all(installs, root)
    local items = {
      { install = true, text = "Install: " .. label },
      { install = false, text = "Not now (not asked again; :Tools installs it later)" },
    }
    local prompt = ("%s needs %s, which %s missing"):format(vim.bo[buf].filetype, table.concat(offer, ", "), #offer == 1 and "is" or "are")
    vim.ui.select(items, { prompt = prompt, kind = "tools.install", format_item = function(item) return item.text end }, function(item)
      remember(keys, item ~= nil)
      if item and item.install then
        install(offer, root, label)
      end
      done()
    end)
  end)
end

-- One prompt at a time; installs run on in the background
local queue = {} ---@type fun(done: fun())[]
local busy = false

local function next_prompt()
  local job = not busy and table.remove(queue, 1)
  if job then
    busy = true
    job(function()
      busy = false
      vim.schedule(next_prompt)
    end)
  end
end

--- Asks what buf's project and filetype need, once per buffer and filetype.
---@param buf integer
function M.check(buf)
  local ft = vim.bo[buf].filetype
  if vim.v.vim_did_enter ~= 1 or checked[buf] == ft or not tools.can_install() or not M.eligible(buf) then
    return
  end
  checked[buf] = ft
  table.insert(queue, function(done)
    if not M.eligible(buf) or not tools.can_install() then
      return done()
    end
    local root = tools.root(buf)
    tools.project(root, function(project)
      M.ask_project(project, function() offer_tools(buf, root, done) end)
    end)
  end)
  next_prompt()
end

--------------------------------------------------------------------------------
-- Indicator
--------------------------------------------------------------------------------

--- Starts resolving buf's tools so status() can count them.
---@param buf integer
local function track(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" or vim.api.nvim_buf_get_name(buf) == "" then
    return
  end
  local root, ft = tools.root(buf), vim.bo[buf].filetype
  local names = needed(buf)
  tracked[buf] = { root = root, ft = ft, names = names }
  tools.resolve_all(names, root, function() end)
end

--- Statusline text: empty when every tool buf runs is found and its project config is answered; otherwise
--- the number of missing tools and "?" for an unanswered project config, e.g. "2" or "?" (lualine adds the icon).
---@param buf? integer default current
---@return string
function M.status(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local info = tracked[buf]
  if not info then
    return ""
  end
  local missing = 0
  for _, name in ipairs(info.names) do
    local result = tools.get(name, info.root)
    if result and not result.path then
      missing = missing + 1
    end
  end
  local project = tools.project(info.root)
  local unanswered = project and #project.configs > 0 and project.choice == nil
  if missing == 0 and not unanswered then
    return ""
  end
  return (missing > 0 and tostring(missing) or "") .. (unanswered and "?" or "")
end

--------------------------------------------------------------------------------
-- :Tools
--------------------------------------------------------------------------------

--- Restarts servers on buf (and the other buffers they serve), or starts them when they are not running.
---@param servers string[]
---@param buf integer
function M.restart(servers, buf)
  local clients, stopped = {}, {}
  for _, server in ipairs(servers) do
    local running = vim.lsp.get_clients({ bufnr = buf, name = server })
    vim.list_extend(clients, running)
    if #running == 0 then
      table.insert(stopped, server)
    end
  end
  if #clients > 0 then
    require("core.lsp_servers").restart(clients)
  end
  if #stopped > 0 then
    -- Enabling again re-runs the enable FileType handler on every buffer, which starts what is not running
    vim.lsp.enable(stopped)
  end
  vim.notify(("Restarted %s"):format(table.concat(servers, ", ")), vim.log.levels.INFO, { title = title })
end

---@param root string
---@param names string[]
local function retry(root, names)
  tools.refresh(root)
  tools.resolve_all(names, root, function(results)
    local lines = {}
    for _, name in ipairs(names) do
      local result = results[name]
      table.insert(lines, ("%s: %s"):format(name, result.path and ("%s %s"):format(result.source, short(result.path)) or result.reason or "missing"))
    end
    vim.notify(#lines > 0 and table.concat(lines, "\n") or "Resolved again", vim.log.levels.INFO, { title = title })
  end)
end

---@param result tools.Result
---@param roles string[]
local function format_tool(result, roles)
  local where = result.path and short(result.path) or (result.reason or "missing")
  if not result.path and result.install and result.install.kind ~= "none" then
    where = ("%s -> %s"):format(where, describe(result.install, result.root))
  end
  return ("%s %-28s %-12s %s  [%s]"):format(result.path and "✓" or "✗", result.name, result.source, where, table.concat(roles, ", "))
end

local choice_text = { use = "use + install", installed = "installed only", global = "global only" }

--- Lists the current buffer's tools with where each binary comes from, with install / retry / restart actions.
---@param buf? integer
function M.open(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local root, ft = tools.root(buf), vim.bo[buf].filetype
  local names, roles, servers = needed(buf)
  tools.project(root, function(project)
    tools.resolve_all(names, root, function(results)
      local items = {}
      for _, name in ipairs(names) do
        table.insert(items, { result = results[name], text = format_tool(results[name], roles[name]) })
      end
      if #project.configs > 0 then
        local choice = project.untrusted and "untrusted, global only" or choice_text[project.choice] or "not answered"
        table.insert(items, { project = project, text = ("Project config %s: %s (change)"):format(short(project.configs[1]), choice) })
      end
      table.insert(items, { retry = true, text = ("Retry: resolve every tool in %s again"):format(short(root)) })

      local prompt = ("Tools for %s in %s"):format(ft ~= "" and ft or "this buffer", short(root))
      vim.ui.select(items, { prompt = prompt, kind = "tools", format_item = function(item) return item.text end }, function(item)
        if not item then
          return
        elseif item.retry then
          return retry(root, names)
        elseif item.project then
          return M.ask_project(item.project, function() end, true)
        end
        M.actions(item.result, buf, vim.tbl_filter(function(server) return catalog.binary("server", server) == item.result.name end, servers))
      end)
    end)
  end)
end

--- The actions for one tool: install (when missing and installable), retry, restart its servers (when found).
---@param result tools.Result
---@param buf integer
---@param servers string[] servers this tool runs for buf's filetype
function M.actions(result, buf, servers)
  local root = result.root
  local actions = {}
  if not result.path and result.install and result.install.kind ~= "none" then
    local label = describe(result.install, root)
    table.insert(actions, { text = "Install: " .. label, run = function() install({ result.name }, root, label) end })
  end
  table.insert(actions, { text = "Retry: resolve it again", run = function() retry(root, { result.name }) end })
  -- A server whose binary is missing cannot start, so there is nothing to restart
  if #servers > 0 and result.path then
    table.insert(actions, { text = "Restart " .. table.concat(servers, ", "), run = function() M.restart(servers, buf) end })
  end
  local prompt = ("%s: %s"):format(result.name, result.path and short(result.path) or (result.reason or "missing"))
  vim.ui.select(actions, { prompt = prompt, kind = "tools.actions", format_item = function(item) return item.text end }, function(item)
    if item then
      item.run()
    end
  end)
end

local subcommands = {
  --- Installs everything the current buffer's tools are missing
  install = function(buf)
    local root = tools.root(buf)
    local names = needed(buf)
    tools.resolve_all(names, root, function(results)
      local missing = vim.tbl_filter(function(name) return not results[name].path and (results[name].install or {}).kind ~= "none" end, names)
      if #missing == 0 then
        return vim.notify("Nothing to install", vim.log.levels.INFO, { title = title })
      end
      install(missing, root, describe_all(vim.tbl_map(function(name) return results[name].install end, missing), root))
    end)
  end,
  retry = function(buf) retry(tools.root(buf), (needed(buf))) end,
  restart = function(buf)
    local _, _, servers = needed(buf)
    if #servers == 0 then
      return vim.notify("No servers for this filetype", vim.log.levels.WARN, { title = title })
    end
    M.restart(servers, buf)
  end,
  project = function(buf)
    tools.project(tools.root(buf), function(project)
      if #project.configs == 0 then
        return vim.notify("No project mise config for this buffer", vim.log.levels.INFO, { title = title })
      end
      M.ask_project(project, function() end, true)
    end)
  end,
}

function M.setup()
  local group = vim.api.nvim_create_augroup("tools.ux", { clear = true })
  local function has_ui() return #vim.api.nvim_list_uis() > 0 end

  vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
    group = group,
    callback = function(ev)
      if not has_ui() then
        return
      end
      -- After the FileType handlers, so conform, nvim-lint and the servers are set up for this buffer
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(ev.buf) then
          return
        end
        local info = tracked[ev.buf]
        if not info or info.ft ~= vim.bo[ev.buf].filetype then
          track(ev.buf)
        end
        if ev.buf == vim.api.nvim_get_current_buf() then
          M.check(ev.buf)
        end
      end)
    end,
  })
  -- Files opened at startup get FileType before the UI is there
  vim.api.nvim_create_autocmd("UIEnter", {
    group = group,
    callback = function()
      vim.schedule(function()
        local buf = vim.api.nvim_get_current_buf()
        track(buf)
        M.check(buf)
      end)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    callback = function(ev)
      tracked[ev.buf], checked[ev.buf] = nil, nil
    end,
  })
  -- A saved mise config drops the answer remembered for it (tools refreshes on the same write): ask again here,
  -- and in other buffers as they are entered
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = tools.config_patterns,
    callback = function(ev)
      checked = {}
      -- After tools' own handler, which drops the cached project
      vim.schedule(function()
        if ev.buf == vim.api.nvim_get_current_buf() then
          M.check(ev.buf)
        end
      end)
    end,
  })

  vim.api.nvim_create_user_command("Tools", function(opts)
    local buf = vim.api.nvim_get_current_buf()
    local sub = opts.fargs[1]
    if not sub then
      return M.open(buf)
    elseif not subcommands[sub] then
      return vim.notify("Unknown :Tools subcommand " .. sub, vim.log.levels.ERROR, { title = title })
    end
    subcommands[sub](buf)
  end, {
    nargs = "?",
    desc = "Tools for this buffer: binaries, sources, install / retry / restart",
    complete = function(lead)
      return vim.tbl_filter(function(sub) return vim.startswith(sub, lead) end, vim.tbl_keys(subcommands))
    end,
  })
end

return M
