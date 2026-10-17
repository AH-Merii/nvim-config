-- @desc     a buffer's facts with the real tools and servers: a linter runs only where its binary is found and no server that covers it is attached, a missing binary is listed as missing, the attached servers are listed, and the formatters are conform's
-- @areas    ui lint tools
-- @budget   30
-- @needs    jactionlint ruff
-- Which tools are there depends on the suite's mise: jactionlint and ruff are, hadolint and zizmor are not.
local tools = require("tools")
local facts = require("ui.facts")
vim.g.install_tools = "off"

--- Opens path and returns its facts once want accepts them (or the last ones), and its tools' results.
local function open(path, lines, want)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  vim.cmd.edit(path)
  local results
  tools.resolve_all(require("lang").of(vim.bo.filetype).tools, tools.root(0), function(r) results = r end)
  wait_until(function() return results ~= nil end, 10000)
  local f
  wait_until(function()
    f = facts.get(0)
    return want(f)
  end, 10000)
  return f, results or {}
end

--- The linters of the buffer's language whose binary is found (true) or missing (false), as the resolver says.
local function linters_by_found(results)
  local out = {}
  for _, name in ipairs(require("lang").of(vim.bo.filetype).linters) do
    local result = results[tools.catalog.binary("linter", name)]
    if result then
      out[name] = result.path ~= nil
    end
  end
  return out
end

local f, results = open(FIX .. "/.github/workflows/ci.yml", { "on: push", "jobs: {}" }, function(x) return #x.linters > 0 end)
local found = linters_by_found(results)
check("the workflow file has a found and a missing linter in the suite", vim.list_contains(vim.tbl_values(found), true)
  and vim.list_contains(vim.tbl_values(found), false), vim.inspect(found))
for name, ok in pairs(found) do
  if ok then
    check(("%s, found, will run"):format(name), vim.list_contains(f.linters, name), vim.inspect(f.linters))
  else
    check(("%s, missing, will not run"):format(name), not vim.list_contains(f.linters, name), vim.inspect(f.linters))
    check(("%s's binary is listed as missing"):format(name), vim.list_contains(f.missing, tools.catalog.binary("linter", name)), vim.inspect(f.missing))
  end
end

f = open(FIX .. "/py/a.py", { "x = 1" }, function(x) return vim.list_contains(x.servers, "ruff") end)
if check("the ruff server attaches and is listed", vim.list_contains(f.servers, "ruff"), vim.inspect(f.servers)) then
  local covered = {}
  for linter, server in pairs(require("lang").of("python").covered_by) do
    if vim.list_contains(f.servers, server) then
      table.insert(covered, linter)
    end
  end
  -- conform decides on its own which formatters run; the facts must agree with the real plugin
  local conform = vim.tbl_map(function(x) return x.name end, require("conform").list_formatters_to_run(0))
  check("the formatters that will run are the ones conform runs", #conform > 0 and vim.deep_equal(f.formatters, conform),
    vim.inspect({ facts = f.formatters, conform = conform }))
  check("python has a linter that an attached server covers", #covered > 0, vim.inspect(f.servers))
  for _, linter in ipairs(covered) do
    check(("%s, covered by an attached server, will not run"):format(linter), not vim.list_contains(f.linters, linter), vim.inspect(f.linters))
  end
end
