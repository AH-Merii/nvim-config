-- @desc     renaming a tag renames its pair through LSP linked editing when the attached server supports it, and does nothing without such a server
-- @areas    lsp editing
-- @budget   15
-- In-process fake servers, so no tool needs installing. The one that supports linked editing answers with the
-- tag names of the line, as vscode-html-language-server does.

-- the ranges of the opening and closing tag names on the cursor's line
local function tag_ranges(buf, line)
  local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
  local open_s, open_e = text:find("^<([%w]+)")
  local close_s, close_e = text:find("</[%w]+>$")
  if not (open_s and close_s) then
    return vim.NIL
  end
  local function range(s, e) return { start = { line = line, character = s }, ["end"] = { line = line, character = e } } end
  return { ranges = { range(open_s, open_e), range(close_s + 1, close_e - 1) } }
end

local answered = 0 -- linkedEditingRange requests the fakes answered

-- an in-process server attached to buf, advertising linked editing or not
local function start_fake(buf, name, linked)
  local function cmd(dispatchers)
    local closing, id = false, 0
    local function close()
      if not closing then
        closing = true
        vim.schedule(function() dispatchers.on_exit(0, 15) end)
      end
    end
    return {
      request = function(method, params, callback)
        id = id + 1
        local result = vim.NIL
        if method == "initialize" then
          result = { capabilities = { textDocumentSync = 1, linkedEditingRangeProvider = linked or nil } }
        elseif method == "textDocument/linkedEditingRange" then
          result = tag_ranges(buf, params.position.line)
        end
        vim.schedule(function()
          callback(nil, result)
          if method == "textDocument/linkedEditingRange" then answered = answered + 1 end
        end)
        return true, id
      end,
      notify = function(method)
        if method == "exit" then close() end
        return true
      end,
      is_closing = function() return closing end,
      terminate = close,
    }
  end
  local id = vim.lsp.start({ name = name, cmd = cmd, root_dir = FIX }, { bufnr = buf, reuse_client = function() return false end })
  wait_until(function()
    local c = id and vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized and vim.lsp.buf_is_attached(buf, id)
  end, 3000)
  return id
end

-- renames the opening tag "div" to "span" in a fresh buffer served by a fake server, and returns the line
local function rename_opening_tag(name, linked)
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "html"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "<div>x</div>" })
  start_fake(buf, name, linked)
  -- a session starts once linked editing has the ranges at the cursor, which it asks for when the cursor moves
  local before = answered
  vim.api.nvim_win_set_cursor(0, { 1, 2 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
  if linked then
    wait_until(function() return answered > before end, 3000)
  end
  feed("ciwspan<Esc>")
  -- feedkeys runs no main loop, so fire the TextChanged Neovim's main loop fires after the edit
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  wait_until(function() return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "<span>x</span>" end, linked and 2000 or 500)
  return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
end

local line = rename_opening_tag("nvr_linked", true)
check("with a server that supports linked editing, renaming the opening tag renames the closing one", line == "<span>x</span>", line)

line = rename_opening_tag("nvr_unlinked", false)
check("without one, the closing tag is left as it was", line == "<span>x</div>", line)
