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

local n = 0
--- A fresh project root and system PATH dir, and the resolver on a fake backend built from spec.
---@param spec table fake_backend's opts; spec.projects is keyed "root", replaced by the new root
---@return string root, string system, table backend
local function setup(spec)
  n = n + 1
  local root = ("%s/%d/project"):format(tmp, n)
  local system = ("%s/%d/system"):format(tmp, n)
  vim.fn.mkdir(root, "p")
  vim.fn.mkdir(system, "p")
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
    { source = "missing", install = { kind = "global", spec = "npm:typescript@latest" } },
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

h.finish()
