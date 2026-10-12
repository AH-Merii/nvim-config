-- @desc     headless, nothing prompts and nothing installs: opening files of a project whose mise config pins a missing tool, and whose filetypes lack their tools, asks nothing, and every install function refuses without running a command
-- @areas    tools startup
-- @budget   30
local tools = require("tools")

-- every way the config could ask, and every command it runs from here on
local asked, ran = {}, {}
for _, fn in ipairs({ "select", "input" }) do
  local orig = vim.ui[fn]
  vim.ui[fn] = function(...)
    table.insert(asked, "vim.ui." .. fn)
    return orig(...)
  end
end
for _, fn in ipairs({ "confirm", "input", "inputlist" }) do
  local orig = vim.fn[fn]
  vim.fn[fn] = function(...)
    table.insert(asked, "vim.fn." .. fn)
    return orig(...)
  end
end
local system = vim.system
vim.system = function(cmd, ...)
  table.insert(ran, table.concat(cmd, " "))
  return system(cmd, ...)
end
local function installs()
  return vim.tbl_filter(function(c)
    return c:find(" use %-g") or c:find(" install") or c:find(" trust") or c:find("component add")
  end, ran)
end

check("installs are off without a UI", not tools.can_install())

-- a project pinning a shfmt version nobody installed, with files whose tools the suite lacks
local root = FIX .. "/proj"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "[tools]", 'shfmt = "3.7.0"' }, root .. "/mise.toml")
vim.fn.writefile({ "echo hi" }, root .. "/script.sh")
vim.fn.writefile({ "key: value" }, root .. "/config.yaml")
vim.fn.writefile({ "[tool]" }, root .. "/pyproject.toml")
local events = 0
vim.api.nvim_create_autocmd("User", { pattern = tools.event, callback = function() events = events + 1 end })
for _, f in ipairs({ "script.sh", "config.yaml", "pyproject.toml" }) do
  vim.cmd.edit(root .. "/" .. f)
end
local p
tools.project(root, function(x) p = x end)
wait_until(function() return p ~= nil end, 10000)
check("the project's pin is missing", p and vim.list_contains(p.missing, "shfmt"), p and vim.inspect(p.missing))
local want = tools.for_filetype("sh").tools
local results
tools.resolve_all(want, root, function(r) results = r end)
wait_until(function() return results ~= nil end, 10000)
local missing = vim.tbl_filter(function(n) return results and not results[n].path end, want)
info("sh tools missing here: " .. table.concat(missing, ", "))
check("some tool is missing, so an offer would be due", #missing > 0, vim.inspect(want))
-- give any prompt on resolution, FileType or ToolsChanged time to come
wait_until(function() return events > 0 end, 5000)
vim.wait(1500)

local function refused(start)
  local done
  start(function(ok, err) done = { ok, err } end)
  wait_until(function() return done ~= nil end, 5000)
  return done and done[1] == false and (done[2] or ""):find("off") ~= nil, done and vim.inspect(done)
end
check("install_global refuses", refused(function(cb) tools.install_global({ "shfmt@latest" }, cb) end))
check("install_project refuses", refused(function(cb) tools.install_project(root, cb) end))
check("install_component refuses", refused(function(cb) tools.install_component("rust-analyzer", root, cb) end))
check("set_choice use refuses to install", refused(function(cb) tools.set_choice(root, "use", cb) end))
check("install refuses", (function()
  local done
  tools.install({ "shfmt" }, root, function(ok, errs) done = { ok, errs } end)
  wait_until(function() return done ~= nil end, 5000)
  return done and done[1] == false, done and vim.inspect(done)
end)())

-- Plain :Tools is a picker the user opens, not a prompt; :Tools install still installs nothing and asks nothing
if check(":Tools exists", vim.fn.exists(":Tools") == 2) then
  local notify, said = vim.notify, {}
  vim.notify = function(msg) table.insert(said, msg) end
  local function says_off() return vim.iter(said):any(function(m) return m:find("installs are off") ~= nil end) end
  pcall(vim.cmd, "Tools install")
  -- Wait for that message, not the first one: noice warns here when it finds vim.notify replaced
  wait_until(says_off, 5000)
  vim.notify = notify
  check(":Tools install says installs are off", says_off(), vim.inspect(said))
end
vim.wait(500)
check("nothing asked", #asked == 0, table.concat(asked, ", "))
check("no install, trust or mise use ran", #installs() == 0, table.concat(installs(), " | "))
p = nil
tools.project(root, function(x) p = x end)
wait_until(function() return p ~= nil end, 10000)
check("the pin is still not installed", p and vim.list_contains(p.missing, "shfmt"), p and vim.inspect(p.missing))
