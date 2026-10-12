-- @desc     the buffer-diagnostics keys in core.lsp's table exist in a buffer iff an LSP client is attached or nvim-lint has linters for its filetype (or a dot-part), with controlled entries, fake servers and the fixture files
-- @areas    keys lint lsp
-- @budget   40
-- @args     main.lua
-- @needs    lua-language-server
-- Ported from nvim-sbx-keys/checks2/diag.lua. lua_ls makes main.lua a buffer with a real client.

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
-- run what autocmds and handlers scheduled; two rounds cover a schedule made from a scheduled callback
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end

local servers = {}
-- an in-process server with no capabilities, attached to buf
local function start_fake(buf, name)
  local srv = {}
  local function cmd(dispatchers)
    srv.dispatchers = dispatchers
    local closing, id = false, 0
    local function close()
      if not closing then
        closing = true
        vim.schedule(function() dispatchers.on_exit(0, 15) end)
      end
    end
    return {
      request = function(method, _, callback)
        id = id + 1
        vim.schedule(function() callback(nil, method == "initialize" and { capabilities = {} } or vim.NIL) end)
        return true, id
      end,
      notify = function(method)
        if method == "exit" then close() end
        return true
      end,
      is_closing = function() return closing end,
      terminate = close,
    }
  end
  local id = vim.lsp.start({ name = name, cmd = cmd, root_dir = FIX }, { bufnr = buf, reuse_client = function() return false end })
  wait_until(function()
    local c = id and vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized and vim.lsp.buf_is_attached(buf, id)
  end, 3000)
  servers[id] = srv
  flush()
  return id
end
local function stop(id)
  local c = vim.lsp.get_client_by_id(id)
  if c then c:stop(true) end
  wait_until(function() return vim.lsp.get_client_by_id(id) == nil end, 3000)
  flush()
end
local function buf_map(buf, mode, lhs)
  local raw = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhsraw == raw or m.lhsrawalt == raw then return m end
  end
end
local function modes(key)
  local m = key.mode or "n"
  return type(m) == "table" and m or { m }
end
local function methods_of(key)
  if key.method == nil then return {} end
  return type(key.method) == "table" and key.method or { key.method }
end
local DIR = FIX .. "/.nvr-diag"
vim.fn.mkdir(DIR, "p")
local nbuf = 0
local function buf_of(ft)
  nbuf = nbuf + 1
  vim.cmd.edit(("%s/d%d.txt"):format(DIR, nbuf))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = ft
  flush()
  return buf
end

local ok_lsp, core_lsp = pcall(require, "core.lsp")
local keys = ok_lsp and type(core_lsp) == "table" and core_lsp.keys or nil
if not check("core.lsp exposes its gated key table", type(keys) == "table", "require('core.lsp').keys is " .. type(keys)) then return end
local lint = require("lint")

-- entries gated only by a non-LSP condition
local diag_keys = vim.tbl_filter(function(k) return k.when ~= nil and #methods_of(k) == 0 end, keys)
info("condition-only entries: " .. table.concat(vim.tbl_map(function(k) return k[1] end, diag_keys), " "))
if not check("the table has condition-only entries", #diag_keys > 0) then return end

local function judge(label, buf, want)
  for _, key in ipairs(diag_keys) do
    for _, mode in ipairs(modes(key)) do
      local has = buf_map(buf, mode, key[1]) ~= nil
      expect(has == want, "[%s] %s %s: %s, want %s", label, mode, key[1], has and "present" or "absent", want and "present" or "absent")
    end
  end
end

section("linters configured")
expect(lint.linters_by_ft.sbxnone == nil, "precondition: no linter for sbxnone")
local bn = buf_of("sbxnone")
judge("no linter, no client", bn, false)
lint.linters_by_ft.sbxlint = { "a_linter_that_is_not_installed" }
judge("linter configured", buf_of("sbxlint"), true)
judge("compound ft with a linted part", buf_of("sbxother.sbxlint"), true)
lint.linters_by_ft.sbxempty = {}
judge("empty linter list", buf_of("sbxempty"), false)

section("attached clients")
-- any attached client, whatever it supports, may publish diagnostics
local c1 = start_fake(bn, "fake-nothing")
judge("client with no capabilities", bn, true)
local c2 = start_fake(bn, "fake-nothing2")
stop(c1)
judge("one of two clients stopped", bn, true)
stop(c2)
judge("all clients stopped", bn, false)
local bl = buf_of("sbxlint")
stop(start_fake(bl, "fake-lint"))
judge("linted ft after its client stops", bl, true)

section("fixture files")
vim.fn.writefile({ "plain text" }, DIR .. "/plain.txt")
local any_client = false
for _, f in ipairs({ "main.lua", "app.conf", "main.go", DIR .. "/plain.txt" }) do
  vim.cmd.edit(f)
  local buf = vim.api.nvim_get_current_buf()
  local missing, why = wait_attach(buf, (lsp_expected(buf)), 15000)
  if #missing > 0 then info(f .. ": servers missing: " .. table.concat(why, "; ")) end
  flush()
  local ft = vim.bo[buf].filetype
  local clients = #vim.lsp.get_clients({ bufnr = buf })
  any_client = any_client or clients > 0
  local producer = clients > 0 or #(lint.linters_by_ft[ft] or {}) > 0
  judge(vim.fn.fnamemodify(f, ":t") .. " (producer " .. tostring(producer) .. ")", buf, producer)
end
expect(any_client, "some fixture buffer has a real client, so the client branch is exercised")
done()
