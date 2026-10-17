-- The in-process fake language server: a client attaches with the capabilities it is given, supports_method
-- follows a later registration, and the requests the client sends are logged.
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local server = require("fake_server")

local function scratch()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, h.tmpdir() .. "/a.txt")
  return buf
end

h.case("a client attaches with the given capabilities", function()
  local buf = scratch()
  local srv = server.start({ buf = buf, methods = { "textDocument/hover" } })
  local client = srv.client()
  h.ok(vim.lsp.buf_is_attached(buf, srv.id), "the client is attached to the buffer")
  h.eq(client:supports_method("textDocument/hover", buf), true, "hover, given")
  h.eq(client:supports_method("textDocument/rename", buf), false, "rename, not given")
  srv.stop()
  h.eq(srv.client(), nil, "the client once stopped")
end)

h.case("supports_method follows a later registration", function()
  local buf = scratch()
  local srv = server.start({ buf = buf })
  local client = srv.client()
  h.eq(client:supports_method("textDocument/formatting", buf), false, "formatting before registering")
  srv.register({ "textDocument/formatting" })
  h.eq(client:supports_method("textDocument/formatting", buf), true, "formatting once registered")
  srv.unregister({ "textDocument/formatting" })
  h.eq(client:supports_method("textDocument/formatting", buf), false, "formatting once unregistered")
  srv.stop()
end)

h.case("the requests a client sends are logged, with their params", function()
  local buf = scratch()
  local hover = { contents = { kind = "plaintext", value = "fake" } }
  local srv = server.start({ buf = buf, methods = { "textDocument/hover" }, handlers = { ["textDocument/hover"] = function() return hover end } })
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = 0, character = 0 } }
  local err, result = h.await(function(done) srv.client():request("textDocument/hover", params, done, buf) end)
  h.eq({ err, result }, { nil, hover }, "the reply")
  h.eq(srv.requests[1].method, "initialize", "the first request")
  h.eq(srv.requests[#srv.requests], { method = "textDocument/hover", params = params }, "the last request")
  srv.stop()
end)

h.finish()
