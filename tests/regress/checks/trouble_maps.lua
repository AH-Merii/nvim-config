-- @desc     every Trouble command the config maps, global or a gated LSP key, opens a Trouble window without error and leaves eventignore as it was
-- @areas    ui lsp
-- @budget   60
-- @needs    lua-language-server
local function trouble_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "trouble" then return w end
  end
end
local function trouble_cmd(rhs)
  return type(rhs) == "string" and rhs:match("^<[Cc][Mm][Dd]>%s*(Trouble%s.-)<[Cc][Rr]>$") or nil
end

vim.cmd.edit("main.lua")
local buf, main_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local missing, why = wait_attach(buf, { "lua_ls" }, 15000)
if not check("lua_ls attached", #missing == 0, table.concat(why, "; ")) then return end

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

-- trouble loads in the deferred phase; this makes sure it has before its maps are read
require("app.plugins").load("trouble.nvim")
local ran = false
vim.schedule(function() ran = true end)
wait_until(function() return ran end, 1000)

-- the maps in the buffer, plus every key row's action (a gated row's map is an expr map that picks its action)
local cmds, seen = {}, {}
local function add(rhs, lhs)
  local cmd = trouble_cmd(rhs)
  if cmd and not seen[cmd] then
    seen[cmd] = true
    table.insert(cmds, { cmd = cmd, lhs = lhs })
  end
end
for _, mode in ipairs({ "n", "x" }) do
  for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do add(m.rhs, m.lhs) end
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do add(m.rhs, m.lhs) end
end
for _, row in ipairs(require("keys").list()) do add(row.action, row.lhs) end
if not check("the config maps Trouble commands", #cmds > 0) then return end

-- items for the list modes, and a cursor on M (line 3), which has a definition and references
vim.fn.setqflist({ { filename = vim.api.nvim_buf_get_name(buf), lnum = 5, col = 1, text = "item" } })
vim.fn.setloclist(main_win, { { filename = vim.api.nvim_buf_get_name(buf), lnum = 5, col = 1, text = "item" } })
for _, c in ipairs(cmds) do
  while trouble_win() do vim.api.nvim_win_close(trouble_win(), true) end
  vim.fn.win_gotoid(main_win)
  vim.api.nvim_win_set_cursor(main_win, { 3, 9 })
  local ei = vim.o.eventignore
  vim.v.errmsg = ""
  local ok, err = pcall(vim.cmd, c.cmd)
  local win = wait_until(trouble_win, 5000) and trouble_win() or nil
  local name = ("%s (%s)"):format(c.cmd, c.lhs)
  check(name .. " opens a Trouble window", ok and vim.v.errmsg == "" and win ~= nil,
    err or (vim.v.errmsg ~= "" and vim.v.errmsg or nil))
  check(name .. " leaves eventignore as it was", vim.o.eventignore == ei, ("%q, was %q"):format(vim.o.eventignore, ei))
  if win then
    local tw, mw = vim.api.nvim_win_get_position(win), vim.api.nvim_win_get_position(main_win)
    info(("%s: Trouble window at row %d col %d, editor at row %d col %d"):format(name, tw[1], tw[2], mw[1], mw[2]))
  end
  vim.o.eventignore = ei
  pcall(vim.cmd, "Trouble " .. c.cmd:match("^Trouble%s+(%S+)") .. " close")
  wait_until(function() return trouble_win() == nil end, 2000)
end
