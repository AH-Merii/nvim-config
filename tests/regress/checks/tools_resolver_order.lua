-- @desc     the resolver takes a tool from the project env, else the project's mise pins once accepted, else global mise, else the system PATH, never from mise shims, mise install dirs or Mason's bin dir on PATH; a project env copy and a pin of another version are reported and the user's pick wins; a missing pin is offered for the project; a copy too old is skipped and noted; a config pinning nothing is not a project config
-- @areas    tools
-- @budget   30
-- @needs    ruff tsc
local tools = require("tools")

local function put(path, lines, exe)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  if exe then vim.fn.setfperm(path, "rwxr-xr-x") end
end
local function show(r) return r and ("%s %s%s"):format(r.source, tostring(r.path), r.reason and (" (" .. r.reason .. ")") or "") or "no answer" end
local function choose(root, choice)
  local done
  tools.set_choice(root, choice, function(ok, err) done = { ok, err } end)
  wait_until(function() return done ~= nil end, 10000)
  return done and done[1], done and done[2]
end
-- after a refresh or a choice, the next answer for name in root
local function again(name, root)
  tools.refresh(root)
  return tools.wait(name, root, 10000)
end

-- the suite's global ruff, and its version, which the project pins so the pin is installed
local global = tools.wait("ruff", FIX, 10000)
if not (global and global.path) then return end -- the harness already failed the check
local version = vim.trim(vim.system({ global.path, "--version" }, { text = true }):wait().stdout or ""):match("([%d.]+)$")
if not check("ruff reports its version", version ~= nil, global.path) then return end

local proj = FIX .. "/order"
put(proj .. "/mise.toml", { "[tools]", ('ruff = "%s"'):format(version) })

local r = tools.wait("ruff", proj, 10000)
check("a project config nobody accepted is ignored: global mise", r and r.source == "global-mise", show(r))

local ok, err = choose(proj, "installed")
check("set_choice installed succeeds", ok, err)
r = tools.wait("ruff", proj, 10000)
local data = vim.fs.normalize(vim.env.MISE_DATA_DIR)
check("an accepted project config wins over global: project mise", r and r.source == "project-mise"
  and vim.startswith(r.path or "", data .. "/installs/ruff/"), show(r))

local venv_ruff = proj .. "/.venv/bin/ruff"
put(venv_ruff, { "#!/bin/sh", "echo ruff 0.0.1" }, true)
r = again("ruff", proj)
check("the project env wins over the project's mise pins", r and r.source == "project-env" and r.path == venv_ruff, show(r))
check("a project env copy and a pin of different versions are reported as a conflict",
  r and r.conflict and r.conflict.env.version == "0.0.1" and r.conflict.mise.version == version, r and vim.inspect(r.conflict))
local function prefer(which)
  local said
  tools.set_prefer(proj, "ruff", which, function(ok) said = ok end)
  wait_until(function() return said ~= nil end, 10000)
  return tools.wait("ruff", proj, 10000)
end
r = prefer("mise")
check("picking the mise pin over the project env: project mise", r and r.source == "project-mise", show(r))
r = prefer("env")
check("picking the project env back: project env", r and r.source == "project-env" and r.path == venv_ruff, show(r))
put(venv_ruff, { "#!/bin/sh", "echo ruff " .. version }, true)
r = again("ruff", proj)
check("the same version in both is no conflict", r and r.source == "project-env" and r.conflict == nil, r and vim.inspect(r.conflict))
put(venv_ruff, { "#!/bin/sh", "echo ruff 0.0.1" }, true)
r = again("ruff", proj)
-- searched upward from the root: a sub-project without its own .venv still gets it
put(proj .. "/sub/pyproject.toml", { "[project]", 'name = "sub"' })
r = tools.wait("ruff", proj .. "/sub", 10000)
check("the project env is found upward from a nested root", r and r.source == "project-env" and r.path == venv_ruff, show(r))

vim.fn.delete(proj .. "/.venv", "rf")
ok, err = choose(proj, "global")
check("set_choice global succeeds", ok, err)
r = tools.wait("ruff", proj, 10000)
check("global only ignores the project's pins: global mise", r and r.source == "global-mise", show(r))

-- A pin that is not installed, with "only versions already installed": the global copy runs, the pinned version is
-- offered for the project; a tool missing everywhere is offered both ways
local pin5 = FIX .. "/pin5"
put(pin5 .. "/mise.toml", { "[tools]", 'ruff = "0.0.1"', '"pypi:pyproject-fmt" = "0.0.1"' })
ok, err = choose(pin5, "installed")
check("set_choice installed succeeds for a pin that is not installed", ok, err)
r = tools.wait("ruff", pin5, 10000)
check("a pin that is not installed falls back to global mise", r and r.source == "global-mise", show(r))
check("the pinned version is offered for the project", r and r.offers and r.offers[1].kind == "pinned" and r.offers[1].spec == "ruff@0.0.1",
  r and vim.inspect(r.offers))
local fmt = tools.wait("pyproject-fmt", pin5, 10000)
if fmt and fmt.source == "missing" then
  check("a pinned tool missing everywhere offers the pinned version, and global latest instead",
    fmt.install and fmt.install.kind == "pinned" and fmt.install.spec == "pypi:pyproject-fmt@0.0.1" and fmt.install.global
      and fmt.install.global.spec == "pypi:pyproject-fmt@latest", vim.inspect(fmt.install))
else
  info("pyproject-fmt resolves in the suite (" .. show(fmt) .. "), so the pinned missing case is not exercised")
end
ok, err = choose(pin5, "global")
r = tools.wait("ruff", pin5, 10000)
check("with global only, the pin is not offered", r and r.source == "global-mise" and r.offers == nil, r and vim.inspect(r.offers))

-- A copy below the catalog's lowest version is skipped, and the result says what was skipped
local ts = FIX .. "/ts"
put(ts .. "/package.json", { "{}" })
put(ts .. "/node_modules/.bin/tsc", { "#!/bin/sh", "echo Version 5.9.3" }, true)
r = tools.wait("tsc", ts, 10000)
check("a project tsc older than 7 is skipped for the global one", r and r.source == "global-mise", show(r))
check("the skipped copy is noted with its source and version", r and r.skipped and r.skipped[1].source == "project-env"
  and r.skipped[1].version == "5.9.3", r and vim.inspect(r.skipped))

-- A project config that pins no tools is no project config
put(FIX .. "/empty/mise.toml", { "[tools]" })
local p
tools.project(FIX .. "/empty", function(x) p = x end)
wait_until(function() return p ~= nil end, 10000)
check("a config that pins no tools is not a project config", p and #p.configs == 0, p and vim.inspect(p.configs))

-- PATH: a tool only in a mise shims dir, a mise install dir or Mason's bin dir is missing; in a plain dir it is the system's
local name = "nvr-fake-tool"
local path = vim.env.PATH
local stale = { FIX .. "/fake/mise/shims", FIX .. "/fake/mise/installs/nvr/1.0/bin", FIX .. "/fake/mason/bin" }
for _, dir in ipairs(stale) do put(dir .. "/" .. name, { "#!/bin/sh" }, true) end
vim.env.PATH = table.concat(stale, ":") .. ":" .. path
r = again(name, FIX)
check("a binary only in mise shims, mise installs or Mason's bin dir counts as missing", r and r.source == "missing", show(r))
check("a tool outside the catalog offers no install", r and r.install and r.install.kind == "none", r and vim.inspect(r.install))
put(FIX .. "/fake/bin/" .. name, { "#!/bin/sh" }, true)
vim.env.PATH = table.concat(stale, ":") .. ":" .. FIX .. "/fake/bin:" .. path
r = again(name, FIX)
check("a binary in a plain PATH dir is the system's", r and r.source == "system" and r.path == FIX .. "/fake/bin/" .. name, show(r))
vim.env.PATH = path

-- missing everywhere: the catalog's spec is offered for a global install, at "latest"
r = tools.wait("pyproject-fmt", FIX, 10000)
if r and r.source == "missing" then
  local spec = require("tools.catalog").tools["pyproject-fmt"].spec
  check("a missing catalog tool offers its global mise spec at latest", r.install and r.install.kind == "global"
    and r.install.spec == spec .. "@latest", vim.inspect(r.install))
else
  info("pyproject-fmt resolves in the suite (" .. show(r) .. "), so the missing case is not exercised")
end
