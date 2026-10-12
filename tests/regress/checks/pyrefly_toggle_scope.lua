-- @desc     <leader>Te exists only in buffers pyrefly is attached to, goes when pyrefly detaches, and opening buffers adds no which-key spec for it
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
local function mapped(buf, lhs, mode)
  return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode or "n", false, true) end)
end
-- gra comes from the same LSP key sync as <leader>Te, so once it is there the sync has run
local function synced(buf) return wait_until(function() return mapped(buf, "gra").buffer == 1 end, 10000) end
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
check("python with pyrefly: <leader>Te mapped", wait_until(function() return mapped(pbuf, "<leader>Te").buffer == 1 end, 5000))
local lbuf = open("scratch.lua", "lua_ls")
check("lua: no <leader>Te", vim.tbl_isempty(mapped(lbuf, "<leader>Te")), vim.inspect(mapped(lbuf, "<leader>Te").desc))
check("which-key: opening buffers adds no <leader>Te spec", specs() == before, before .. " -> " .. specs())

-- pyrefly off: the toggle goes from its buffer, and a new python buffer never gets it
vim.lsp.enable("pyrefly", false)
check("python after pyrefly detached: <leader>Te gone", wait_until(function() return vim.tbl_isempty(mapped(pbuf, "<leader>Te")) end, 10000))
local rbuf = open("noproj/app.py", "ruff")
check("python without pyrefly: pyrefly not attached", #vim.lsp.get_clients({ bufnr = rbuf, name = "pyrefly" }) == 0)
check("python without pyrefly: no <leader>Te", vim.tbl_isempty(mapped(rbuf, "<leader>Te")))
