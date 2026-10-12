-- @desc     the profiler keys live under <leader>P, labelled Profiler, and leave <leader>p to the PR review menu
-- @areas    which-key keys
-- @budget   30
-- @version-sensitive
-- @args     main.lua
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded) then return end

local GH = FIX .. "/.nvr-gh"
vim.system({ "git", "init", "-q", GH }):wait()
vim.system({ "git", "-C", GH, "remote", "add", "origin", "git@github.com:x/y.git" }):wait()
vim.fn.writefile({ "x" }, GH .. "/file.txt")
vim.cmd.cd(GH)
vim.cmd.edit(GH .. "/file.txt")
local buf = vim.api.nvim_get_current_buf()
check("PR review menu mapped on <leader>p in a GitHub repo", wait_until(function() return vim.fn.maparg("<leader>p", "n") ~= "" end, 5000))

local function key(s) return vim.fn.keytrans(vim.keycode((s:gsub("<[lL]eader>", vim.g.mapleader or "\\")))) end
local Pp = key("<leader>P")
local pp = key("<leader>p")

for _, k in ipairs({ "p", "s", "h" }) do
  local m = vim.fn.maparg("<leader>P" .. k, "n", false, true)
  check("<leader>P" .. k .. " is mapped", m.lhs ~= nil, m.desc)
end

local stray = {}
for _, mode in ipairs({ "n", "x", "s", "o" }) do
  local all = vim.list_extend(vim.api.nvim_get_keymap(mode), vim.api.nvim_buf_get_keymap(buf, mode))
  for _, m in ipairs(all) do
    local lhs = vim.fn.keytrans(m.lhsraw or m.lhs)
    if lhs:sub(1, #pp) == pp and not (lhs == pp and (m.rhs or ""):find("PR")) then
      stray[#stray + 1] = mode .. ":" .. lhs
    end
  end
end
check("nothing but the PR maps starts with <leader>p", #stray == 0, #stray > 0 and table.concat(stray, " ") or nil)

local root = require("which-key.buf").get({ buf = buf, mode = "n", update = true }).tree.root
local function find(node, keys)
  for _, child in ipairs(node:children()) do
    if child.keys == keys then return child end
    if keys:sub(1, #child.keys) == child.keys then return find(child, keys) end
  end
end
local gP, gp = find(root, Pp), find(root, pp)
check("which-key labels <leader>P Profiler", gP ~= nil and gP:is_group() and gP.desc == "Profiler", gP and tostring(gP.desc))
check("which-key labels <leader>p PR Review Menu", gp ~= nil and gp.desc == "PR Review Menu", gp and tostring(gp.desc))
vim.cmd.cd(FIX)
