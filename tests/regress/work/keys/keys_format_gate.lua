-- @desc     the format keys in core.lsp's table exist in a buffer iff conform has a formatter configured for its filetype (list, function or a dot-part of the filetype) or an attached client formats, and the normal-mode one runs conform
-- @areas    keys format lsp
-- @budget   20
-- Ported from nvim-sbx-keys/checks2/format.lua. Controlled conform.formatters_by_ft entries and fake servers.

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

local function caps_for(methods)
  local caps = {}
  for _, m in ipairs(methods) do
    local path = assert(vim.lsp.protocol._request_name_to_server_capability[m], "no capability path for " .. m)
    local t = caps
    for i = 1, #path - 1 do
      t[path[i]] = t[path[i]] or {}
      t = t[path[i]]
    end
    t[path[#path]] = true
  end
  return caps
end
local servers = {}
-- an in-process server advertising exactly `methods`, attached to buf
local function start_fake(buf, name, methods)
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
        vim.schedule(function() callback(nil, method == "initialize" and { capabilities = caps_for(methods) } or vim.NIL) end)
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
local function server_request(id, method, params)
  local sent = false
  vim.schedule(function()
    servers[id].dispatchers.server_request(method, params)
    sent = true
  end)
  wait_until(function() return sent end, 2000)
  flush()
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
local DIR = FIX .. "/.nvr-fmt"
vim.fn.mkdir(DIR, "p")
local nbuf = 0
local function buf_of(ft)
  nbuf = nbuf + 1
  vim.cmd.edit(("%s/f%d.txt"):format(DIR, nbuf))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = ft
  flush()
  return buf
end

local ok_lsp, core_lsp = pcall(require, "core.lsp")
local keys = ok_lsp and type(core_lsp) == "table" and core_lsp.keys or nil
if not check("core.lsp exposes its gated key table", type(keys) == "table", "require('core.lsp').keys is " .. type(keys)) then return end
local conform = require("conform")

-- the format entries: gated by a non-LSP condition and by LSP format methods
local fmt_keys = vim.tbl_filter(function(k) return k.when ~= nil and #methods_of(k) > 0 end, keys)
info("format entries: " .. table.concat(vim.tbl_map(function(k) return table.concat(modes(k), "") .. ":" .. k[1] end, fmt_keys), " "))
if not check("the table has format entries", #fmt_keys > 0) then return end

local function judge(label, buf, configured, advertised)
  advertised = advertised or {}
  for _, key in ipairs(fmt_keys) do
    local want = configured
    for _, m in ipairs(methods_of(key)) do want = want or advertised[m] == true end
    for _, mode in ipairs(modes(key)) do
      local has = buf_map(buf, mode, key[1]) ~= nil
      expect(has == want, "[%s] %s %s: %s, want %s", label, mode, key[1], has and "present" or "absent", want and "present" or "absent")
    end
  end
end

section("conform configuration")
expect(conform.formatters_by_ft.sbxnone == nil, "precondition: no formatter for sbxnone")
judge("unconfigured ft, no client", buf_of("sbxnone"), false)
conform.formatters_by_ft.sbxlist = { "a_tool_that_is_not_installed" }
local blist = buf_of("sbxlist")
judge("formatter configured but not installed", blist, true)
conform.formatters_by_ft.sbxfn = function() return {} end
judge("formatter function that finds nothing yet", buf_of("sbxfn"), true)
judge("compound ft with a configured part", buf_of("sbxother.sbxlist"), true)
conform.formatters_by_ft.sbxlist = nil
vim.bo[blist].filetype = "sbxlist"
flush()
judge("config removed, FileType again", blist, false)

section("formatting clients")
local bl = buf_of("sbxnone")
local c1 = start_fake(bl, "fake-fmt", { "textDocument/formatting" })
judge("client formats", bl, false, { ["textDocument/formatting"] = true })
stop(c1)
judge("formatting client stopped", bl, false)
local c2 = start_fake(bl, "fake-range", { "textDocument/formatting", "textDocument/rangeFormatting" })
judge("client formats ranges", bl, false, { ["textDocument/formatting"] = true, ["textDocument/rangeFormatting"] = true })
stop(c2)
local bd = buf_of("sbxnone")
local c3 = start_fake(bd, "fake-late", {})
judge("late client before registering", bd, false)
server_request(c3, "client/registerCapability", { registrations = { { id = "f", method = "textDocument/formatting" } } })
judge("late client registered formatting", bd, false, { ["textDocument/formatting"] = true })
stop(c3)
judge("late client stopped", bd, false)

section("configured filetype with a client")
conform.formatters_by_ft.sbxboth = { "a_tool_that_is_not_installed" }
local bb = buf_of("sbxboth")
local c4 = start_fake(bb, "fake-both", { "textDocument/formatting", "textDocument/rangeFormatting" })
judge("configured and formatting client", bb, true)
stop(c4)
judge("configured, client stopped", bb, true)

section("the normal-mode format key runs conform")
local nkey = vim.tbl_filter(function(k) return vim.list_contains(modes(k), "n") and vim.list_contains(methods_of(k), "textDocument/formatting") end, fmt_keys)
local called = 0
-- the config's conform.format_buffer wrapper or conform.format itself
local orig_fb, orig_f = conform.format_buffer, conform.format
conform.format_buffer = orig_fb and function() called = called + 1 end
conform.format = function() called = called + 1 end
for _, key in ipairs(nkey) do
  local m = buf_map(bb, "n", key[1])
  if m and m.callback then pcall(vim.api.nvim_buf_call, bb, m.callback) end
end
conform.format_buffer, conform.format = orig_fb, orig_f
expect(called >= 1, "a format key runs conform (%d normal-mode entries, %d calls)", #nkey, called)
done()
