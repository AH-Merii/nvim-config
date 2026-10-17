-- @desc     with no git, no LSP and the cwd outside git, every lazy key declared without ft is a global map with its desc and callback, the global find/search maps run and open pickers, every globally mapped Snacks toggle flips and flips back, and the PR review commands exist once the plugin loads
-- @areas    keys which-key ui git
-- @budget   20
-- Ported from nvim-sbx-keys/checks2/regress.lua. Guards the global keys while context-gated keys come and go.

local cur, n, bad
local function done()
  if cur and bad == 0 then check(cur, true, n .. " assertions") end
end
local function section(name)
  done()
  cur, n, bad = name, 0, 0
end
local function expect(ok, fmt, ...)
  n = n + 1
  if not ok then
    bad = bad + 1
    check(cur .. ": " .. fmt:format(...), false)
  end
  return ok
end
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end
local function global_map(mode, lhs)
  local raw = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
    if m.lhsraw == raw or m.lhsrawalt == raw then return m end
  end
end
local function close_floats()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then pcall(vim.api.nvim_win_close, w, true) end
  end
end

local Config = require("lazy.core.config")
local Plugin = require("lazy.core.plugin")
local Keys = require("lazy.core.handler.keys")
local NOGIT = vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/nogit"
vim.fn.mkdir(NOGIT, "p")
vim.fn.writefile({ "plain text" }, NOGIT .. "/plain.txt")
vim.cmd.edit(NOGIT .. "/plain.txt")
vim.cmd.cd(NOGIT)
flush()

section("lazy keys without ft are global")
local declared = 0
for name, plugin in pairs(Config.plugins) do
  for _, parsed in pairs(Keys.resolve(Plugin.values(plugin, "keys", true))) do
    if not parsed.ft then
      declared = declared + 1
      local m = global_map(parsed.mode == "v" and "x" or parsed.mode, parsed.lhs)
      expect(m ~= nil and m.desc == parsed.desc, "%s %s %s (%s) is global with its desc", name, parsed.mode, parsed.lhs, parsed.desc or "")
      if m and plugin._.loaded and type(parsed.rhs) == "function" then
        expect(m.callback == parsed.rhs, "%s %s runs its declared function", name, parsed.lhs)
      end
    end
  end
end
expect(declared > 0, "lazy declares global keys (%d)", declared)

section("global find and search maps open pickers")
local leader = vim.g.mapleader or "\\"
local pickers = 0
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  local rest = m.lhs:sub(#leader + 1)
  if m.callback and m.expr ~= 1 and m.lhs:sub(1, #leader) == leader and (rest:match("^[fs].") or rest == "/") then
    local hit
    local real = Snacks.picker
    Snacks.picker = setmetatable({}, {
      __index = function(_, k) return function() hit = k end end,
      __call = function(_, source) hit = tostring(source) end,
    })
    local ok, err = pcall(m.callback)
    Snacks.picker = real
    close_floats()
    if hit then pickers = pickers + 1 end
    expect(ok and hit ~= nil, "%s (%s) opens a picker (%s)", vim.fn.keytrans(m.lhs), m.desc or "", ok and "no picker" or tostring(err))
  end
end
expect(pickers > 0, "global find/search maps exist (%d)", pickers)

section("global Snacks toggles flip and flip back")
local toggled = 0
for id, toggle in pairs(Snacks.toggle.toggles) do
  local desc = "Toggle " .. toggle.opts.name
  for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
    -- an expr map is a gated key (D48): it acts only where its need holds, which plain.txt here lacks
    if m.desc == desc and m.callback and m.expr ~= 1 then
      local before = toggle:get()
      local ok1, err1 = pcall(m.callback)
      local mid = toggle:get()
      local ok2, err2 = pcall(m.callback)
      local after = toggle:get()
      toggled = toggled + 1
      expect(ok1 and ok2 and mid ~= before and after == before, "toggle %s (%s) flips and flips back (%s %s %s%s)", vim.fn.keytrans(m.lhs), id,
        tostring(before), tostring(mid), tostring(after), (ok1 and ok2) and "" or (": " .. tostring(err1 or err2)))
    end
  end
end
expect(toggled > 0, "global toggles exist (%d)", toggled)

section("PR review commands exist after loading")
local pr = Config.plugins["github-pr-reviewer.nvim"]
if not pr then
  info("github-pr-reviewer.nvim is not in the config; PR part skipped")
else
  require("lazy").load({ plugins = { pr.name } })
  local cmds = pr.cmd or {}
  cmds = type(cmds) == "string" and { cmds } or cmds
  for _, cmd in ipairs(cmds) do
    expect(vim.fn.exists(":" .. cmd) == 2, "command %s exists after loading", cmd)
  end
end
vim.cmd.cd(FIX)
done()
