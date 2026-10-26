-- @desc     K's hover float shows pyrefly's docstring cleaned (features/hover_docstring/: no &nbsp; indent, a Google section as a list, a dropped callout marker quoted), and another server's hover as it came
-- @areas    lsp ui
-- @budget   30
-- In-process fake servers answer K with a recorded pyrefly 1.4.0 hover shape (torch 2.14.1 torch.cat's Args and
-- huggingface_hub 2.3.0 HfApi.create_commit's callout, shortened): one named pyrefly, as the clean-up is keyed by the
-- client's name, and one named otherwise. The file K is pressed in has no filetype, so no real server attaches.
local HOVER = table.concat({
  "```python",
  "(function) cat: def cat(tensors: list[Tensor], dim: int = 0) -> Tensor: ...",
  "```",
  "---",
  "Concatenates the given sequence of tensors.  ",
  "  ",
  "[!WARNING]  ",
  "The input list will be mutated.  ",
  "  ",
  "Args:  ",
  "&nbsp;&nbsp;&nbsp;&nbsp;tensors (sequence of Tensors): Non-empty tensors provided must have the same shape,  ",
  "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;except in the cat dimension.  ",
  "&nbsp;&nbsp;&nbsp;&nbsp;dim (int, optional): the dimension",
  "",
  "Go to [Tensor](file:///site-packages/torch/_tensor.py#L102,7)",
}, "\n")

vim.fn.writefile({ "torch.cat(xs)", "torch.cat(ys)" }, "hover.nvrsrc")
vim.cmd.edit("hover.nvrsrc")
local src = vim.api.nvim_get_current_buf()

--- Starts a fake server that answers every hover with HOVER
local function start(name)
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
  local id = vim.lsp.start({ name = name, cmd = cmd, root_dir = FIX }, { bufnr = src })
  check("the fake " .. name .. " server attaches", wait_until(function()
    local c = id and vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized and vim.lsp.buf_is_attached(src, id)
  end, 3000))
  return id
end

--- K's float lines, the float closed after
local function hover()
  vim.api.nvim_win_set_cursor(0, { 1, 7 })
  feed("K")
  local win
  wait_until(function()
    win = vim.b[src].lsp_floating_preview
    return win ~= nil and vim.api.nvim_win_is_valid(win)
  end, 3000)
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
  vim.api.nvim_win_close(win, true)
  return lines
end

local function has(lines, line) return vim.list_contains(lines, line) end

local id = start("pyrefly")
local lines = hover()
local text = table.concat(lines, "\n")
check("pyrefly's hover float has no &nbsp; left", #lines > 0 and not text:find("&nbsp;", 1, true), text)
check("pyrefly's Args section is a bold header over entries",
  has(lines, "**Args:**") and has(lines, "- `tensors` (sequence of Tensors): Non-empty tensors provided must have the same shape,")
    and has(lines, "  except in the cat dimension."), text)
check("pyrefly's dropped callout marker is quoted again", has(lines, "> [!WARNING]") and has(lines, "> The input list will be mutated."), text)
check("the Go to footer is kept", text:find("Go to [Tensor]", 1, true) ~= nil, text)
vim.lsp.get_client_by_id(id):stop(true)
wait_until(function() return vim.lsp.get_client_by_id(id) == nil end, 3000)

start("nvr_other")
lines = hover()
text = table.concat(lines, "\n")
check("another server's hover is not cleaned", text:find("&nbsp;&nbsp;&nbsp;&nbsp;tensors", 1, true) ~= nil, text)
