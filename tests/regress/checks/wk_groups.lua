-- @desc     every which-key group under <leader> has at least one real keymap behind it, global or buffer-local
-- @areas    which-key keys
-- @budget   10
-- @args     main.lua
local buf = vim.api.nvim_get_current_buf()
-- which-key schedules loading its spec when set up after VimEnter
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded, not loaded and "which-key.config never reached loaded" or nil) then return end

local function norm(lhs) return vim.fn.keytrans(vim.keycode((lhs:gsub("<[lL]eader>", vim.g.mapleader or "\\")))) end
local leader = norm("<leader>")
local function maps(mode, b)
  local out = {}
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do table.insert(out, vim.fn.keytrans(m.lhsraw or m.lhs)) end
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(b, mode)) do table.insert(out, vim.fn.keytrans(m.lhsraw or m.lhs)) end
  return out
end

local seen, groups = {}, 0
for _, g in ipairs(rawget(package.loaded["which-key.config"], "mappings")) do
  local prefix = g.lhs and norm(g.lhs)
  local mode = g.mode or "n"
  local b = g.buffer and vim.api.nvim_buf_is_valid(g.buffer) and g.buffer or buf
  local key = prefix and (prefix .. " " .. mode .. " " .. b)
  if g.group and prefix and #prefix > #leader and prefix:sub(1, #leader) == leader and not seen[key] then
    seen[key], groups = true, groups + 1
    local kids = {}
    for _, lhs in ipairs(maps(mode, b)) do
      if #lhs > #prefix and lhs:sub(1, #prefix) == prefix then table.insert(kids, lhs) end
    end
    table.sort(kids)
    check(string.format("which-key group %s %s (%s) has keymaps", mode, g.lhs, tostring(g.desc)), #kids > 0,
      #kids .. ": " .. table.concat(vim.list_slice(kids, 1, 4), " "))
  end
end
check("which-key has groups under <leader>", groups > 0, groups .. " groups")
