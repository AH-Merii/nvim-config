-- @desc     treesitter highlights, indents and parses injections; textobjects, ]f/[f/]F motions and +/- node selection work; parserless buffers keep builtin ap
-- @areas    treesitter keys
-- @budget   30
local function ts_active(buf) return vim.treesitter.highlighter.active[buf] ~= nil end
vim.cmd.edit("main.lua")
local buf = vim.api.nvim_get_current_buf()
check("lua: highlighter active", wait_until(function() return ts_active(buf) end, 3000))
vim.v.errmsg = ""
local before = vim.api.nvim_buf_get_lines(buf, 2, 6, false)
vim.cmd("3,6normal! ==")
check("lua: reindenting indented code changes nothing", vim.v.errmsg == "" and vim.deep_equal(before, vim.api.nvim_buf_get_lines(buf, 2, 6, false)), vim.v.errmsg)

vim.api.nvim_win_set_cursor(0, { 4, 4 })
feed("vaf<Esc>")
check("lua: vaf selects the function", vim.fn.line("'<") == 3 and vim.fn.line("'>") >= 6, vim.fn.line("'<") .. "-" .. vim.fn.line("'>"))
vim.api.nvim_win_set_cursor(0, { 4, 4 })
feed("vif<Esc>")
check("lua: vif selects the body", vim.fn.line("'<") == 4 and vim.fn.line("'>") == 5, vim.fn.line("'<") .. "-" .. vim.fn.line("'>"))
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("]f")
check("lua: ]f jumps to the next function", vim.fn.line(".") == 3, vim.fn.line("."))
feed("]F")
check("lua: ]F jumps to the function end", vim.fn.line(".") == 6, vim.fn.line("."))
feed("[f")
check("lua: [f jumps back to the function start", vim.fn.line(".") == 3, vim.fn.line("."))

vim.api.nvim_win_set_cursor(0, { 4, 6 })
local node = vim.treesitter.get_node_text(assert(vim.treesitter.get_node()), 0)
feed("<space>v")
local m1 = vim.fn.mode()
local s1 = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."))
feed("++")
local s2 = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."))
feed("-")
local s3 = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."))
feed("<Esc>")
check("lua: <leader>v selects the node under the cursor", m1 == "v" and table.concat(s1, "\n") == node, m1 .. " " .. vim.inspect(s1) .. " want " .. node)
check("lua: + grows the selection", #table.concat(s2, "\n") > #table.concat(s1, "\n"), vim.inspect(s2))
check("lua: - shrinks it again", #table.concat(s3, "\n") < #table.concat(s2, "\n"), vim.inspect(s3))

vim.cmd.edit("notes.md")
local mbuf = vim.api.nvim_get_current_buf()
check("markdown: highlighter active", wait_until(function() return ts_active(mbuf) end, 3000))
local ok_parse, perr = pcall(function() vim.treesitter.get_parser(mbuf):parse(true) end)
check("markdown: injections parse", ok_parse, perr)

vim.cmd.edit("app.py")
local pbuf = vim.api.nvim_get_current_buf()
check("python: highlighter active", wait_until(function() return ts_active(pbuf) end, 3000))

-- toml is not in ensure_installed: the FileType hook installs it on demand when missing, then attaches
vim.cmd.edit("pyproject.toml")
local tbuf = vim.api.nvim_get_current_buf()
check("toml: parser outside ensure_installed attaches", wait_until(function() return ts_active(tbuf) end, 20000))

vim.cmd.edit("app.conf")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("dap")
check("conf (no parser): builtin dap deletes the paragraph", vim.api.nvim_buf_line_count(0) == 1 and vim.api.nvim_get_current_line() == "", vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false)))
vim.cmd("edit!")
