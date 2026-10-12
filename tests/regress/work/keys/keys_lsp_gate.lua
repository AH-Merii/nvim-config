-- @desc     every method-gated LSP key in core.lsp's table exists in a buffer iff an attached client supports its method, through attach, detach, dynamic (un)registration, a second client, and ftplugin maps
-- @areas    keys lsp which-key
-- @budget   30
-- Ported from nvim-sbx-keys/checks2/lsp_gate.lua. In-process fake servers, so no Mason package is needed.

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
local function client_dynamic(m)
  local td = vim.lsp.protocol.make_client_capabilities().textDocument or {}
  local short = m:gsub("^textDocument/", "")
  local key = ({ prepareCallHierarchy = "callHierarchy" })[short] or short
  return td[key] ~= nil and td[key].dynamicRegistration == true
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
local function global_map(mode, lhs)
  local raw = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
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
local DIR = FIX .. "/.nvr-lsp"
vim.fn.mkdir(DIR, "p")
local function scratch(name)
  vim.cmd.edit(DIR .. "/" .. name)
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "sbxfake"
  flush()
  return buf
end

local ok_lsp, core_lsp = pcall(require, "core.lsp")
local keys = ok_lsp and type(core_lsp) == "table" and core_lsp.keys or nil
if not check("core.lsp exposes its gated key table", type(keys) == "table", "require('core.lsp').keys is " .. type(keys)) then return end

section("table entries")
for _, key in ipairs(keys) do
  expect(key[2] ~= nil, "entry %s %s has an rhs", table.concat(modes(key), ""), key[1])
  expect(#methods_of(key) > 0 or key.when ~= nil, "entry %s has a method or a condition", key[1])
end

-- entries with a non-LSP condition (`when`) are judged by keys_format_gate and keys_diag_gate
local function lsp_only(key) return key.when == nil end
local all = {}
for _, key in ipairs(keys) do
  for _, m in ipairs(methods_of(key)) do all[m] = true end
end
local methods = vim.tbl_keys(all)
table.sort(methods)
local S1, S2 = {}, {}
for i, m in ipairs(methods) do table.insert(i % 2 == 1 and S1 or S2, m) end
local function set(list)
  local s = {}
  for _, m in ipairs(list) do s[m] = true end
  return s
end
local function round(label, buf, supported)
  for _, key in ipairs(keys) do
    if lsp_only(key) then
      local want = false
      for _, m in ipairs(methods_of(key)) do want = want or supported[m] == true end
      for _, mode in ipairs(modes(key)) do
        local has = buf_map(buf, mode, key[1]) ~= nil
        expect(has == want, "[%s] %s %s map %s, want %s", label, mode, key[1], has and "present" or "absent", want and "present" or "absent")
      end
    end
  end
end
info("methods in table: " .. table.concat(methods, " "))

section("attach and detach")
expect(#methods > 0, "the table has method-gated entries")
round("no client", scratch("none.sbxfake"), {})
-- one client each with half the methods: every single-method entry is seen present and absent
local b1 = scratch("half.sbxfake")
local c1 = start_fake(b1, "fake-S1", S1)
round("client S1", b1, set(S1))
stop(c1)
round("S1 stopped", b1, {})
local c2 = start_fake(b1, "fake-S2", S2)
round("client S2", b1, set(S2))
stop(c2)
round("S2 stopped", b1, {})

section("dynamic registration")
local dyn = vim.tbl_filter(client_dynamic, methods)
expect(#dyn > 0, "the table has methods nvim accepts by dynamic registration")
local b3 = scratch("dyn.sbxfake")
local c3 = start_fake(b3, "fake-dyn", {})
round("dyn before register", b3, {})
server_request(c3, "client/registerCapability", { registrations = vim.tbl_map(function(m) return { id = m, method = m } end, dyn) })
round("dyn registered", b3, set(dyn))
server_request(c3, "client/unregisterCapability", { unregisterations = vim.tbl_map(function(m) return { id = m, method = m } end, dyn) })
round("dyn unregistered", b3, {})
stop(c3)

section("two clients")
local b4 = scratch("two.sbxfake")
local ca = start_fake(b4, "fake-all", methods)
local cb = start_fake(b4, "fake-S1b", S1)
round("two clients", b4, set(methods))
stop(ca)
round("all-client stopped, S1 remains", b4, set(S1))
stop(cb)
round("both stopped", b4, {})

section("ftplugin maps kept")
local b5 = scratch("foreign.sbxfake")
local foreign = {}
for _, key in ipairs(keys) do
  if lsp_only(key) then
    for _, mode in ipairs(modes(key)) do
      local f = function() end
      foreign[mode .. key[1]] = f
      vim.keymap.set(mode, key[1], f, { buf = b5 })
    end
  end
end
local function foreign_kept(label)
  for _, key in ipairs(keys) do
    if lsp_only(key) then
      for _, mode in ipairs(modes(key)) do
        local m = buf_map(b5, mode, key[1])
        expect(m ~= nil and m.callback == foreign[mode .. key[1]], "[%s] %s %s ftplugin map kept", label, mode, key[1])
      end
    end
  end
end
local c5 = start_fake(b5, "fake-all5", methods)
foreign_kept("attached")
stop(c5)
foreign_kept("detached")

section("runtime gr* and gO maps gated")
-- read from a --clean nvim of the same binary, so the list follows the runtime
local tmp = vim.fn.tempname()
vim.system({ vim.v.progpath, "--clean", "--headless", "-c",
  ([[lua local t = {} for _, mode in ipairs({ "n", "x" }) do for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do if m.lhs:match("^gr") or m.lhs == "gO" then t[#t + 1] = mode .. " " .. m.lhs end end end vim.fn.writefile(t, %q)]]):format(tmp),
  "-c", "qa!" }):wait()
local builtins = vim.fn.filereadable(tmp) == 1 and vim.fn.readfile(tmp) or {}
info("runtime built-ins: " .. table.concat(builtins, ", "))
expect(#builtins > 0, "the runtime defines gr* maps")
local b6 = scratch("builtin.sbxfake")
local b7 = scratch("builtin-all.sbxfake")
local c7 = start_fake(b7, "fake-all7", methods)
for _, line in ipairs(builtins) do
  local mode, lhs = line:match("^(%S+) (%S+)$")
  expect(global_map(mode, lhs) == nil, "built-in %s %s is not global", mode, lhs)
  expect(buf_map(b6, mode, lhs) == nil and global_map(mode, lhs) == nil, "built-in %s %s absent without a client", mode, lhs)
  expect(buf_map(b7, mode, lhs) ~= nil, "built-in %s %s present with a supporting client", mode, lhs)
end
stop(c7)

section("modifier-key lhs")
-- Neovim stores <C-x> in lhsraw in its internal form; the simplified form is in lhsrawalt
local probe = { "<C-x>Q", function() end, desc = "probe: modifier key", method = "textDocument/rename" }
table.insert(keys, probe)
local b8 = scratch("modifier.sbxfake")
local c8 = start_fake(b8, "fake-mod", { "textDocument/rename" })
expect(buf_map(b8, "n", probe[1]) ~= nil, "modifier key mapped while supported")
stop(c8)
expect(buf_map(b8, "n", probe[1]) == nil, "modifier key removed once no client supports it")
table.remove(keys)
done()
