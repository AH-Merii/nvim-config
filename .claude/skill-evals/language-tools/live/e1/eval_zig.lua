-- @desc     eval e1: zls attaches to a Zig buffer, and conform reformats it with zig fmt (not LSP formatting)
-- @areas    eval
-- @budget   60
vim.fn.writefile({ "pub fn main() void {", "const   x:u8=1;", "_ = x;", "}" }, "main.zig")
vim.cmd.edit("main.zig")
local buf = vim.api.nvim_get_current_buf()
check("main.zig is a zig buffer", vim.bo[buf].filetype == "zig", vim.bo[buf].filetype)
local missing, why = wait_attach(buf, { "zls" }, 30000)
check("zls attaches to main.zig", #missing == 0, table.concat(why, "; "))
local ok, err = pcall(require("conform").format, { bufnr = buf, async = false, timeout_ms = 20000, lsp_format = "never" })
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
check("conform's formatter rewrites main.zig as zig fmt does", ok and vim.deep_equal(lines, { "pub fn main() void {", "    const x: u8 = 1;", "    _ = x;", "}" }),
  tostring(err) .. " | " .. table.concat(lines, " | "))
