-- @desc     lua_ls attaches to a lua file and pyrefly to a python file, each returns completion items, and <leader>lf reformats lua with stylua and python with ruff
-- @areas    lsp completion format keys
-- @budget   40
-- @needs    lua-language-server pyrefly stylua ruff

-- ask the server until it returns items; a server still indexing answers with an empty list
local function completion_items(buf, name, row, col, ms)
  local client = vim.lsp.get_clients({ bufnr = buf, name = name })[1]
  if not client then return {}, name .. " not attached" end
  if not client:supports_method("textDocument/completion", buf) then return {}, name .. " has no completion" end
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = row, character = col } }
  local items, inflight, tries, last_err = nil, false, 0, nil
  wait_until(function()
    if items then return true end
    if not inflight then
      inflight, tries = true, tries + 1
      local sent = client:request("textDocument/completion", params, function(err, res)
        inflight, last_err = false, err
        local list = type(res) == "table" and (res.items or res) or {}
        if not err and #list > 0 then items = list end
      end, buf)
      if not sent then
        last_err = "request not sent, client stopped"
        return true
      end
    end
    return false
  end, ms)
  local labels = {}
  for i = 1, math.min(5, #(items or {})) do table.insert(labels, items[i].label) end
  return items or {}, string.format("%s, %d requests%s: %s", name, tries,
    last_err and (", last error " .. vim.inspect(last_err)) or "", table.concat(labels, ","))
end

local cases = {
  {
    file = "main.lua", server = "lua_ls",
    probe = "local x = vim.api.nvim_buf_",
    messy = "local   probe   =   {1,2}", want = "local probe = { 1, 2 }",
  },
  {
    file = "app.py", server = "pyrefly",
    probe = "os.pa",
    messy = "probe  =  [1,2]", want = "probe = [1, 2]",
  },
}

local runs = {}
vim.api.nvim_create_autocmd("User", {
  pattern = "ConformFormatPost",
  callback = function(a)
    local d = a.data or {}
    table.insert(runs, { name = d.formatter and d.formatter.name or "?", err = d.err })
  end,
})

for _, c in ipairs(cases) do
  vim.cmd.edit(c.file)
  local buf = vim.api.nvim_get_current_buf()
  local missing, why = wait_attach(buf, { c.server }, 20000)
  check(c.file .. ": " .. c.server .. " attaches", #missing == 0, table.concat(why, "; "))

  -- completion: a probe line before the last line (main.lua ends in `return M`), items asked at its end
  local n = vim.api.nvim_buf_line_count(buf) - 1
  vim.api.nvim_buf_set_lines(buf, n, n, false, { c.probe })
  local items, detail = completion_items(buf, c.server, n, #c.probe, 15000)
  check(c.file .. ": LSP completion returns items", #items > 0, #items .. " items from " .. detail)
  vim.api.nvim_buf_set_lines(buf, n, n + 1, false, {})

  -- formatting: a messy line before the last line, then the user's <leader>lf map
  n = vim.api.nvim_buf_line_count(buf) - 1
  vim.api.nvim_buf_set_lines(buf, n, n, false, { c.messy })
  runs = {}
  feed("<Esc><leader>lf")
  local function formatted() return vim.list_contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), c.want) end
  local function errored()
    for _, r in ipairs(runs) do
      if r.err then return true end
    end
    return false
  end
  wait_until(function() return formatted() or errored() end, 10000)
  local ran = vim.tbl_map(function(r) return r.name .. (r.err and (" failed: " .. tostring(r.err.message)) or "") end, runs)
  check(c.file .. ": <leader>lf formats", formatted(), string.format("formatters run: %s; line now: %s",
    #ran > 0 and table.concat(ran, ", ") or "none", tostring(vim.api.nvim_buf_get_lines(buf, n, n + 1, false)[1])))
  vim.cmd("silent! %bwipeout!")
end
