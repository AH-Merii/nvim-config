-- @desc     formatting a Dockerfile through conform runs dockerfmt and leaves it formatted; Compose and Bake files never plan dockerfmt
-- @areas    format
-- @budget   15
-- @needs    dockerfmt
local conform = require("conform")
local function planned(buf) return vim.tbl_map(function(f) return f.name end, conform.list_formatters_to_run(buf)) end

vim.fn.writefile({ "from alpine:3.20", "run apk add --no-cache curl &&    echo hi", "copy . /app" }, "Dockerfile")
vim.cmd.edit("Dockerfile")
local buf = vim.api.nvim_get_current_buf()
check("the sample is dockerfile", vim.bo[buf].filetype == "dockerfile", vim.bo[buf].filetype)
local names = planned(buf)
check("dockerfmt is planned for dockerfile", vim.list_contains(names, "dockerfmt"), table.concat(names, ","))
local ok, err = pcall(conform.format, { bufnr = buf, async = false, timeout_ms = 10000 })
check("conform.format runs", ok, err)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
-- dockerfmt v0.5.4's output for these lines, read from stdin as conform runs it
local want = { "FROM alpine:3.20", "RUN apk add --no-cache curl && echo hi", "COPY . /app" }
check("the buffer is formatted", vim.deep_equal(lines, want), table.concat(lines, " | "))

-- Compose and Bake files are variants of yaml and hcl (lang/docker.lua), not of dockerfile
for _, case in ipairs({ { "compose.yaml", "yaml.docker-compose" }, { "docker-bake.hcl", "hcl.docker-bake" } }) do
  vim.fn.writefile({ "" }, case[1])
  vim.cmd.edit(case[1])
  local b = vim.api.nvim_get_current_buf()
  check(case[1] .. " is " .. case[2], vim.bo[b].filetype == case[2], vim.bo[b].filetype)
  local n = planned(b)
  check(case[1] .. " plans no dockerfmt", not vim.list_contains(n, "dockerfmt"), table.concat(n, ","))
end
