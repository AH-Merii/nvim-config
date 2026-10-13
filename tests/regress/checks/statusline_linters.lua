-- @desc     the statusline lists only the linters that run: not one whose binary is missing, not one whose server reports the same findings while attached
-- @areas    ui lint tools
-- @budget   30
-- @needs    jactionlint ruff
-- Which tools are there depends on the suite's mise: jactionlint and ruff are, hadolint and zizmor are not.
local tools = require("tools")
vim.g.install_tools = "off"

local function statusline()
  require("lualine").refresh({ place = { "statusline" }, force = true })
  return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win(), maxwidth = 400 }).str
end
--- Opens path and returns the statusline once want accepts it, or the last one seen.
local function open(path, lines, want)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  vim.cmd.edit(path)
  local names = tools.for_filetype(vim.bo.filetype, 0).tools
  local results
  tools.resolve_all(names, tools.root(0), function(r) results = r end)
  wait_until(function() return results ~= nil end, 10000)
  local line
  wait_until(function()
    vim.api.nvim_exec_autocmds("User", { pattern = tools.event, data = { root = tools.root(0), tools = {}, reason = "refresh" } })
    line = statusline()
    return want(line)
  end, 10000)
  return line, results or {}
end

local line, results = open(FIX .. "/.github/workflows/ci.yml", { "on: push", "jobs: {}" }, function(l) return l:find("jactionlint", 1, true) ~= nil end)
if check("jactionlint is found and zizmor is missing in the suite", results.jactionlint and results.jactionlint.path and results.zizmor
  and not results.zizmor.path, vim.inspect(vim.tbl_map(function(r) return r.source end, results))) then
  check("a linter that runs is listed", line:find("jactionlint", 1, true) ~= nil, line)
  check("a linter whose binary is missing is not", not line:find("zizmor", 1, true), line)
end

line = open(FIX .. "/py/a.py", { "x = 1" }, function()
  return #vim.lsp.get_clients({ bufnr = 0, name = "ruff" }) > 0
end)
if check("the ruff server attaches", #vim.lsp.get_clients({ bufnr = 0, name = "ruff" }) > 0, line) then
  line = statusline()
  -- the linters list follows the formatters list ("ruff_fix, ruff_format, ..."), which also names ruff
  local formatters = table.concat(vim.tbl_map(function(f) return f.name end, require("conform").list_formatters_to_run(0)), ", ")
  local at = formatters ~= "" and line:find(formatters, 1, true)
  if check("the statusline lists ruff's formatters", at ~= nil, vim.inspect({ line = line, formatters = formatters })) then
    local rest = line:sub(at + #formatters)
    check("a linter whose server is attached is not listed", not rest:find("ruff", 1, true), rest)
  end
end
