-- @desc     an LSP hover float (filetype markdown, buftype nofile) has spell off, while a markdown file and an oil buffer (buftype acwrite) keep it
-- @areas    editing lsp
-- @budget   20
-- An in-process fake server answers K, so no tool needs installing.
local HOVER = "```lua\nfunction M.greet(name: string)\n```\n\n---\n\nGreets **nmae**, a mispelled word."

-- the file K is pressed in: no filetype, so no server but the fake one attaches and only its hover shows
vim.fn.writefile({ "local M = {}", "function M.greet(name) end", "return M" }, "hover.nvrsrc")
vim.cmd.edit("hover.nvrsrc")
local src = vim.api.nvim_get_current_buf()
local function cmd(d)
  local closing = false
  local function close()
    if not closing then
      closing = true
      vim.schedule(function() d.on_exit(0, 15) end)
    end
  end
  return {
    request = function(method, _, callback)
      local result = vim.NIL
      if method == "initialize" then
        result = { capabilities = { hoverProvider = true } }
      elseif method == "textDocument/hover" then
        result = { contents = { kind = "markdown", value = HOVER } }
      end
      vim.schedule(function() callback(nil, result) end)
      return true, 1
    end,
    notify = function(method)
      if method == "exit" then close() end
      return true
    end,
    is_closing = function() return closing end,
    terminate = close,
  }
end
local id = vim.lsp.start({ name = "nvr_hover", cmd = cmd, root_dir = FIX }, { bufnr = src })
if not check("the fake hover server attaches", wait_until(function()
  local c = id and vim.lsp.get_client_by_id(id)
  return c ~= nil and c.initialized and vim.lsp.buf_is_attached(src, id)
end, 3000)) then
  return
end

vim.api.nvim_win_set_cursor(0, { 2, 12 })
feed("K")
local win
wait_until(function()
  win = vim.b[src].lsp_floating_preview
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end, 3000)
if check("K opens the hover float", win ~= nil and vim.api.nvim_win_is_valid(win)) then
  local buf = vim.api.nvim_win_get_buf(win)
  local what = ("filetype %s, buftype %s"):format(vim.bo[buf].filetype, vim.bo[buf].buftype)
  check("precondition: the float is a nofile markdown buffer", vim.bo[buf].filetype == "markdown" and vim.bo[buf].buftype == "nofile", what)
  check("the hover float has spell off", vim.wo[win].spell == false)
  vim.api.nvim_win_close(win, true)
end

check("precondition: spell is off in the source file's window", vim.wo.spell == false)
vim.cmd.edit("notes.md")
check("a markdown file has spell on", vim.wo.spell == true)

-- what oil.nvim makes for a directory: an acwrite buffer named oil://<dir>/, filetype oil
local oil = vim.api.nvim_create_buf(true, false)
vim.bo[oil].buftype = "acwrite"
vim.api.nvim_buf_set_name(oil, "oil://" .. FIX .. "/")
vim.api.nvim_set_current_buf(oil)
check("precondition: spell is off in the oil buffer before its filetype is set", vim.wo.spell == false)
vim.bo[oil].filetype = "oil"
check("an oil buffer (buftype acwrite) has spell on", vim.wo.spell == true)
