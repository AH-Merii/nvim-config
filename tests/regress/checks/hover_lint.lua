-- @desc     an LSP hover float (filetype markdown, buftype nofile) is not linted when K opens it nor when K again focuses it, while a markdown file is linted by the same linter
-- @areas    lint lsp
-- @budget   30
-- markdownlint-cli2 is a fake in the fixture's node_modules/.bin, which the resolver finds first (lua/tools/init.lua):
-- it logs the first line of each text it is given. The hover comes from an in-process fake server.
local LOG = FIX .. "/markdownlint.log"
local bin = FIX .. "/node_modules/.bin/markdownlint-cli2"
vim.fn.mkdir(vim.fs.dirname(bin), "p")
vim.fn.writefile({
  "#!/bin/sh",
  'if [ "$1" = --version ]; then echo "markdownlint-cli2 v0.20.0"; exit 0; fi',
  "{ printf 'linted: '; head -n 1; } >> '" .. LOG .. "'",
  "cat > /dev/null",
}, bin)
vim.fn.setfperm(bin, "rwxr-xr-x")
local found = require("tools").wait("markdownlint-cli2", FIX, 10000)
if not check("precondition: the resolver finds the fake markdownlint-cli2", found ~= nil and found.path == bin, vim.inspect(found)) then
  return
end

local function log() return vim.fn.filereadable(LOG) == 1 and vim.fn.readfile(LOG) or {} end
--- Whether a lint of a text starting with first ran within 1 s
local function linted(first)
  return wait_until(function() return vim.list_contains(log(), "linted: " .. first) end, 1000)
end

local HOVER_FIRST = "nvr hover text"
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
        result = { contents = { kind = "markdown", value = HOVER_FIRST .. "\n\n```lua\nlocal x = 1\n```" } }
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
  check("precondition: the float is a nofile markdown buffer", vim.bo[buf].filetype == "markdown" and vim.bo[buf].buftype == "nofile")
  check("opening the hover float does not lint it", not linted(HOVER_FIRST), vim.inspect(log()))
  -- the second K focuses the float once its hover request is answered (runtime lua/vim/lsp/util.lua, focus_id)
  feed("K")
  check("precondition: K again focuses the float", wait_until(function() return vim.api.nvim_get_current_win() == win end, 3000))
  check("focusing the hover float does not lint it", not linted(HOVER_FIRST), vim.inspect(log()))
  vim.api.nvim_win_close(win, true)
end

vim.cmd.edit("notes.md")
check("a markdown file is linted by the same linter", linted("# Title"), vim.inspect(log()))
