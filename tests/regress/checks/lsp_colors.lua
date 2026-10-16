-- @desc     a language server's colors are drawn once each, as a symbol at the line's end in the color, and go with the server
-- @areas    ui
-- @budget   20
local buf

--- The end-of-line symbols drawn in buf, as { row (1-based), fg (hex) }, sorted
local function symbols()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_text_pos == "eol" and d.virt_text then
      local hl = vim.api.nvim_get_hl(0, { name = d.virt_text[1][2], link = false })
      out[#out + 1] = ("%d %06x"):format(m[2] + 1, hl.fg or 0)
    end
  end
  table.sort(out)
  return out
end

-- A language server's colors: an in-process server that reports two
vim.fn.writefile({ "first", "second", "third" }, "lsp.txt")
vim.cmd.edit("lsp.txt")
buf = vim.api.nvim_get_current_buf()
local function server(dispatchers)
  local closing = false
  return {
    request = function(method, _, callback)
      if method == "initialize" then
        callback(nil, { capabilities = { colorProvider = true, textDocumentSync = 1 } })
      elseif method == "textDocument/documentColor" then
        callback(nil, {
          { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 5 } }, color = { red = 1, green = 0, blue = 0, alpha = 1 } },
          { range = { start = { line = 2, character = 0 }, ["end"] = { line = 2, character = 5 } }, color = { red = 0, green = 0, blue = 1, alpha = 1 } },
        })
      else
        callback(nil, nil)
      end
      return true, 1
    end,
    notify = function() return true end,
    is_closing = function() return closing end,
    terminate = function()
      closing = true
      vim.schedule(function() dispatchers.on_exit(0, 15) end)
    end,
  }
end
local id = vim.lsp.start({ name = "fakecolors", cmd = server }, { bufnr = buf })
-- the built-in draws server colors while redrawing, which headless happens only when asked
wait_until(function()
  vim.cmd.redraw()
  return #symbols() >= 2
end, 3000)
check("each server color is drawn once, as the symbol at the line's end in its color",
  vim.deep_equal(symbols(), { "1 ff0000", "3 0000ff" }), vim.inspect(symbols()))
local client = id and vim.lsp.get_client_by_id(id)
if client then
  client:stop(true)
end
wait_until(function() return #symbols() == 0 end, 3000)
check("they go when the server stops", #symbols() == 0, vim.inspect(symbols()))
