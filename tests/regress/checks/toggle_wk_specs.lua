-- @desc     the buffer-local <leader>TT and <leader>TG toggles add no which-key spec per buffer, and their which-key label follows the toggle state
-- @areas    which-key keys git treesitter
-- @budget   25
-- @args     main.lua
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded) then return end
local wkc = package.loaded["which-key.config"]
local function norm(lhs) return vim.fn.keytrans(vim.keycode((lhs:gsub("<[lL]eader>", vim.g.mapleader or "\\")))) end
local keys = { TT = norm("<leader>TT"), TG = norm("<leader>TG") }
local function specs(lhs)
  local out = {}
  for _, m in ipairs(rawget(wkc, "mappings")) do
    if m.lhs and norm(m.lhs) == lhs and (m.mode or "n") == "n" then table.insert(out, m) end
  end
  return out
end
-- both toggles are mapped when treesitter and gitsigns attach to the buffer
local function attached(buf)
  local function has(lhs) return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, "n", false, true).buffer == 1 end) end
  return has("<leader>TT") and has("<leader>TG")
end
local function open(file)
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  return buf, wait_until(function() return attached(buf) end, 5000)
end

local first = vim.api.nvim_get_current_buf()
check("main.lua gets both toggles", wait_until(function() return attached(first) end, 5000))
local before = { TT = #specs(keys.TT), TG = #specs(keys.TG) }
for _, f in ipairs({ "app.py", "notes.md", "main.go", "index.ts" }) do
  local _, ok = open(f)
  check(f .. " gets both toggles", ok)
end
for name, lhs in pairs(keys) do
  local now = #specs(lhs)
  check(name .. ": which-key has a spec", before[name] > 0, before[name])
  check(name .. ": opening buffers adds no which-key spec", now == before[name], before[name] .. " -> " .. now)
end

-- in the last buffer: the key toggles and the label follows
local buf = vim.api.nvim_get_current_buf()
local function label(name)
  local s = specs(keys[name])
  local m = s[#s]
  if not m then return nil end
  local d = type(m.desc) == "function" and m.desc() or m.desc
  local i = type(m.icon) == "function" and m.icon() or m.icon
  return tostring(d) .. " " .. vim.inspect(i)
end
for name, probe in pairs({ TT = function() return vim.treesitter.highlighter.active[buf] ~= nil end, TG = function() return require("gitsigns.config").config.signcolumn end }) do
  local lhs = "<leader>" .. name
  local s0, l0 = probe(), label(name)
  feed(lhs)
  local s1, l1 = probe(), label(name)
  feed(lhs)
  check(name .. ": key flips the state", s1 ~= s0 and probe() == s0, tostring(s0) .. " " .. tostring(s1))
  check(name .. ": which-key label follows the state", l0 ~= l1 and label(name) == l0, tostring(l0) .. " | " .. tostring(l1))
end
