-- @desc     startup is clean: every lazy spec plugin is installed, specs load without notices, :checkhealth lazy has no ERROR or WARNING, and no error or warning reached the user after startup and VeryLazy
-- @areas    startup smoke
-- @budget   12
local Config = require("lazy.core.config")
local missing, count = {}, 0
for name, p in pairs(Config.plugins) do
  count = count + 1
  if not (p._ and p._.installed) then table.insert(missing, name) end
end
table.sort(missing)
check("lazy: every spec'd plugin is installed", #missing == 0, count .. " spec'd; missing: " .. table.concat(missing, ","))
local notifs = {}
for _, n in ipairs(Config.spec.notifs or {}) do table.insert(notifs, n.msg) end
check("lazy: specs load without notices", #notifs == 0, table.concat(notifs, " | "))
local clean = {}
for _, p in pairs(Config.to_clean or {}) do table.insert(clean, p.name) end
table.sort(clean)
if #clean > 0 then info("on disk but not spec'd (Lazy clean candidates): " .. table.concat(clean, ",")) end

-- lazy warns about any existing site/pack/* dir (it stats the dir, not its contents), and the suite's
-- data dir has an empty site/pack/core/opt from vim.pack; only that empty dir is excused
local text = health("lazy", 6000)
check("checkhealth lazy finished", text ~= "TIMEOUT")
local core = vim.uv.fs_realpath(vim.fn.stdpath("data") .. "/site/pack/core")
local function holds_packages(dir) return #vim.fn.glob(dir .. "/*/*", false, true) > 0 end
local bad, excused = {}, {}
for line in text:gmatch("[^\n]+") do
  if line:find("ERROR") or line:find("WARNING") then
    local dir = line:match("existing packages at `([^`]*)`")
    local empty_core = dir ~= nil and core ~= nil and vim.uv.fs_realpath(dir) == core and not holds_packages(dir)
    table.insert(empty_core and excused or bad, vim.trim(line))
  end
end
check("checkhealth lazy: no ERROR or WARNING", #bad == 0, table.concat(bad, " | "))
if #excused > 0 then info("excused, empty vim.pack dir: " .. table.concat(excused, " | ")) end

-- :messages holds every message ui2 shows (ui2 has no history of its own; its pager renders this one);
-- snacks.notifier takes over vim.notify and never echoes, so its history holds the notifications
local errs = {}
local msgs = vim.api.nvim_exec2("messages", { output = true }).output
for line in msgs:gmatch("[^\n]+") do
  if line:find("E%d+:") or line:find("[Ee]rror") or line:find("stack traceback") or line:find("[Ww]arn") then
    table.insert(errs, ":messages: " .. line)
  end
end
local snacks_notifier = package.loaded["snacks.notifier"]
if snacks_notifier and snacks_notifier.get_history then
  for _, n in ipairs(snacks_notifier.get_history({ filter = vim.log.levels.WARN })) do
    table.insert(errs, "snacks.notifier: " .. tostring(n.msg))
  end
end
check("no error or warning after startup and VeryLazy", #errs == 0, table.concat(errs, " | "))
