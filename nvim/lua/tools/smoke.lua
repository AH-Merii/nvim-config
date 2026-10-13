-- Headless smoke test of the resolver; changes nothing outside a temp dir:
--   XDG_STATE_HOME=$(mktemp -d) nvim --clean --headless -l nvim/lua/tools/smoke.lua [root]

local config = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))))
vim.opt.rtp:prepend(config)
local tools = require("tools")
tools.setup()

local failures = 0
local function check(ok, what)
  print(("%s %s"):format(ok and "ok  " or "FAIL", what))
  failures = failures + (ok and 0 or 1)
end

local function show(result)
  if not result then
    return "nil (timed out)"
  end
  local install = result.install and (" install=%s %s"):format(result.install.kind, result.install.spec or result.install.component or "") or ""
  local env = result.env and " env.PATH[1]=" .. vim.split(result.env.PATH, ":")[1] or ""
  return ("%-13s %-12s %s%s%s%s"):format(result.name, result.source, result.path or "-", result.reason and " (" .. result.reason .. ")" or "", install, env)
end

local events = {}
vim.api.nvim_create_autocmd("User", { pattern = tools.event, callback = function(ev) table.insert(events, ev.data) end })

local root = vim.fs.abspath(_G.arg[1] or vim.fs.dirname(config))
print("root " .. root)
check(tools.get("ruff", root) == nil, "nothing cached before resolving")
local t0 = vim.uv.hrtime()
local names = { "ruff", "stylua", "rust-analyzer", "rustfmt", "cargo-clippy", "tsc", "prettierd", "fish", "not-a-tool" }
local done
tools.resolve_all(names, root, function(results) done = results end)
vim.wait(10000, function() return done ~= nil end, 10)
print(("resolved %d tools in %d ms"):format(#names, (vim.uv.hrtime() - t0) / 1e6))
for _, name in ipairs(names) do
  print("  " .. show(done and done[name]))
end
check(done ~= nil, "resolve_all calls back")
check(tools.get("ruff", root) ~= nil, "get returns the cached result")
local sync
check(tools.resolve("ruff", root, function(r) sync = r end) ~= nil and sync ~= nil, "resolve answers a cached tool synchronously")
for _, result in pairs(done or {}) do
  check(not (result.path or ""):find("/mise/shims/") and not (result.path or ""):find("/mason/bin/"), result.name .. " is not a shim or Mason binary")
end
vim.wait(100, function() return #events > 0 end)
check(#events > 0 and events[1].root == root and events[1].reason == "resolved", "User ToolsChanged fired with reason resolved")

-- Project configs, in a temp dir
local tmp = vim.fn.tempname()
local plain, env = vim.fs.joinpath(tmp, "plain"), vim.fs.joinpath(tmp, "env")
vim.fn.mkdir(vim.fs.joinpath(plain, ".venv/bin"), "p")
vim.fn.mkdir(env, "p")
vim.fn.writefile({ "[tools]", 'ruff = "0.6.0"' }, vim.fs.joinpath(plain, "mise.toml"))
vim.fn.writefile({ "#!/bin/sh", "echo venv-ruff" }, vim.fs.joinpath(plain, ".venv/bin/ruff"))
vim.uv.fs_chmod(vim.fs.joinpath(plain, ".venv/bin/ruff"), 493)
vim.fn.writefile({ "[tools]", 'ruff = "latest"', "[env]", 'FOO = "1"' }, vim.fs.joinpath(env, "mise.toml"))

local project
tools.project(plain, function(p) project = p end)
vim.wait(5000, function() return project ~= nil end)
print("plain project: " .. vim.inspect(project and { configs = project.configs, choice = project.choice, missing = project.missing, active = project.active }))
check(project and #project.configs == 1 and project.choice == nil and not project.active, "unanswered project config is found and not used")
check(project and vim.list_contains(project.missing, "ruff"), "uninstalled pin is listed as missing")
local venv_ruff = tools.wait("ruff", plain, 5000)
print("  " .. show(venv_ruff))
check(venv_ruff and venv_ruff.source == "project-env", ".venv/bin wins over everything")

tools.set_choice(plain, "installed")
vim.wait(5000, function() return (tools.project(plain) or {}).choice == "installed" end)
check((tools.project(plain) or {}).active == true, "choice 'installed' is remembered and makes the project config active")

local untrusted
tools.project(env, function(p) untrusted = p end)
vim.wait(5000, function() return untrusted ~= nil end)
print("env project: " .. vim.inspect(untrusted and { configs = untrusted.configs, untrusted = untrusted.untrusted, active = untrusted.active }))
check(untrusted and untrusted.untrusted ~= nil and not untrusted.active, "config with [env] is untrusted and ignored")
print("  " .. show(tools.wait("stylua", env, 5000)))

local refused
tools.install_global({ "ruff@latest" }, function(ok, err) refused = { ok, err } end)
vim.wait(5000, function() return refused ~= nil end)
check(refused and refused[1] == false, "headless install refused: " .. tostring(refused and refused[2]))

local ft = vim.filetype.match({ filename = "/x/.github/workflows/ci.yml" })
check(ft == "yaml.github-actions", "workflow file is yaml.github-actions")
check(vim.filetype.match({ filename = "/x/pyproject.toml" }) == "toml.pyproject", "pyproject.toml is toml.pyproject")

vim.fn.delete(tmp, "rf")
print(failures == 0 and "PASS" or ("FAIL: %d"):format(failures))
os.exit(failures == 0 and 0 or 1)
