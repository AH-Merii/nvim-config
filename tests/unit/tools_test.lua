-- The tool resolver through its interface (require("tools")), with the fake backend for mise. Project env dirs and
-- the system PATH are real throwaway dirs. Rules: docs/mise-tooling-decisions.md, "Resolution order" and cases 9, 10.
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local fake = require("fake_backend")
local tools = require("tools")

local tmp = h.tmpdir()
-- The answers to the project prompt are real local state; keep them out of the live state dir
require("tools.state").file = tmp .. "/state/projects.json"

-- git stays reachable on the system PATH each case sets: project-only installs use it (D100)
local git_bin = vim.fn.exepath("git")

local n = 0
--- A fresh project root and system PATH dir holding git, and the resolver on a fake backend built from spec.
---@param spec table fake_backend's opts; spec.projects is keyed "root", replaced by the new root
---@return string root, string system, table backend
local function setup(spec)
  n = n + 1
  local root = ("%s/%d/project"):format(tmp, n)
  local system = ("%s/%d/system"):format(tmp, n)
  vim.fn.mkdir(root, "p")
  vim.fn.mkdir(system, "p")
  vim.uv.fs_symlink(git_bin, system .. "/git")
  vim.env.PATH = system
  local backend = fake({ global = spec.global, global_pins = spec.global_pins, projects = spec.project and { [root] = spec.project } or nil })
  tools.setup({ backend = backend })
  return root, system, backend
end

local function resolve(name, root)
  return h.await(function(done) tools.resolve(name, root, done) end)
end
local function version(result)
  return h.await(function(done) tools.version(result, done) end)
end
--- Where the result came from and the version its copy reports.
local function found(name, root)
  local result = resolve(name, root)
  return { source = result.source, version = version(result) }
end
local function answer(root, choice)
  h.await(function(done) tools.set_choice(root, choice, done) end)
end

h.case("the first layer holding a tool wins: project env, accepted project mise, global mise, system", function()
  -- Each layer holds ruff in its own version, so the version says which copy was picked
  local layers = {
    { source = "project-env", version = "0.16.0" },
    { source = "project-mise", version = "0.15.0" },
    { source = "global-mise", version = "0.17.0" },
    { source = "system", version = "0.14.0" },
  }
  for first = 1, #layers + 1 do
    local has = {}
    for i = first, #layers do
      has[layers[i].source] = true
    end
    local root, system = setup({
      global = has["global-mise"] and { ruff = "0.17.0" } or nil,
      project = has["project-mise"] and { ruff = "0.15.0" } or nil,
    })
    if has["project-env"] then
      h.bin(root .. "/.venv/bin/ruff", "0.16.0")
    end
    if has["system"] then
      h.bin(system .. "/ruff", "0.14.0")
    end
    if has["project-mise"] then
      answer(root, "installed")
    end
    local want = layers[first] or { source = "missing" }
    h.eq(found("ruff", root), want, ("ruff with layers from %s down"):format(want.source))
  end
end)

h.case("a project env above the root is found", function()
  local root = setup({ global = { ruff = "0.17.0" } })
  h.bin(vim.fs.dirname(root) .. "/.venv/bin/ruff", "0.16.0")
  h.eq(found("ruff", root), { source = "project-env", version = "0.16.0" })
end)

h.case("an unaccepted project mise config isn't used", function()
  for _, choice in ipairs({ false, "global", "installed", "use" }) do
    local root = setup({ global = { ruff = "0.17.0" }, project = { ruff = "0.15.0" } })
    if choice then
      answer(root, choice)
    end
    local want = (choice == "installed" or choice == "use") and { source = "project-mise", version = "0.15.0" }
      or { source = "global-mise", version = "0.17.0" }
    h.eq(found("ruff", root), want, ("ruff with the project config answered %s"):format(choice or "never"))
  end
end)

h.case("a copy below the minimum version is skipped", function()
  -- tsc's catalog entry needs 7 or newer (tools/catalog.lua)
  local root = setup({ global = { node = "22.0.0", tsc = "7.0.2" } })
  h.bin(root .. "/node_modules/.bin/tsc", "5.9.3")
  local result = resolve("tsc", root)
  h.eq({ source = result.source, version = result.version }, { source = "global-mise", version = "7.0.2" }, "the copy used")
  h.eq(result.skipped, { { source = "project-env", version = "5.9.3" } }, "the copies skipped")

  root = setup({ global = { node = "22.0.0", tsc = "7.0.2" } })
  h.bin(root .. "/node_modules/.bin/tsc", "7.0.0")
  h.eq(found("tsc", root), { source = "project-env", version = "7.0.0" }, "a copy at the minimum")

  root = setup({ global = { node = "22.0.0" } })
  h.bin(root .. "/node_modules/.bin/tsc", "5.9.3")
  result = resolve("tsc", root)
  h.eq(
    { source = result.source, install = result.install },
    -- node_modules makes the root a project, so the project-only install is offered too (D100)
    {
      source = "missing",
      install = { kind = "global", spec = "npm:typescript@latest", project_only = { kind = "local", spec = "npm:typescript@latest" } },
    },
    "no copy new enough"
  )
end)

--- Runs tools.install for names as if a UI were attached (installs never run headless) and returns its callback's args.
local function install(names, root)
  local list_uis = vim.api.nvim_list_uis
  vim.api.nvim_list_uis = function() return { {} } end
  local ok, errs, failed = h.await(function(done) tools.install(names, root, done) end)
  vim.api.nvim_list_uis = list_uis
  return { ok = ok, errs = errs, failed = failed }
end

h.case("a tool missing its runtime installs both together", function()
  local root, _, backend = setup({})
  local result = resolve("yaml-language-server", root)
  h.eq(result.install, { kind = "global", spec = "npm:yaml-language-server@latest", runtime = "node" }, "the install offered")
  h.eq(install({ "yaml-language-server" }, root), { ok = true, errs = {}, failed = {} }, "the install's outcome")
  h.eq(backend.calls, { { "use_global", { "npm:yaml-language-server@latest", "node@lts" } } }, "the backend's installs")
  h.eq(resolve("yaml-language-server", root).source, "global-mise", "the source once installed")
end)

h.case("a tool whose runtime went missing installs only the runtime", function()
  local root, _, backend = setup({ global = { ["yaml-language-server"] = "1.25.0" } })
  local result = resolve("yaml-language-server", root)
  h.eq({ source = result.source, install = result.install }, { source = "missing", install = { kind = "global", runtime = "node" } }, "the result")
  install({ "yaml-language-server" }, root)
  h.eq(backend.calls, { { "use_global", { "node@lts" } } }, "the backend's installs")
  h.eq(resolve("yaml-language-server", root).source, "global-mise", "the source once node is in")
end)

-- D99: mise reads the global config.toml after conf.d and lets it win (https://mise.jdx.dev/configuration.html), so
-- with a pin there that isn't installed, a "latest" written to the config's own file leaves the tool missing
h.case("a version the global config pins but isn't installed is what Install installs, and the tool is found", function()
  local root, _, backend = setup({ global_pins = { shfmt = "3.10.0" } })
  local result = resolve("shfmt", root)
  h.eq(
    { source = result.source, install = result.install },
    { source = "missing", install = { kind = "pinned", spec = "shfmt@3.10.0", version = "3.10.0", config = "config.toml", scope = "global" } },
    "the result"
  )
  h.eq(install({ "shfmt" }, root), { ok = true, errs = {}, failed = {} }, "the install's outcome")
  h.eq(backend.calls, { { "install", { "shfmt@3.10.0" } } }, "the backend's installs: no write to the config's own file")
  h.eq(found("shfmt", root), { source = "global-mise", version = "3.10.0" }, "a fresh resolve")
end)

h.case("without a global pin that isn't installed, the offer is the global install into the config's own file", function()
  local root = setup({})
  h.eq(resolve("shfmt", root).install, { kind = "global", spec = "shfmt@latest" }, "no global pin")
  -- The project's own pin is what mise uses in the project, so it comes before the global one
  root = setup({ project = { shfmt = { version = "3.8.0", installed = false } }, global_pins = { shfmt = "3.10.0" } })
  answer(root, "installed")
  local inst = resolve("shfmt", root).install
  h.eq({ inst.kind, inst.spec, inst.scope }, { "pinned", "shfmt@3.8.0" }, "a project pin as well, in use")
end)

-- D100: in a project, a missing tool the project doesn't pin can be installed for the project only, into the root's
-- mise.local.toml, which is then kept out of git. git is real, in throwaway repos, with no system or user config.
vim.env.GIT_CONFIG_NOSYSTEM, vim.env.GIT_CONFIG_GLOBAL, vim.env.GIT_CEILING_DIRECTORIES = "1", tmp .. "/gitconfig", tmp
h.write(tmp .. "/gitconfig", { "[user]", "name = t", "email = t@t" })

---@param dir string
---@param ... string git args
local function git(dir, ...)
  local out = vim.system({ git_bin, ... }, { cwd = dir, text = true }):wait()
  assert(out.code == 0, out.stderr)
end

-- Every notification from here on, to see the .gitignore toast: { text, level }
local notes = {} ---@type { [1]: string, [2]: integer }[]
vim.notify = function(msg, level) table.insert(notes, { msg, level }) end
local INFO, WARN, ERROR = vim.log.levels.INFO, vim.log.levels.WARN, vim.log.levels.ERROR
local toast = { { "Added mise.local.toml to .gitignore", INFO } }

--- Runs tools.apply for items as if a UI were attached and returns its callback's args.
local function apply(items, root)
  local list_uis = vim.api.nvim_list_uis
  vim.api.nvim_list_uis = function() return { {} } end
  local ok, errs, failed = h.await(function(done) tools.apply(items, root, done) end)
  vim.api.nvim_list_uis = list_uis
  return { ok = ok, errs = errs, failed = failed }
end

---@param path string
---@return string? contents, nil when there is no such file
local function contents(path)
  local ok, lines = pcall(vim.fn.readfile, path, "b")
  return ok and table.concat(lines, "\n") or nil
end

--- Installs name (default ruff) for root's project only; returns what the gitignore file (default root's .gitignore)
--- holds afterwards, nil when there is none, and the notifications it gave.
---@param root string
---@param gitignore? string
---@param name? string
local function install_here(root, gitignore, name)
  name = name or "ruff"
  local result = resolve(name, root)
  h.ok(result.install and result.install.project_only, "no project-only offer: " .. vim.inspect(result.install))
  notes = {}
  h.eq(apply({ { name = name, install = result.install.project_only } }, root), { ok = true, errs = {}, failed = {} }, "the install")
  return contents(gitignore or (root .. "/.gitignore")), notes
end

---@param root string
---@return tools.Choice?
local function choice(root) return h.await(function(done) tools.project(root, done) end).choice end

h.case("in a project, a missing tool it doesn't pin is offered for the project only, and resolves from there", function()
  for _, kind in ipairs({ "git repo", "pyproject.toml", "config answered installed", "config answered use" }) do
    local answered = kind:match("^config answered (%w+)")
    local root, _, backend = setup({ project = answered and { stylua = "2.0.0" } or nil })
    if kind == "git repo" then
      git(root, "init", "-q")
    elseif kind == "pyproject.toml" then
      h.write(root .. "/pyproject.toml", { "[project]" })
    else
      -- Answering "use" through tools would trust and install the project, which the fake backend doesn't do
      local configs = h.await(function(done) tools.project(root, done) end).configs
      require("tools.state").set(configs, answered)
      tools.refresh()
    end
    local inst = resolve("ruff", root).install
    h.eq(inst, { kind = "global", spec = "ruff@latest", project_only = { kind = "local", spec = "ruff@latest" } }, kind .. ": the offer")
    install_here(root)
    h.eq(backend.calls, { { "use_local", root, { "ruff@latest" } } }, kind .. ": the backend's installs")
    h.eq(found("ruff", root), { source = "project-mise", version = "1.0.0" }, kind .. ": a fresh resolve")
    if answered then
      h.eq({ choice(root), found("stylua", root) }, { answered, { source = "project-mise", version = "2.0.0" } }, kind .. ": the answer and the other pin")
    end
  end
end)

h.case("a project-only install carries the prompt's answer over only to the configs it saw plus mise.local.toml", function()
  -- A terminal `git pull` can add, change or remove a project config after the last scan, or during the install
  local pulls = {
    { "a new tools-only config", nil, function(pins) pins.stylua = "2.0.0" end },
    { "a new untrusted config", nil, function(_, backend, root) backend.untrusted[root] = "mise.toml" end },
    { "a changed config", "use", function(pins) pins.stylua = "2.1.0" end },
    -- mise's paranoid mode refuses even the file the install wrote
    { "an untrusted mise.local.toml", nil, function(_, backend, root) backend.untrusted[root] = "mise.local.toml" end },
  }
  ---@param answered? tools.Choice the answer for a mise.toml pinning stylua 2.0.0; nil for no config
  local function offered(answered)
    local pins = answered and { stylua = "2.0.0" } or {}
    local root, _, backend = setup({ project = pins })
    git(root, "init", "-q")
    if answered then
      require("tools.state").set(h.await(function(done) tools.project(root, done) end).configs, answered)
      tools.refresh()
    end
    local offer = resolve("ruff", root).install
    h.ok(offer and offer.project_only, "no project-only offer: " .. vim.inspect(offer))
    return root, pins, backend, offer.project_only
  end
  for _, when in ipairs({ "after the offer", "during the install" }) do
    for _, pull in ipairs(pulls) do
      local root, pins, backend, inst = offered(pull[2])
      local function run() pull[3](pins, backend, root) end
      if when == "after the offer" then
        run()
      else
        backend.during_use_local = run
      end
      local what = ("%s %s"):format(pull[1], when)
      h.eq(apply({ { name = "ruff", install = inst } }, root).ok, true, what .. ": the install")
      h.eq(choice(root), nil, what .. ": the answer")
    end
  end
  -- A config gone by the install leaves only the file the install wrote
  local root, pins, _, inst = offered("use")
  pins.stylua = nil
  vim.fn.delete(root .. "/mise.toml")
  h.eq(apply({ { name = "ruff", install = inst } }, root).ok, true, "a removed config: the install")
  h.eq({ choice(root), found("ruff", root).source }, { "installed", "project-mise" }, "a removed config")
end)

h.case("with a global pin that isn't installed, a project also gets the project-only offer", function()
  local root = setup({ global_pins = { shfmt = "3.10.0" } })
  git(root, "init", "-q")
  h.eq(resolve("shfmt", root).install, {
    kind = "pinned",
    spec = "shfmt@3.10.0",
    version = "3.10.0",
    config = "config.toml",
    scope = "global",
    project_only = { kind = "local", spec = "shfmt@latest" },
  }, "the offer")
  install_here(root, nil, "shfmt")
  h.eq(found("shfmt", root), { source = "project-mise", version = "1.0.0" }, "a fresh resolve")
end)

h.case("no project-only offer outside a project, in HOME, where its config isn't in use, or with a missing runtime", function()
  local root = setup({})
  h.eq(resolve("ruff", root).install, { kind = "global", spec = "ruff@latest" }, "outside a project")
  -- A ~/.venv or a stray ~/node_modules makes HOME the root; a mise.local.toml there would apply everywhere under it,
  -- as it would in a dir above HOME. HOME may be a link to the dir the root names (a home on another disk, say), and
  -- an empty HOME can't be told apart from any root
  local home = vim.env.HOME
  for _, where in ipairs({ "HOME with a .venv", "HOME a link to the root", "HOME below the root", "HOME empty" }) do
    root = setup({})
    vim.fn.mkdir(root .. "/.venv", "p")
    vim.env.HOME = ({ ["HOME with a .venv"] = root, ["HOME a link to the root"] = root .. "-link", ["HOME below the root"] = root .. "/me", ["HOME empty"] = "" })[where]
    if where == "HOME a link to the root" then
      vim.uv.fs_symlink(root, vim.env.HOME)
    elseif where == "HOME below the root" then
      vim.fn.mkdir(vim.env.HOME, "p")
    end
    local ok, result = pcall(resolve, "ruff", root)
    vim.env.HOME = home
    assert(ok, result)
    h.eq(result.install, { kind = "global", spec = "ruff@latest" }, where)
  end
  for _, answer_with in ipairs({ false, "global" }) do
    root = setup({ project = { stylua = "2.0.0" } })
    if answer_with then
      answer(root, answer_with)
    end
    h.eq(resolve("ruff", root).install, { kind = "global", spec = "ruff@latest" }, ("a project config answered %s"):format(answer_with or "never"))
  end
  root = setup({})
  git(root, "init", "-q")
  h.eq(resolve("yaml-language-server", root).install, { kind = "global", spec = "npm:yaml-language-server@latest", runtime = "node" }, "no node")
  -- `mise config set` can't write a key with a dot (tools.go:golang.org/...) or a bracket (ubi:o/r[exe=x])
  root = setup({ global = { go = "1.25.0" } })
  git(root, "init", "-q")
  h.eq(resolve("gopls", root).install, { kind = "global", spec = "go:golang.org/x/tools/gopls@latest" }, "a mise name with a dot")
  require("tools.catalog").tools["bracketed-tool"] = { spec = "ubi:owner/repo[exe=bracketed-tool]" }
  local bracketed = resolve("bracketed-tool", root).install
  require("tools.catalog").tools["bracketed-tool"] = nil
  h.eq(bracketed, { kind = "global", spec = "ubi:owner/repo[exe=bracketed-tool]@latest" }, "a mise name with a bracket")
end)

h.case("a project that pins the tool gets its pinned version offered, not a project-only install", function()
  local root = setup({ project = { ruff = { version = "0.15.0", installed = false } } })
  git(root, "init", "-q")
  answer(root, "installed")
  local inst = resolve("ruff", root).install
  h.eq({ inst.kind, inst.spec, inst.project_only, inst.global.project_only }, { "pinned", "ruff@0.15.0" }, "the offer")
end)

h.case("in a git repo, the repo's .gitignore gains one mise.local.toml line when it isn't ignored, with a toast", function()
  for _, before in ipairs({ false, "node_modules/\n", "node_modules/" }) do
    local root = setup({})
    git(root, "init", "-q")
    if before then
      vim.fn.writefile(vim.split(before, "\n", { plain = true }), root .. "/.gitignore", "b")
    end
    local after, said = install_here(root)
    h.eq({ after, said }, { (before and "node_modules/\n" or "") .. "mise.local.toml\n", toast }, vim.inspect(before))
  end
  -- Projects in subdirectories of a repo: the line goes in the repo's top-level .gitignore, once
  local repo = setup({})
  git(repo, "init", "-q")
  for _, sub in ipairs({ "a", "b" }) do
    h.write(("%s/%s/pyproject.toml"):format(repo, sub), { "[project]" })
    local after, said = install_here(repo .. "/" .. sub, repo .. "/.gitignore")
    h.eq(
      { after, said, contents(("%s/%s/.gitignore"):format(repo, sub)) },
      { "mise.local.toml\n", sub == "a" and toast or {} },
      "a project in " .. sub .. "/"
    )
  end
end)

h.case("nothing changes in .gitignore, and no toast, when git already ignores mise.local.toml, tracks it, or there is no git", function()
  for _, how in ipairs({ "its name", "*.local.toml", "the global excludes file", "!mise.local.toml", "tracked", "no git" }) do
    local root = setup({})
    h.write(root .. "/pyproject.toml", { "[project]" })
    local excludes = tmp .. "/excludes"
    h.write(tmp .. "/gitconfig", { "[user]", "name = t", "email = t@t", "[core]", "excludesFile = " .. excludes })
    h.write(excludes, how == "the global excludes file" and { "mise.local.toml" } or { "" })
    if how ~= "no git" then
      git(root, "init", "-q")
    end
    local before = ({ ["its name"] = "mise.local.toml", ["*.local.toml"] = "*.local.toml", ["!mise.local.toml"] = "!mise.local.toml" })[how]
    if before then
      h.write(root .. "/.gitignore", { before })
    end
    if how == "tracked" then
      h.write(root .. "/mise.local.toml", { "[tools]" })
      git(root, "add", "mise.local.toml")
      git(root, "commit", "-qm", "local config")
    end
    local after, said = install_here(root)
    h.eq({ after, said }, { before and (before .. "\n") or nil, {} }, how)
  end
  h.write(tmp .. "/gitconfig", { "[user]", "name = t", "email = t@t" })
end)

h.case("git's repo-locating environment and settings never move the .gitignore edit outside the project's repo", function()
  -- A bare-repo dotfiles setup exports GIT_DIR and GIT_WORK_TREE; git would then answer for that repo instead
  local other = setup({})
  git(other, "init", "-q", "--bare", other .. "/dotfiles.git")
  for _, repo in ipairs({ true, false }) do
    local root = setup({})
    h.write(root .. "/pyproject.toml", { "[project]" })
    if repo then
      git(root, "init", "-q")
    end
    vim.env.GIT_DIR, vim.env.GIT_WORK_TREE = other .. "/dotfiles.git", other
    local ok, after, said = pcall(install_here, root)
    vim.env.GIT_DIR, vim.env.GIT_WORK_TREE = nil, nil
    assert(ok, after)
    local what = repo and "a repo of its own" or "no repo"
    h.eq({ after, said, contents(other .. "/.gitignore") }, { repo and "mise.local.toml\n" or nil, repo and toast or {} }, what)
  end
  -- core.worktree can put the work tree elsewhere, here the dir above the project's .git
  local parent = setup({})
  local root = parent .. "/project"
  vim.fn.mkdir(root, "p")
  git(root, "init", "-q")
  git(root, "config", "core.worktree", parent)
  local after, said = install_here(root)
  h.eq({ after, contents(parent .. "/.gitignore") }, {}, "core.worktree: the .gitignore files")
  h.ok(#said == 1 and said[1][2] == WARN and vim.startswith(said[1][1], "Not adding mise.local.toml to .gitignore: "), vim.inspect(said))
  -- A dotfiles repo checked out in HOME holds every project below it that has no repo of its own
  root = setup({})
  local home, user_home = vim.fs.dirname(root), vim.env.HOME
  git(home, "init", "-q")
  h.write(root .. "/pyproject.toml", { "[project]" })
  vim.env.HOME = home
  local ok
  ok, after, said = pcall(install_here, root)
  vim.env.HOME = user_home
  assert(ok, after)
  h.eq({ after, contents(home .. "/.gitignore") }, {}, "a repo in HOME: the .gitignore files")
  h.ok(#said == 1 and said[1][2] == WARN and vim.startswith(said[1][1], "Not adding mise.local.toml to .gitignore: "), vim.inspect(said))
end)

h.case("a .gitignore that can't be written or is a link is left alone, and a notification says so", function()
  -- Read-only: an error instead of the toast
  local root = setup({})
  git(root, "init", "-q")
  h.write(root .. "/.gitignore", { "node_modules/" })
  vim.uv.fs_chmod(root .. "/.gitignore", tonumber("444", 8))
  local after, said = install_here(root)
  h.eq(after, "node_modules/\n", "a read-only .gitignore")
  h.ok(#said == 1 and said[1][2] == ERROR and vim.startswith(said[1][1], "Couldn't add mise.local.toml to .gitignore: "), vim.inspect(said))
  -- A link (a stowed .gitignore, say): editing it would change a file outside the repo
  root = setup({})
  git(root, "init", "-q")
  local target = root .. "/../dotfiles-gitignore"
  h.write(target, { "node_modules/" })
  vim.uv.fs_symlink(target, root .. "/.gitignore")
  after, said = install_here(root, target)
  h.eq(after, "node_modules/\n", "the link's target")
  h.ok(#said == 1 and said[1][2] == WARN and vim.startswith(said[1][1], "Not adding mise.local.toml to .gitignore: "), vim.inspect(said))
end)

h.finish()
