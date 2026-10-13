-- @desc     formatting a fish buffer through conform indents it with the resolved fish's builtin fish_indent
-- @areas    format tools
-- @budget   10
-- @needs    fish
local dir = FIX .. "/fish"
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ "if true", "echo hi", "end" }, dir .. "/config.fish")
vim.cmd.edit(dir .. "/config.fish")
local buf = vim.api.nvim_get_current_buf()
local ok, err = pcall(require("conform").format, { bufnr = buf, async = false, timeout_ms = 10000, lsp_format = "never" })
check("fish: conform.format runs", ok, err)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
check("fish: the body of the if is indented four spaces", vim.deep_equal(lines, { "if true", "    echo hi", "end" }), vim.inspect(lines))
