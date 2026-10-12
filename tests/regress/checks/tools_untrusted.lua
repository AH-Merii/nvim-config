-- @desc     a project mise config with [env] that mise refuses until trusted is treated as global only, even after the user accepts it; its project env still applies
-- @areas    tools
-- @budget   25
-- @needs    ruff
local tools = require("tools")

local function show(r) return r and ("%s %s"):format(r.source, tostring(r.path)) or "no answer" end

local global = tools.wait("ruff", FIX, 10000)
if not (global and global.path) then return end -- the harness already failed the check
local version = vim.trim(vim.system({ global.path, "--version" }, { text = true }):wait().stdout or ""):match("([%d.]+)$")
local root = FIX .. "/untrusted"
local config = root .. "/mise.toml"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "[tools]", ('ruff = "%s"'):format(version), "[env]", 'NVR_UNTRUSTED = "1"' }, config)

local p
tools.project(root, function(x) p = x end)
wait_until(function() return p ~= nil end, 10000)
check("the [env] config is reported untrusted", p and p.untrusted and vim.fs.normalize(p.untrusted) == config and vim.deep_equal(p.configs, { config }),
  p and vim.inspect({ p.untrusted, p.configs }))
check("an untrusted project is not used", p and not p.active, p and tostring(p.active))
local r = tools.wait("ruff", root, 10000)
check("ruff comes from global mise", r and r.source == "global-mise", show(r))

local done
tools.set_choice(root, "installed", function(ok, err) done = { ok, err } end)
wait_until(function() return done ~= nil end, 10000)
p = nil
tools.project(root, function(x) p = x end)
wait_until(function() return p ~= nil end, 10000)
check("accepting it does not make mise use it", p and p.choice == "installed" and not p.active, p and vim.inspect({ p.choice, p.active }))
r = tools.wait("ruff", root, 10000)
check("ruff still comes from global mise", r and r.source == "global-mise", show(r))

-- trust is never granted on the user's behalf: mise still refuses the config
local res = vim.system({ "mise", "env", "--json" }, { cwd = root, text = true }):wait(10000)
check("nothing trusted the config", res.code ~= 0 and (res.stderr or ""):find("not trusted", 1, true) ~= nil,
  ("exit %d: %s"):format(res.code, (res.stderr or ""):sub(1, 200)))

local venv_ruff = root .. "/.venv/bin/ruff"
vim.fn.mkdir(vim.fs.dirname(venv_ruff), "p")
vim.fn.writefile({ "#!/bin/sh" }, venv_ruff)
vim.fn.setfperm(venv_ruff, "rwxr-xr-x")
tools.refresh(root)
r = tools.wait("ruff", root, 10000)
check("the project env still applies", r and r.source == "project-env" and r.path == venv_ruff, show(r))
