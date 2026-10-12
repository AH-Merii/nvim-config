-- @desc     pyrefly and ruff share one position encoding on python buffers, and ruff's columns, fixes and pyrefly hover stay right after multibyte text
-- @areas    lsp
-- @budget   45
-- @needs    pyrefly ruff
vim.cmd.edit("app.py")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { 's = "ééé"; import sys' })
local missing, why = wait_attach(buf, { "pyrefly", "ruff" }, 20000)
check("pyrefly and ruff attach to app.py", #missing == 0, table.concat(why, "; "))

local encodings = {}
for _, cl in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
  encodings[cl.offset_encoding] = (encodings[cl.offset_encoding] or "") .. cl.name .. " "
end
check("app.py clients share one position encoding", vim.tbl_count(encodings) == 1, vim.inspect(encodings))

local health_text = health("vim.lsp")
check("checkhealth vim.lsp completed", health_text ~= "TIMEOUT")
check("checkhealth reports no mixed position encodings", not health_text:find("different position encodings", 1, true),
  health_text:match("[^\n]*Buffer %d+:[^\n]*"))

vim.api.nvim_set_current_buf(buf)
local function unused_import(diags)
  for _, d in ipairs(diags) do
    if d.lnum == 0 and d.source == "Ruff" and d.code == "F401" then return d end
  end
end
local d = unused_import(wait_diagnostics(buf, function(ds) return unused_import(ds) ~= nil end, 15000))
local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
local sys_col = line:find("sys", 1, true) - 1
check("ruff F401 starts at the byte column of sys", d ~= nil and d.col == sys_col, d and ("col " .. d.col .. " in " .. line) or "no F401 on line 1")

vim.api.nvim_win_set_cursor(0, { 1, sys_col })
vim.lsp.buf.code_action({
  apply = true,
  filter = function(a, id) return vim.lsp.get_client_by_id(id).name == "ruff" and a.title:find("unused import") ~= nil end,
})
wait_until(function() return not vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]:find("sys", 1, true) end, 10000)
local fixed = vim.api.nvim_buf_get_lines(buf, 0, 2, false)
check("ruff's fix removes only the import", vim.trim(fixed[1]):gsub(";$", "") == 's = "ééé"' and fixed[2] == "import os", vim.inspect(fixed))

-- line 9 is print(add(1, "2"), ...); col 8 is inside add
local hover
vim.api.nvim_win_set_cursor(0, { 9, 8 })
vim.lsp.buf_request(buf, "textDocument/hover", function(cl) return vim.lsp.util.make_position_params(0, cl.offset_encoding) end, function(_, res, ctx)
  local cl = vim.lsp.get_client_by_id(ctx.client_id)
  if cl and cl.name == "pyrefly" then hover = res or false end
end)
wait_until(function() return hover ~= nil end, 10000)
local text = hover and vim.inspect(hover.contents) or ""
check("pyrefly hover still describes add", text:find("add", 1, true) ~= nil and text:find("int", 1, true) ~= nil, text:sub(1, 120))
vim.cmd("edit!")
