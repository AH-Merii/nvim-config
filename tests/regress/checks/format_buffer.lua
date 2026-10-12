-- @desc     format_buffer (<leader>lf) formats with the planned formatter, reports no-ops and missing formatters, and shows the formatter's own error text
-- @areas    format lsp
-- @budget   40
-- @version-sensitive
-- @needs    stylua terraform-ls
local c = require("conform")
local L = vim.log.levels
local harness_notify, real_format = vim.notify, c.format
local notes = {}
vim.notify = function(msg, level, opts) table.insert(notes, { msg = tostring(msg), level = level, title = opts and opts.title }) end

-- format_buffer is async; its single notification is the result
local function run(buf, args)
  notes = {}
  c.format_buffer(vim.tbl_extend("force", { async = true, bufnr = buf }, args or {}))
  wait_until(function() return #notes > 0 end, 10000)
  return notes[1] or { msg = "no notification", level = -1 }
end
local function readable(n, text) return n.level == L.ERROR and n.msg:find(text, 1, true) ~= nil and not n.msg:find("table: 0x", 1, true) end

vim.fn.mkdir("fmt", "p")
vim.fn.writefile({ "local   x  =  1", "return x" }, "fmt/bad.lua")
vim.cmd.edit("fmt/bad.lua")
local lbuf = vim.api.nvim_get_current_buf()
local n1 = run(lbuf)
local first = vim.api.nvim_buf_get_lines(lbuf, 0, 1, false)[1]
check("lua: stylua reformats the buffer", first == "local x = 1", first)
check("lua: an INFO note names the formatter", n1.level == L.INFO and n1.msg:find("stylua", 1, true) ~= nil, n1.msg)
local n2 = run(lbuf)
check("lua: a no-op run is reported at INFO, differently from an edit", n2.level == L.INFO and n2.msg ~= n1.msg, n2.msg)

vim.fn.writefile({ "plain text" }, "fmt/notes.txt")
vim.cmd.edit("fmt/notes.txt")
local nbuf = vim.api.nvim_get_current_buf()
local n3 = run(nbuf)
check("text: no formatter or LSP is a WARN, buffer untouched", n3.level == L.WARN and vim.api.nvim_buf_get_lines(nbuf, 0, -1, false)[1] == "plain text", n3.msg)

-- Each error shape conform's callback can deliver, whatever the Neovim version
local shapes = {
  { "plain lsp.ResponseError table", { code = -32603, message = "server said no" }, "server said no" },
  { "string error", "Formatter failed. See :ConformInfo", "Formatter failed. See :ConformInfo" },
}
for _, s in ipairs(shapes) do
  c.format = function(_, cb) cb(s[2]) end
  local n = run(lbuf)
  check(s[1] .. " is shown as text", readable(n, s[3]), n.msg)
end
c.format = real_format

-- Real server: terraform-ls refuses to format without the terraform CLI; 0.13 drops the error's __tostring
if vim.fn.executable("terraform") == 1 then
  info("terraform CLI on PATH: the real terraform-ls failure cannot be provoked, skipped")
else
  vim.fn.mkdir("tf", "p")
  vim.fn.writefile({ 'resource "null_resource" "x" {', '      a   = "b"', "}" }, "tf/main.tf")
  vim.cmd.edit("tf/main.tf")
  local tbuf = vim.api.nvim_get_current_buf()
  local missing, why = wait_attach(tbuf, { "terraformls" }, 20000)
  check("terraform-ls attached", #missing == 0, table.concat(why, "; "))
  local raw
  real_format({ async = true, bufnr = tbuf, quiet = true }, function(err) raw = err or false end)
  wait_until(function() return raw ~= nil end, 10000)
  check("precondition: LSP fallback fails with an error object", type(raw) == "table" and type(raw.message) == "string", vim.inspect(raw))
  if type(raw) == "table" and type(raw.message) == "string" then
    local n = run(tbuf)
    check("terraform-ls failure shows the server's message", readable(n, raw.message), n.msg)
  end
end
vim.notify = harness_notify
