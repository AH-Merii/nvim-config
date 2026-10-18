-- @desc     startup is clean: every plugin the config names is installed, :checkhealth vim.pack has no ERROR or WARNING, and no error or warning reached the user after startup and VeryLazy
-- @areas    startup smoke
-- @budget   12
local plugins = require("app.plugins").list()
local missing = {}
for _, p in ipairs(plugins) do
  if not vim.uv.fs_stat(p.path) then table.insert(missing, p.name) end
end
check("every plugin the config names is installed", #plugins > 0 and #missing == 0,
  #plugins .. " named; missing: " .. table.concat(missing, ","))

local text = health("vim.pack", 6000)
check("checkhealth vim.pack finished", text ~= "TIMEOUT")
local bad = {}
for line in text:gmatch("[^\n]+") do
  if line:find("ERROR") or line:find("WARNING") then table.insert(bad, vim.trim(line)) end
end
check("checkhealth vim.pack: no ERROR or WARNING", #bad == 0, table.concat(bad, " | "))

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
