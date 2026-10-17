-- @desc     a server's code lenses are drawn above their lines and <leader>Tc hides and shows them in that buffer; a server without code lenses gets no codeLens request and its buffer no <leader>Tc
-- @areas    lsp ui keys
-- @budget   20
-- In-process fake servers, so no tool needs installing: one sends two lenses, one has no codeLensProvider.

--- The code lenses drawn in buf, as "<row (1-based)> <text>", sorted
local function lenses(buf)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_lines and d.virt_lines_above then
      for _, line in ipairs(d.virt_lines) do
        local text = vim.iter(line):map(function(chunk) return chunk[1] end):join("")
        out[#out + 1] = ("%d %s"):format(m[2] + 1, vim.trim(text))
      end
    end
  end
  table.sort(out)
  return out
end

--- A fake server with the given capabilities that records the methods it is asked for
local function server(capabilities, asked)
  return function(dispatchers)
    local closing = false
    return {
      request = function(method, _, callback)
        asked[#asked + 1] = method
        if method == "initialize" then
          callback(nil, { capabilities = capabilities })
        elseif method == "textDocument/codeLens" then
          callback(nil, {
            { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 5 } }, command = { title = "run first", command = "fake.run" } },
            { range = { start = { line = 2, character = 2 }, ["end"] = { line = 2, character = 7 } }, command = { title = "2 references", command = "fake.refs" } },
          })
        else
          callback(nil, nil)
        end
        return true, #asked
      end,
      notify = function() return true end,
      is_closing = function() return closing end,
      terminate = function()
        closing = true
        vim.schedule(function() dispatchers.on_exit(0, 15) end)
      end,
    }
  end
end

local function has_toggle(buf)
  return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg("<leader>Tc", "n", false, true).buffer == 1 end)
end

-- A server without code lenses: asked for none, and its buffer gets no toggle
vim.fn.writefile({ "alpha", "beta" }, "nolens.txt")
vim.cmd.edit("nolens.txt")
local plain = vim.api.nvim_get_current_buf()
local plain_asked = {}
local plain_id = vim.lsp.start({ name = "fakeplain", cmd = server({ textDocumentSync = 1, hoverProvider = true }, plain_asked) }, { bufnr = plain })
wait_until(function() return vim.list_contains(plain_asked, "initialize") end, 3000)
-- an edit is where lenses are re-requested
vim.api.nvim_buf_set_lines(plain, 0, 1, false, { "alpha!" })
vim.cmd.redraw()
-- the hover key is how this config marks an attached server's buffer; wait for it so the gated keys have synced
wait_until(function() return vim.fn.maparg("K", "n", false, true).buffer == 1 end, 3000)
vim.wait(200)
check("a server without code lenses is asked for none", not vim.list_contains(plain_asked, "textDocument/codeLens"), table.concat(plain_asked, " "))
check("a buffer whose server has no code lenses gets no <leader>Tc", not has_toggle(plain))

-- A server with code lenses, which its config does not ask to draw, in two buffers side by side
local lens_config = { name = "fakelens", cmd = server({ textDocumentSync = 1, codeLensProvider = {} }, {}) }
vim.fn.writefile({ "first", "second", "  third" }, "other.txt")
vim.cmd.edit("other.txt")
local other = vim.api.nvim_get_current_buf()
local id = vim.lsp.start(lens_config, { bufnr = other })
vim.fn.writefile({ "first", "second", "  third" }, "lens.txt")
vim.cmd.vsplit("lens.txt")
local buf = vim.api.nvim_get_current_buf()
vim.lsp.start(lens_config, { bufnr = buf })
local want = { "1 run first", "3 2 references" }
-- the built-in draws lenses while redrawing, which headless happens only when asked
local drawn = wait_until(function()
  vim.cmd.redraw()
  return #lenses(buf) >= 2 and #lenses(other) >= 2
end, 3000)
check("each lens is drawn above its line", drawn and vim.deep_equal(lenses(buf), want), vim.inspect(lenses(buf)))

if check("the buffer gets <leader>Tc", wait_until(function() return has_toggle(buf) end, 3000)) then
  feed("<leader>Tc")
  wait_until(function()
    vim.cmd.redraw()
    return #lenses(buf) == 0
  end, 2000)
  check("<leader>Tc hides them", #lenses(buf) == 0, vim.inspect(lenses(buf)))
  check("only in that buffer", vim.deep_equal(lenses(other), want), vim.inspect(lenses(other)))
  feed("<leader>Tc")
  wait_until(function()
    vim.cmd.redraw()
    return #lenses(buf) >= 2
  end, 3000)
  check("<leader>Tc again shows them", vim.deep_equal(lenses(buf), want), vim.inspect(lenses(buf)))
end

for _, client_id in ipairs({ id, plain_id }) do
  local client = client_id and vim.lsp.get_client_by_id(client_id)
  if client then
    client:stop(true)
  end
end
