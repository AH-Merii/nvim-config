-- @desc     the Trouble modes the keymaps use (diagnostics, a one-item qflist, symbols) open a Trouble window without error or auto-jump
-- @areas    ui lsp
-- @budget   40
-- @needs    lua-language-server
local function trouble_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "trouble" then return w end
  end
end
vim.cmd.edit("main.lua")
local buf, main_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local missing, why = wait_attach(buf, { "lua_ls" }, 15000)
check("lua_ls attached", #missing == 0, table.concat(why, "; "))

-- lua_ls answers documentSymbol with nothing until it has read the file; ask until it has symbols
local has_symbols, pending = false, false
local params = { textDocument = vim.lsp.util.make_text_document_params(buf) }
wait_until(function()
  if not pending then
    pending = true
    vim.lsp.buf_request_all(buf, "textDocument/documentSymbol", params, function(res)
      pending = false
      for _, r in pairs(res or {}) do
        if r.result and r.result[1] then has_symbols = true end
      end
    end)
  end
  return has_symbols
end, 20000)
check("precondition: lua_ls returns document symbols", has_symbols)
check("precondition: main.lua has diagnostics", #wait_diagnostics(buf, nil, 15000) > 0)

-- one item: trouble v3 reads a leftover v2 `auto_jump = {}` as true and jumps instead of opening
vim.fn.setqflist({ { filename = vim.api.nvim_buf_get_name(buf), lnum = 5, col = 1, text = "item" } })
for _, mode in ipairs({ "diagnostics", "qflist", "symbols" }) do
  vim.fn.win_gotoid(main_win)
  vim.v.errmsg = ""
  local ok, err = pcall(vim.cmd, "Trouble " .. mode .. " open")
  wait_until(function() return trouble_win() ~= nil end, 3000)
  check("Trouble " .. mode .. " opens", ok and vim.v.errmsg == "" and trouble_win() ~= nil, err or (vim.v.errmsg ~= "" and vim.v.errmsg or nil))
  pcall(vim.cmd, "Trouble " .. mode .. " close")
  wait_until(function() return trouble_win() == nil end, 2000)
end
