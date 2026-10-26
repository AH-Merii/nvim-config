-- @desc     render-markdown loads with the first LSP hover float, not at startup nor with a markdown file; it renders that float and later ones, each as tall as its rendered text (a table's virtual border line included), and never renders a markdown file
-- @areas    lsp ui
-- @budget   30
-- @args     notes.md
-- An in-process fake server answers K. Rendered means render-markdown's extmarks in the buffer (namespace
-- render-markdown.nvim, lua/render-markdown/core/ui.lua).
local NAME = "render-markdown.nvim"
local HOVER = table.concat({
  "```lua",
  "function M.greet(name: string)",
  "```",
  "",
  "---",
  "",
  "Greets **name**; see `M.bye`.",
  "",
  "- `name`: who to greet",
  "",
  "```lua",
  'M.greet("you")',
  "```",
  "",
  -- last, with no empty line under it: render-markdown draws its bottom border on a virtual line
  "| field | value |",
  "| --- | --- |",
  "| `a` | 1 |",
}, "\n")

local function loaded()
  for _, p in ipairs(require("app.plugins").list()) do
    if p.name == NAME then return p.loaded end
  end
end
local function marks(buf)
  local ns = vim.api.nvim_get_namespaces()["render-markdown.nvim"]
  return ns and #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) or 0
end

local notes = vim.api.nvim_get_current_buf()
check("precondition: notes.md is a markdown file", vim.bo[notes].filetype == "markdown" and vim.bo[notes].buftype == "")
check("render-markdown is not loaded at startup, nor by a markdown file", loaded() == false, vim.inspect(loaded()))

-- one window: the float's height is capped by the room in the window around the cursor
-- (runtime lua/vim/lsp/util.lua, make_floating_popup_options)
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

--- K on main.lua: the float, once render-markdown's marks are in it (or the wait ran out)
local function hover(which)
  vim.api.nvim_win_set_cursor(0, { 2, 12 })
  feed("K")
  local win
  wait_until(function()
    win = vim.b[src].lsp_floating_preview
    return win ~= nil and vim.api.nvim_win_is_valid(win) and marks(vim.api.nvim_win_get_buf(win)) > 0
  end, 3000)
  if not check(which .. " K opens the hover float", win ~= nil and vim.api.nvim_win_is_valid(win)) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  check(which .. " hover float is rendered", marks(buf) > 0, marks(buf))
  -- the window shows every line of the rendered text, with no empty row under it
  local height, text = vim.api.nvim_win_get_height(win), vim.api.nvim_win_text_height(win, {}).all
  check(which .. " hover float's height fits its rendered text", height == text, ("height %d, text %d"):format(height, text))
  vim.api.nvim_win_close(win, true)
end

hover("the first")
check("the first hover float loads render-markdown", loaded() == true)
hover("a later")

-- a markdown file shown, moved in and opened after render-markdown loaded
vim.cmd.buffer(notes)
feed("jj")
vim.cmd.edit("new.md")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "# New", "", "Some *text*.", "", "```lua", "print(1)", "```" })
feed("G")
local new = vim.api.nvim_get_current_buf()
-- a render that never comes is waited for 500 ms; render-markdown renders 100 ms after a change (its debounce)
wait_until(function() return marks(notes) > 0 or marks(new) > 0 end, 500)
check("a markdown file is not rendered", marks(notes) == 0, marks(notes))
check("a markdown file opened after render-markdown loaded is not rendered", marks(new) == 0, marks(new))
