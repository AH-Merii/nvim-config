-- @desc     treesitter highlights, indents and parses injections; a language needs its injections' parsers, through inherited queries, bundled ones too; textobjects, ]f/[f/]F motions and +/- node selection work; parserless buffers keep builtin ap
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

-- toml's file in lua/lang/ names no parser: its own comes from get_lang, pre-seeded (headless runs never install, D120)
vim.cmd.edit("pyproject.toml")
local tbuf = vim.api.nvim_get_current_buf()
check("toml: highlighter active", wait_until(function() return ts_active(tbuf) end, 3000))

-- What a language needs, read from nvim-treesitter's queries
local parsers = require("parsers")
local function needs(ft) return parsers.needed(ft) end
check("python needs regex, which its injections name", vim.list_contains(needs("python"), "regex"), vim.inspect(needs("python")))
check("typescriptreact needs regex, through tsx's inherited typescript and ecma queries", needs("typescriptreact")[1] == "tsx" and vim.list_contains(needs("typescriptreact"), "regex"), vim.inspect(needs("typescriptreact")))
check("lua, which Neovim bundles, needs nvim-treesitter's lua, luadoc and luap", needs("lua")[1] == "lua" and vim.list_contains(needs("lua"), "luadoc") and vim.list_contains(needs("lua"), "luap"), vim.inspect(needs("lua")))
