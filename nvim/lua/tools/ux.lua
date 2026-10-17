-- The install prompts, the :Tools view and the statusline indicator for the tool resolver (tools).
-- Asks once per project mise config that pins tools (use + install / installed only / global only), then once per missing tool
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

--- The catalog binaries buf's filetype runs (servers, formatters, linters, and what they call), and per binary its
--- roles there in plain words, e.g. { "lsp", "formatter", "linter" }.
---@param buf integer
---@return string[] names, table<string, string[]> roles, string[] servers
local function needed(buf)
  local found = require("lang").of(vim.bo[buf].filetype)
  if not found then
    return {}, {}, {}
  end
  local names, roles = catalog.needed(found)
  return names, roles, found.servers
end

--------------------------------------------------------------------------------
-- Words
--------------------------------------------------------------------------------

--- "a", "a and b", "a, b and c"
---@param list string[]
local function join(list)
  if #list <= 1 then
    return list[1] or ""
  end
  return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

--- At most three items, then "+N more".
---@param list string[]
---@return string[]
local function capped(list)
  if #list <= 3 then
    return list
  end
  local out = vim.list_slice(list, 1, 3)
  table.insert(out, ("+%d more"):format(#list - 3))
  return out
end

--- A mise tool's name without its backend: "pypi:pyrefly" -> "pyrefly", "npm:@fsouza/prettierd" -> "prettierd".
---@param tool string
local function tool_label(tool) return (tool:gsub("^[%w-]+:", ""):match("[^/]+$")) or tool end

---@param n integer
---@param one string
---@param many string
local function count(n, one, many) return n == 1 and one or many end

--- The project's pins that tools in names use (all of them when names is nil), sorted, and the file names of the
--- configs that pin them (the nearest config when none does).
---@param project tools.Project
---@param names? string[]
---@return string[] pins e.g. { "pyrefly 1.3.0", "ruff 0.15.0" }, string config e.g. "mise.toml"
local function pin_list(project, names)
  local specs = names and {} or nil
  for _, name in ipairs(names or {}) do
    local spec = (catalog.tools[name] or {}).spec
    if spec then
      specs[spec] = true
    end
  end
  local pins, files = {}, {}
  local tools_ = vim.tbl_keys(project.pins)
  table.sort(tools_, function(a, b) return tool_label(a) < tool_label(b) end)
  for _, tool in ipairs(tools_) do
    if not specs or specs[tool] then
      local pin = project.pins[tool]
      table.insert(pins, ("%s %s"):format(tool_label(tool), pin.version))
      add(files, vim.fs.basename(pin.source))
    end
  end
  local config = #files > 0 and join(files) or vim.fs.basename(project.untrusted or project.configs[1] or "mise.toml")
  return pins, config
end

---@param pins string[]
local function in_parens(pins) return #pins > 0 and (" (%s)"):format(table.concat(capped(pins), ", ")) or "" end

local source_words = { ["project-mise"] = "project mise", ["global-mise"] = "global mise", system = "system" }

--- Where a found tool comes from, in words: "global mise", "project .venv", "rustup", ...
---@param result tools.Result
local function source_label(result)
  local entry = catalog.tools[result.name] or {}
  if entry.component then
    return "rustup"
  elseif result.source == "project-env" then
    return "project " .. tools.env_dir(entry, result.path)
  end
  return source_words[result.source] or result.source
end

--- "(project's 5.9.3 is too old)" for a copy passed over by the version check; "" when none was.
---@param result tools.Result
local function skipped_note(result)
  local first = (result.skipped or {})[1]
  if not first then
    return ""
  end
  local owner = (first.source == "project-env" or first.source == "project-mise") and "project's"
    or first.source == "global-mise" and "global mise's"
    or "system's"
  return (" (%s %s is too old)"):format(owner, first.version or "copy")
end

--- The tool as a prompt names it: "ruff", or "tsc 7 or newer (project has 5.9.3)" when copies were too old.
---@param result tools.Result
local function needs_label(result)
  local entry = catalog.tools[result.name] or {}
  local first = (result.skipped or {})[1]
  if not (entry.min and first) then
    return result.name
  end
  local owner = (first.source == "project-env" or first.source == "project-mise") and "project" or "global"
  return ("%s %s or newer (%s has %s)"):format(result.name, entry.min, owner, first.version or "an older one")
end

--- What picking an install does, as a menu entry or prompt option. subject: "it" or "them" in a prompt, nil in a
--- tool's own menu.
---@param inst tools.Install
---@param subject? string
---@param names? string[] for a rustup component that needs rust first
local function install_text(inst, subject, names)
  local it = subject and (subject .. " ") or ""
  if inst.kind == "global" then
    if inst.runtime == "rust" and inst.component then
      return ("Install Rust globally with mise, then add %s"):format(join(names or { inst.component }))
    elseif inst.runtime and not inst.spec then
      return ("Install %s globally with mise"):format(inst.runtime)
    elseif inst.runtime then
      return ("Install %sand %s globally with mise"):format(subject and it or "it ", inst.runtime)
    end
    return ("Install %sglobally with mise"):format(it)
  elseif inst.kind == "component" then
    return ("Install %swith rustup%s"):format(it, inst.toolchain and (" (toolchain %s)"):format(inst.toolchain) or "")
  elseif inst.kind == "pinned" then
    return ("Install %s for this project with mise"):format(inst.version)
  elseif inst.kind == "project" then
    return ("Install %sfor this project with mise (trusts %s)"):format(it, inst.config or "mise.toml")
  end
  return ""
end

local not_now = "Not now (won't ask again; install later from :Tools)"

--------------------------------------------------------------------------------
-- Pickers
--------------------------------------------------------------------------------

--- vim.ui.select sized to its rows: snacks' select layout is 50% of the screen, 80 to 100 columns, which cut the
--- rows off; this asks for the width of the longest row or title instead, up to the screen's width.
---@param items table[] each with .text
---@param opts { prompt: string, kind: string }
---@param on_choice fun(item?: table)
local function select(items, opts, on_choice)
  local widest = vim.fn.strdisplaywidth(opts.prompt) + 4 -- the title sits in the border, with a space each side
  for _, item in ipairs(items) do
    -- snacks puts "<n>. " before each row
    widest = math.max(widest, vim.fn.strdisplaywidth(item.text) + #tostring(#items) + 2)
  end
  local width = math.min(widest + 4, math.max(vim.o.columns - 4, 20)) -- borders and a little air
  vim.ui.select(items, {
    prompt = opts.prompt,
    kind = opts.kind,
    format_item = function(item) return item.text end,
    snacks = { layout = { layout = { width = width, min_width = width, max_width = width } } },
  }, on_choice)
end

--------------------------------------------------------------------------------
-- Installs, with a progress message and the result shown
--------------------------------------------------------------------------------

---@class tools.ux.Progress
---@field names string[] what is installed, e.g. { "pyrefly", "ruff" }
---@field running? string progress text instead of "Installing <names>"
---@field done? string result text instead of "Installed <names>"
---@field failed? string failure text instead of "Couldn't install <names>"

--- Runs an install, showing a progress message while it runs (the statusline's progress) and a notification when it ends.
--- tools refreshes after every install, which fires User ToolsChanged for each tool it moved.
---@param what tools.ux.Progress
---@param start fun(cb: fun(ok: boolean, errs: string[], failed?: string[]))
---@param on_done? fun(ok: boolean)
function M.run_install(what, start, on_done)
  local running = what.running or ("Installing %s"):format(table.concat(what.names, ", "))
  local progress = { kind = "progress", source = "tools", title = title, status = "running" }
  progress.id = vim.api.nvim_echo({ { running } }, false, progress)
  start(function(ok, errs, failed)
    progress.status = ok and "success" or "failed"
    vim.api.nvim_echo({ { running } }, false, progress)
    if ok then
      vim.notify(what.done or ("Installed %s"):format(join(what.names)), vim.log.levels.INFO, { title = title })
    else
      local head = what.failed or ("Couldn't install %s"):format(join(failed and #failed > 0 and failed or what.names))
      vim.notify(("%s\n%s"):format(head, table.concat(errs or {}, "\n")), vim.log.levels.ERROR, { title = title })
    end
    if on_done then
      on_done(ok)
    end
  end)
end

--- The names an install brings in: the tools, and a runtime installed alongside them.
---@param items tools.InstallItem[]
local function installed_names(items)
  local names = {}
  for _, item in ipairs(items) do
    -- Only a runtime is missing: the runtime is what gets installed
    if not (item.install.kind == "global" and item.install.runtime and not item.install.spec and not item.install.component) then
      add(names, item.name)
    end
  end
  for _, item in ipairs(items) do
    local runtime = item.install.runtime
    if runtime then
      add(names, runtime == "rust" and "Rust" or runtime)
    end
  end
  return names
end

---@param items tools.InstallItem[]
---@param root string
---@param on_done? fun(ok: boolean)
local function install(items, root, on_done)
  M.run_install({ names = installed_names(items) }, function(cb) tools.apply(items, root, cb) end, on_done)
end

--------------------------------------------------------------------------------
-- Prompts
--------------------------------------------------------------------------------

--- Uses the project's mise config ("Yes"): trusts it, installs its missing pins, uses them.
---@param project tools.Project
---@param names? string[] the filetype's tools, to name the missing pins it uses first
---@param done? fun()
local function use_project(project, names, done)
  local root = project.root
  local _, config = pin_list(project, names)
  asked["project:" .. root] = true -- set_choice installs; a failure is shown, not offered again
  local missing = vim.tbl_map(tool_label, project.missing)
  M.run_install({
    names = missing,
    running = #missing == 0 and ("Trusting %s"):format(config) or nil,
    done = #missing == 0 and ("Using %s"):format(config) or nil,
    failed = ("Couldn't use %s"):format(config),
  }, function(cb)
    tools.set_choice(root, "use", function(ok, err) cb(ok, { err }) end)
  end, function()
    if done then
      done()
    end
  end)
end

--- The project prompt: whether to use the project's mise config. Calls done when answered, dismissed or not needed.
---@param project tools.Project
---@param done fun()
---@param force? boolean ask even when answered before
---@param names? string[] the filetype's tools: the pins they use are the ones named
function M.ask_project(project, done, force, names)
  -- Keyed by the configs' contents too: an edit drops the remembered answer, so it is asked again
  local key = project.configs[1] and ("project-config:%s:%s"):format(project.configs[1], state.hash(project.configs))
  if not key or (not force and (project.choice or asked[key])) then
    return done()
  end
  asked[key] = true
  local root = project.root
  local pins, config = pin_list(project, names)
  local items, prompt
  if project.untrusted then
    -- mise refuses every call under an untrusted config with [env], so only trusting it makes its pins usable
    prompt = ("Trust this project's %s? (it sets environment variables)"):format(config)
    items = {
      { choice = "use", text = "Yes, trust it and install its tools" },
      { choice = "global", text = "No, use my global tools" },
    }
  else
    prompt = ("Use this project's %s?%s"):format(config, in_parens(pins))
    local missing = capped(vim.tbl_map(tool_label, project.missing))
    items = {
      {
        choice = "use",
        text = #missing > 0 and ("Yes, and install %s (trusts %s)"):format(join(missing), config) or ("Yes (trusts %s)"):format(config),
      },
      { choice = "installed", text = "Only versions already installed" },
      { choice = "global", text = "No, use my global tools" },
    }
  end
  select(items, { prompt = prompt, kind = "tools.project" }, function(item)
    if not item then
      return done()
    elseif item.choice == "use" then
      return use_project(project, names, done)
    end
    tools.set_choice(root, item.choice, function(ok, err)
      if not ok then
        vim.notify(err or "failed", vim.log.levels.ERROR, { title = title })
      end
      done()
    end)
  end)
end

---@param install tools.Install
---@param root string
local function offer_key(install, root)
  if install.kind == "global" then
    return "global:" .. (install.spec or catalog.runtimes[install.runtime].spec)
  elseif install.kind == "component" then
    return "component:" .. install.component
  elseif install.kind == "pinned" then
    return "pinned:" .. install.spec
  end
  return "project:" .. root
end

--- Asks which copy to use where the project env and the project's mise pin hold different versions, once per tool
--- and project. Calls done when answered, dismissed or not needed.
---@param results tools.Result[]
---@param root string
---@param done fun()
local function ask_conflicts(results, root, done)
  local result = table.remove(results, 1)
  if not result then
    return done()
  end
  local conflict, key = result.conflict, "conflict:" .. root .. ":" .. result.name
  if not conflict or conflict.prefer or asked[key] then
    return ask_conflicts(results, root, done)
  end
  asked[key] = true
  local env, pin = conflict.env, conflict.mise
  select({
    { prefer = "env", text = ("Use %s's %s"):format(env.where, env.version) },
    { prefer = "mise", text = ("Use %s's %s"):format(pin.where, pin.version) },
  }, { prompt = ("%s is in %s (%s) and %s (%s)"):format(result.name, env.where, env.version, pin.where, pin.version), kind = "tools.conflict" }, function(
    item
  )
    if not item then
      return ask_conflicts(results, root, done)
    end
    tools.set_prefer(root, result.name, item.prefer, function() ask_conflicts(results, root, done) end)
  end)
end

--- How missing tools are offered together: one prompt per group.
---@param inst tools.Install
local function group_of(inst)
  if inst.kind == "global" and inst.runtime and not inst.spec and not inst.component then
    return "runtime:" .. inst.runtime
  elseif inst.kind == "global" and inst.component then
    return "rust"
  elseif inst.kind == "global" then
    return "global"
  end
  return inst.kind
end

--- One missing-tool prompt for a group of offers. Calls done when answered or dismissed.
---@param ft string
---@param offers { result: tools.Result, key: string }[]
---@param root string
---@param done fun()
local function offer_group(ft, offers, root, done)
  local results = vim.tbl_map(function(o) return o.result end, offers)
  local items = vim.tbl_map(function(r) return { name = r.name, install = r.install } end, results)
  local first = results[1].install
  local subject = count(#results, "it", "them")
  local names = vim.tbl_map(function(r) return r.name end, results)
  local prompt
  local options = {}
  if first.kind == "global" and first.runtime and not first.spec and not first.component then
    prompt = ("%s needs %s to run %s"):format(ft, first.runtime, join(names))
    table.insert(options, { items = items, text = install_text(first) })
  elseif first.kind == "pinned" then
    local pinned = vim.tbl_map(function(r) return ("%s %s"):format(r.name, r.install.version) end, results)
    prompt = ("%s needs %s (pinned by %s)"):format(ft, join(pinned), first.config)
    local globals = vim.tbl_map(function(r) return { name = r.name, install = r.install.global } end, results)
    table.insert(options, { items = items, text = #results == 1 and install_text(first) or "Install them for this project with mise" })
    table.insert(options, { items = globals, text = ("Install %s globally with mise (latest)"):format(subject) })
  else
    prompt = ("%s needs %s"):format(ft, join(vim.tbl_map(needs_label, results)))
    local runtimes = {}
    for _, r in ipairs(results) do
      if r.install.runtime then
        add(runtimes, r.install.runtime)
      end
    end
    local text = install_text(first, subject, names)
    if first.kind == "global" and #runtimes > 0 and not first.component then
      text = ("Install %s and %s globally with mise"):format(subject, join(runtimes))
    end
    table.insert(options, { items = items, text = text })
  end
  table.insert(options, { text = not_now })
  local keys = vim.tbl_map(function(o) return o.key end, offers)
  select(options, { prompt = prompt, kind = "tools.install" }, function(item)
    remember(keys, item ~= nil)
    if item and item.items then
      install(item.items, root)
    end
    done()
  end)
end

--- The missing-tool prompts: what buf's filetype runs that is missing and not offered before, grouped by how it is
--- installed; first, which copy to use where the project env and a mise pin differ.
---@param buf integer
---@param root string
---@param done fun()
local function offer_tools(buf, root, done)
  local names = needed(buf)
  tools.resolve_all(names, root, function(results)
    ask_conflicts(vim.tbl_map(function(name) return results[name] end, names), root, function()
      local groups, order, keys = {}, {}, {}
      for _, name in ipairs(names) do
        local result = results[name]
        local inst = result and not result.path and result.install
        if inst and inst.kind ~= "none" then
          local key = offer_key(inst, root)
          if not offered(key) and not keys[key] then
            keys[key] = true
            local group = group_of(inst)
            if not groups[group] then
              groups[group] = {}
              table.insert(order, group)
            end
            table.insert(groups[group], { result = result, key = key })
          end
        end
      end
      local function next_group()
        local group = table.remove(order, 1)
        if not group or not vim.api.nvim_buf_is_valid(buf) then
          return done()
        end
        offer_group(vim.bo[buf].filetype, groups[group], root, next_group)
      end
      next_group()
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
      M.ask_project(project, function() offer_tools(buf, root, done) end, false, (needed(buf)))
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

---@param servers string[]
---@param buf integer
local function any_running(servers, buf)
  return vim.iter(servers):any(function(server) return #vim.lsp.get_clients({ bufnr = buf, name = server }) > 0 end)
end

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
  vim.notify(("%s %s"):format(#clients > 0 and "Restarted" or "Started", table.concat(servers, ", ")), vim.log.levels.INFO, { title = title })
end

--- Resolves names in root and fetches the versions of the found ones; cb gets results and versions by name.
---@param names string[]
---@param root string
---@param cb fun(results: table<string, tools.Result>, versions: table<string, string>)
local function with_versions(names, root, cb)
  tools.resolve_all(names, root, function(results)
    local versions, left = {}, #names + 1
    local function one()
      left = left - 1
      if left == 0 then
        cb(results, versions)
      end
    end
    for _, name in ipairs(names) do
      tools.version(results[name], function(version)
        versions[name] = version
        one()
      end)
    end
    one()
  end)
end

--- Where a tool stands, for its row: "global mise · 0.17.0", "not installed · install", "needs node · install".
---@param result tools.Result
---@param version? string
local function status_text(result, version)
  if result.path then
    return source_label(result) .. (version and (" · " .. version) or "") .. skipped_note(result)
  end
  local inst = result.install or { kind = "none" }
  if inst.kind == "none" then
    return ("not installed · install %s with your package manager"):format(result.name)
  elseif inst.kind == "global" and inst.runtime and not inst.spec and not inst.component then
    return ("needs %s · install"):format(inst.runtime)
  end
  return "not installed · install" .. skipped_note(result)
end

---@param text string
---@param width integer
local function pad(text, width) return text .. (" "):rep(width - vim.fn.strdisplaywidth(text)) end

--- One row per tool: mark, name and roles padded to the longest of each, then where it comes from.
---@param names string[]
---@param results table<string, tools.Result>
---@param versions table<string, string>
---@param roles table<string, string[]>
---@return string[]
local function rows(names, results, versions, roles)
  local name_w, role_w = 0, 0
  for _, name in ipairs(names) do
    name_w = math.max(name_w, vim.fn.strdisplaywidth(name))
    role_w = math.max(role_w, vim.fn.strdisplaywidth(table.concat(roles[name] or {}, ", ")))
  end
  return vim.tbl_map(function(name)
    local result = results[name]
    return ("%s %s  %s  %s"):format(
      result.path and "✓" or "✗",
      pad(name, name_w),
      pad(table.concat(roles[name] or {}, ", "), role_w),
      status_text(result, versions[name])
    )
  end, names)
end

---@param root string
---@param names string[]
---@param roles table<string, string[]>
local function rescan(root, names, roles)
  tools.refresh(root)
  with_versions(names, root, function(results, versions)
    local lines = rows(names, results, versions, roles)
    vim.notify(#lines > 0 and ("Rescanned tool sources\n" .. table.concat(lines, "\n")) or "Rescanned tool sources", vim.log.levels.INFO, { title = title })
  end)
end

--- The mise.toml row: what picking it does. Hidden when the project has no config that pins tools.
---@param project tools.Project
---@param names string[]
---@return { project: tools.Project, use: boolean, text: string }?
local function project_row(project, names)
  if #project.configs == 0 then
    return nil
  end
  local pins, config = pin_list(project, names)
  if project.untrusted then
    return { project = project, use = true, text = ("Trust %s and use its tools"):format(config) }
  elseif project.choice == "use" then
    return { project = project, use = false, text = ("Stop using %s%s"):format(config, in_parens(pins)) }
  end
  return { project = project, use = true, text = ("Use %s%s · trusts it"):format(config, in_parens(pins)) }
end

--- Lists the current buffer's tools with where each binary comes from; picking one opens its actions.
---@param buf? integer
function M.open(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local root, ft = tools.root(buf), vim.bo[buf].filetype
  local names, roles, servers = needed(buf)
  tools.project(root, function(project)
    with_versions(names, root, function(results, versions)
      local items = {}
      for i, text in ipairs(rows(names, results, versions, roles)) do
        table.insert(items, { result = results[names[i]], version = versions[names[i]], text = text })
      end
      local row = project_row(project, names)
      if row then
        table.insert(items, row)
      end
      table.insert(items, { rescan = true, text = "Rescan tool sources" })

      local prompt = ("Tools for %s in %s"):format(ft ~= "" and ft or "this buffer", short(root))
      select(items, { prompt = prompt, kind = "tools" }, function(item)
        if not item then
          return
        elseif item.rescan then
          return rescan(root, names, roles)
        elseif item.project and item.use then
          return use_project(item.project, names)
        elseif item.project then
          local _, config = pin_list(item.project, names)
          return tools.set_choice(
            root,
            "global",
            function(ok, err)
              vim.notify(
                ok and ("Stopped using %s; using your global tools"):format(config) or (err or "failed"),
                ok and vim.log.levels.INFO or vim.log.levels.ERROR,
                { title = title }
              )
            end
          )
        end
        M.actions(item.result, buf, vim.tbl_filter(function(server) return catalog.binary("server", server) == item.result.name end, servers), item.version)
      end)
    end)
  end)
end

--- The actions for one tool: start or restart its servers, install it (or what it lacks), install the project's
--- pinned version, switch between the project env and the mise pin. A tool with none says where it comes from instead.
---@param result tools.Result
---@param buf integer
---@param servers string[] servers this tool runs for buf's filetype
---@param version? string
function M.actions(result, buf, servers, version)
  local root, name = result.root, result.name
  local actions = {}
  ---@param inst tools.Install
  ---@param text string
  local function offer(inst, text)
    local item = { name = name, install = inst }
    table.insert(actions, { text = text, run = function() install({ item }, root) end })
  end
  -- A server whose binary is missing cannot start, so there is nothing to start or restart
  if #servers > 0 and result.path then
    local verb = any_running(servers, buf) and "Restart" or "Start"
    table.insert(actions, { text = ("%s %s"):format(verb, table.concat(servers, ", ")), run = function() M.restart(servers, buf) end })
  end
  local inst = not result.path and result.install
  if inst and inst.kind ~= "none" then
    offer(inst, install_text(inst))
    if inst.kind == "pinned" and inst.global then
      offer(inst.global, "Install globally with mise (latest)")
    end
  end
  for _, extra in ipairs(result.offers or {}) do
    offer(extra, install_text(extra))
  end
  local conflict = result.conflict
  if conflict and result.path then
    local other, prefer = conflict.mise, "mise"
    if result.source == "project-mise" then
      other, prefer = conflict.env, "env"
    end
    table.insert(actions, {
      text = ("Use %s's %s instead"):format(other.where, other.version),
      run = function() tools.set_prefer(root, name, prefer) end,
    })
  end

  local heading = result.path and ("%s%s · %s"):format(name, version and (" " .. version) or "", source_label(result)) or ("%s · not installed"):format(name)
  if #actions == 0 then
    local where = result.path and short(result.path) or ("install %s with your package manager"):format(name)
    return vim.notify(("%s · %s"):format(heading, where), vim.log.levels.INFO, { title = title })
  end
  select(actions, { prompt = heading, kind = "tools.actions" }, function(item)
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
      local items = {}
      for _, name in ipairs(names) do
        local inst = not results[name].path and results[name].install
        if inst and inst.kind ~= "none" then
          table.insert(items, { name = name, install = inst })
        end
      end
      if #items == 0 then
        return vim.notify("Nothing to install", vim.log.levels.INFO, { title = title })
      end
      install(items, root)
    end)
  end,
  rescan = function(buf)
    local names, roles = needed(buf)
    rescan(tools.root(buf), names, roles)
  end,
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
      M.ask_project(project, function() end, true, (needed(buf)))
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
    desc = "Tools for this buffer: binaries, sources, install / rescan / restart",
    complete = function(lead)
      return vim.tbl_filter(function(sub) return vim.startswith(sub, lead) end, vim.tbl_keys(subcommands))
    end,
  })
end

return M
