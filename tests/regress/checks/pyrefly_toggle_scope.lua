-- @desc     which-key lists <leader>Te only in buffers pyrefly is attached to, drops it when pyrefly detaches, and opening buffers adds no which-key spec for it
-- @areas    lsp keys which-key
-- @budget   60
-- @fixture  projects
-- @needs    pyrefly ruff lua-language-server
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded) then return end
local wkc = package.loaded["which-key.config"]
local function norm(lhs) return vim.fn.keytrans(vim.keycode((lhs:gsub("<[lL]eader>", vim.g.mapleader or "\\")))) end
local key = norm("<leader>Te")
local function specs()
  local n = 0
  for _, m in ipairs(rawget(wkc, "mappings")) do
    if m.lhs and norm(m.lhs) == key and (m.mode or "n") == "n" then n = n + 1 end
  end
  return n
end
local function listed(buf, lhs) return wk_lists(buf, "n", lhs) ~= nil end
-- gra needs a code-action server, as pyrefly and ruff are; once it is listed the buffer's LSP keys are in place
local function synced(buf) return (wk_wait(buf, "n", "gra", true, 10000)) end
local function open(file, server)
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  local missing, why = wait_attach(buf, { server }, 20000)
  check(file .. ": " .. server .. " attaches", #missing == 0, vim.inspect(why))
  check(file .. ": LSP keys synced", synced(buf))
  return buf
end
local before = specs()
check("which-key has a <leader>Te spec", before > 0, before)

local pbuf = open("withproj/app.py", "pyrefly")
check("python with pyrefly: <leader>Te listed", (wk_wait(pbuf, "n", "<leader>Te", true)))
local lbuf = open("scratch.lua", "lua_ls")
check("lua: <leader>Te not listed", not listed(lbuf, "<leader>Te"), wk_lists(lbuf, "n", "<leader>Te"))
check("which-key: opening buffers adds no <leader>Te spec", specs() == before, before .. " -> " .. specs())

-- pyrefly off: the toggle goes from its buffer, and a new python buffer never gets it
vim.lsp.enable("pyrefly", false)
check("python after pyrefly detached: <leader>Te not listed", (wk_wait(pbuf, "n", "<leader>Te", false, 10000)))
local rbuf = open("noproj/app.py", "ruff")
check("python without pyrefly: pyrefly not attached", #vim.lsp.get_clients({ bufnr = rbuf, name = "pyrefly" }) == 0)
check("python without pyrefly: <leader>Te not listed", not listed(rbuf, "<leader>Te"))
