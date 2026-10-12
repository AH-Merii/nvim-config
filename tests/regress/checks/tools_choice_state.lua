-- @desc     the answer to the project prompt is remembered per project config, also by a new session, and forgotten when the config is edited and written
-- @areas    tools
-- @budget   30
-- @needs    ruff
local tools = require("tools")

local function show(r) return r and ("%s %s"):format(r.source, tostring(r.path)) or "no answer" end
local function project(root)
  local p
  tools.project(root, function(x) p = x end)
  wait_until(function() return p ~= nil end, 10000)
  return p
end
-- the choice a fresh nvim (same state dir, nothing cached) reads for root
local function new_session(root)
  local script = FIX .. "/session.lua"
  vim.fn.writefile({
    "vim.opt.rtp:prepend(vim.fn.stdpath('config'))",
    "local p",
    ("require('tools').project(%q, function(x) p = x end)"):format(root),
    "vim.wait(10000, function() return p ~= nil end)",
    "io.stdout:write(p and tostring(p.choice) or 'timeout')",
  }, script)
  local res = vim.system({ vim.v.progpath, "--clean", "--headless", "-l", script }, { text = true }):wait(20000)
  return vim.trim(res.stdout or ""), res
end

local global = tools.wait("ruff", FIX, 10000)
if not (global and global.path) then return end -- the harness already failed the check
local version = vim.trim(vim.system({ global.path, "--version" }, { text = true }):wait().stdout or ""):match("([%d.]+)$")
local root = FIX .. "/choice"
local config = root .. "/mise.toml"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "[tools]", ('ruff = "%s"'):format(version) }, config)

local p = project(root)
check("a new project config has no choice yet and is not used", p and p.choice == nil and not p.active
  and vim.deep_equal(p.configs, { config }), p and vim.inspect({ p.choice, p.active, p.configs }))

local done
tools.set_choice(root, "installed", function(ok, err) done = { ok, err } end)
wait_until(function() return done ~= nil end, 10000)
check("set_choice installed succeeds", done and done[1], done and done[2])
p = project(root)
check("the choice is remembered and the project is used", p and p.choice == "installed" and p.active,
  p and vim.inspect({ p.choice, p.active }))
local r = tools.wait("ruff", root, 10000)
check("ruff now comes from the project's pin", r and r.source == "project-mise", show(r))
local out, res = new_session(root)
check("a new session reads the same choice", out == "installed", out .. " " .. (res.stderr or ""):sub(1, 200))

-- editing the config through Neovim: BufWritePost refreshes, the old answer no longer applies
local events = {}
vim.api.nvim_create_autocmd("User", {
  pattern = tools.event,
  callback = function(ev) if ev.data.root == root then table.insert(events, ev.data) end end,
})
vim.cmd.edit(config)
vim.api.nvim_buf_set_lines(0, -1, -1, false, { "# edited" })
vim.cmd("silent write")
r = nil
wait_until(function()
  r = tools.get("ruff", root)
  return r ~= nil and r.source ~= "project-mise"
end, 10000)
check("after the config is written ruff falls back to global", r and r.source == "global-mise", show(r))
p = project(root)
check("the edited config has no choice and is not used", p and p.choice == nil and not p.active, p and vim.inspect({ p.choice, p.active }))
local said = vim.iter(events):any(function(e) return vim.list_contains(e.tools, "ruff") and e.reason == "refresh" end)
check("ToolsChanged says ruff changed for the root, reason refresh", said, vim.inspect(events))
out, res = new_session(root)
check("a new session asks again too", out == "nil", out .. " " .. (res.stderr or ""):sub(1, 200))
