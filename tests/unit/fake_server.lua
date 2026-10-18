-- An in-process language server for unit tests, started through the real vim.lsp with cmd as a Lua function
-- (:h vim.lsp.ClientConfig), as tests/regress/checks/keys_lsp_gate.lua does. The test controls its capabilities,
-- registers capabilities later (client/registerCapability) and reads the requests it received.
--
--   local srv = require("fake_server").start({ buf = buf, methods = { "textDocument/hover" } })
--   srv.client():supports_method("textDocument/hover", buf)  -- true
--   srv.register({ "textDocument/formatting" })
--   srv.requests                                             -- { { method = "initialize", params = … }, … }
--   srv.stop()

local M = {}

---@param cond fun(): boolean
---@param what string
local function wait(cond, what)
  if not vim.wait(3000, cond, 5) then
    error("fake server: timed out waiting for " .. what, 3)
  end
end

--- Runs what handlers scheduled; two rounds cover a schedule made from a scheduled callback.
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait(function() return ran end, "the event loop")
  end
end

--- Server capabilities that support exactly methods, e.g. { "textDocument/hover" } -> { hoverProvider = true }.
---@param methods string[]
---@return lsp.ServerCapabilities
function M.capabilities(methods)
  local caps = {}
  for _, method in ipairs(methods) do
    local path = assert(vim.lsp.protocol._request_name_to_server_capability[method], "no server capability for " .. method)
    local t = caps
    for i = 1, #path - 1 do
      t[path[i]] = t[path[i]] or {}
      t = t[path[i]]
    end
    t[path[#path]] = true
  end
  return caps
end

---@class fake.Server
---@field id integer the client's id
---@field client fun(): vim.lsp.Client? nil once stopped
---@field requests { method: string, params: any }[] every request the client sent, initialize first
---@field notifications { method: string, params: any }[] every notification the client sent
---@field register fun(methods: string[]) sends client/registerCapability for methods and waits for it to apply
---@field unregister fun(methods: string[]) sends client/unregisterCapability for methods
---@field stop fun() stops the client and waits until it is gone

--- Starts a server attached to opts.buf and waits until it is initialized.
---@param opts { buf: integer, name?: string, methods?: string[], capabilities?: lsp.ServerCapabilities, handlers?: table<string, fun(params: any): any>, root_dir?: string }
---@return fake.Server
function M.start(opts)
  local srv = { requests = {}, notifications = {} }
  local dispatchers ---@type vim.lsp.rpc.Dispatchers
  local capabilities = opts.capabilities or M.capabilities(opts.methods or {})
  local handlers = opts.handlers or {}

  ---@param d vim.lsp.rpc.Dispatchers
  ---@return vim.lsp.rpc.PublicClient
  local function cmd(d)
    dispatchers = d
    local closing, id = false, 0
    local function close()
      if not closing then
        closing = true
        vim.schedule(function() d.on_exit(0, 15) end)
      end
    end
    return {
      request = function(method, params, callback)
        id = id + 1
        table.insert(srv.requests, { method = method, params = params })
        local result = vim.NIL
        if method == "initialize" then
          result = { capabilities = capabilities }
        elseif handlers[method] then
          result = handlers[method](params)
        end
        vim.schedule(function() callback(nil, result) end)
        return true, id
      end,
      notify = function(method, params)
        table.insert(srv.notifications, { method = method, params = params })
        if method == "exit" then
          close()
        end
        return true
      end,
      is_closing = function() return closing end,
      terminate = close,
    }
  end

  local root = opts.root_dir or vim.fn.getcwd()
  local id = vim.lsp.start({ name = opts.name or "fake", cmd = cmd, root_dir = root }, { bufnr = opts.buf, reuse_client = function() return false end })
  assert(id, "fake server: vim.lsp.start returned no client")
  srv.id = id
  function srv.client() return vim.lsp.get_client_by_id(id) end
  wait(function()
    local client = srv.client()
    return client ~= nil and client.initialized and vim.lsp.buf_is_attached(opts.buf, id)
  end, "the client to attach")
  flush()

  ---@param method string
  ---@param params table
  local function server_request(method, params)
    dispatchers.server_request(method, params)
    flush()
  end
  function srv.register(methods)
    server_request("client/registerCapability", { registrations = vim.tbl_map(function(m) return { id = m, method = m } end, methods) })
  end
  function srv.unregister(methods)
    server_request("client/unregisterCapability", { unregisterations = vim.tbl_map(function(m) return { id = m, method = m } end, methods) })
  end
  function srv.stop()
    local client = srv.client()
    if client then
      client:stop(true)
    end
    wait(function() return srv.client() == nil end, "the client to stop")
    flush()
  end
  return srv
end

return M
