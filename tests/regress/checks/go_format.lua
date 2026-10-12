-- @desc     formatting a Go buffer through conform leaves it gofmt-clean and adds the imports it uses
-- @areas    format
-- @budget   10
-- @needs    goimports gofumpt

-- judge with the gofmt of the Go that goimports runs with (its env PATH, from the suite's mise)
local goimports = require("tools").wait("goimports", FIX, 10000)
local gofmt_bin
for _, dir in ipairs(vim.split(goimports and goimports.env and goimports.env.PATH or "", ":", { plain = true })) do
  if not gofmt_bin and vim.fn.executable(dir .. "/gofmt") == 1 then gofmt_bin = dir .. "/gofmt" end
end
if not check("gofmt is on goimports' PATH to judge the result", gofmt_bin ~= nil, goimports and goimports.env and goimports.env.PATH) then
  return
end
local dir = FIX .. "/gofmt"
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ "module example.com/f", "", "go 1.22" }, dir .. "/go.mod")
vim.fn.writefile({ "package main", "", "func main() {", "x := 1", "\tfmt.Println( x )", "}" }, dir .. "/main.go")
vim.cmd.edit(dir .. "/main.go")
local buf = vim.api.nvim_get_current_buf()

local ok, err = pcall(require("conform").format, { bufnr = buf, async = false, timeout_ms = 10000 })
if not ok then check("go: conform.format runs", false, err) end
local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") .. "\n"
local shown = (text:gsub("\n", " | "))
local gofmt = vim.system({ gofmt_bin }, { stdin = text, text = true }):wait(10000)
check("go: the formatted buffer is gofmt-clean", gofmt.code == 0 and gofmt.stdout == text, shown)
check("go: formatting adds the missing fmt import",
  text:find('import%s+"fmt"') ~= nil or text:find('import%s*%([^)]*"fmt"') ~= nil, shown)
