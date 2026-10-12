-- @desc     a GitHub workflow gets yaml.github-actions and jactionlint findings whether it is opened by a relative or an absolute path, only from the rules actionlint has (not the security rules zizmor reports), with each finding's level as its diagnostic severity
-- @areas    lint tools
-- @budget   20
-- @needs    jactionlint
local ns = require("lint").get_namespace("jactionlint")
local function put(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
--- Opens path and returns its jactionlint diagnostics, by 1-based line.
local function lint(path)
  vim.cmd.edit(vim.fn.fnameescape(path))
  local buf = vim.api.nvim_get_current_buf()
  wait_diagnostics(buf, function() return #vim.diagnostic.get(buf, { namespace = ns }) > 0 end, 5000)
  local by_line = {}
  for _, d in ipairs(vim.diagnostic.get(buf, { namespace = ns })) do
    by_line[d.lnum + 1] = d
  end
  return buf, by_line
end
local function show(by_line)
  return vim.inspect(vim.tbl_map(function(d) return ("%s %s"):format(vim.diagnostic.severity[d.severity], d.message:sub(1, 50)) end, by_line))
end

-- "ubuntu-latst" (line 4) is an unknown runner label, which actionlint reports. The unpinned checkout (line 6), the
-- missing permissions (line 3) and concurrency (line 1) are findings of jactionlint's default profile only.
local bad = { "on: push", "jobs:", "  a:", "    runs-on: ubuntu-latst", "    steps:", "      - uses: actions/checkout@v4", "      - run: echo hi" }
put(".github/workflows/rel.yml", bad)
put(".github/workflows/abs.yml", bad)
for _, case in ipairs({ { "relative", ".github/workflows/rel.yml" }, { "absolute", FIX .. "/.github/workflows/abs.yml" } }) do
  local buf, by_line = lint(case[2])
  check("workflow opened by its " .. case[1] .. " path is yaml.github-actions", vim.bo[buf].filetype == "yaml.github-actions",
    vim.bo[buf].filetype)
  check("workflow opened by its " .. case[1] .. " path has the runner label finding", by_line[4] ~= nil,
    next(by_line) and show(by_line) or ("none within 5s for " .. vim.api.nvim_buf_get_name(buf)))
  by_line[4] = nil
  check("workflow opened by its " .. case[1] .. " path has no finding from a rule actionlint lacks", next(by_line) == nil, show(by_line))
end

-- The repository's config sets the level of two rules; the deprecated set-output command keeps its default, error
put(".github/jactionlint.yaml", { "rules:", "  unknown-runner-label: warn", "  outdated-action-runner: info" })
put(".github/workflows/levels.yml", {
  "on: push",
  "jobs:",
  "  a:",
  "    runs-on: ubuntu-latst",
  "    steps:",
  "      - uses: actions/checkout@v2",
  '      - run: echo "::set-output name=x::y"',
})
local _, by_line = lint(FIX .. "/.github/workflows/levels.yml")
local want = { [4] = "WARN", [6] = "INFO", [7] = "ERROR" }
for line, severity in pairs(want) do
  local d = by_line[line]
  check(("a finding of level %s is a %s diagnostic"):format(severity:lower(), severity),
    d ~= nil and vim.diagnostic.severity[d.severity] == severity, show(by_line))
end
