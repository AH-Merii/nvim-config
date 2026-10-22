-- @desc     render-markdown loaded while a markdown file is current, as snacks' markdown preview loads it (by requiring it), leaves that file unrendered and still renders the LSP floats
-- @areas    lsp ui
-- @budget   20
-- @args     notes.md
-- Its plugin/ file attaches the current buffer as it loads (render-markdown/plugin/render-markdown.lua). Rendered
-- means render-markdown's extmarks in the buffer (namespace render-markdown.nvim, lua/render-markdown/core/ui.lua).
local function marks(buf)
  local ns = vim.api.nvim_get_namespaces()["render-markdown.nvim"]
  return ns and #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) or 0
end

local notes = vim.api.nvim_get_current_buf()
check("precondition: notes.md is a markdown file", vim.bo[notes].filetype == "markdown" and vim.bo[notes].buftype == "")
-- snacks/picker/util/markdown.lua requires it the same way, before its first markdown preview
check("requiring render-markdown loads it", pcall(require, "render-markdown"))
feed("jj")
-- a render that never comes is waited for 500 ms; render-markdown renders 100 ms after a change (its debounce)
wait_until(function() return marks(notes) > 0 end, 500)
check("the markdown file that was current when it loaded is not rendered", marks(notes) == 0, marks(notes))

-- the float K opens, from the same function
local buf, win = vim.lsp.util.open_floating_preview({ "# Doc", "", "Some **text**.", "", "```lua", "print(1)", "```" }, "markdown", {})
check("an LSP float is rendered", wait_until(function() return marks(buf) > 0 end, 3000), marks(buf))
vim.api.nvim_win_close(win, true)
