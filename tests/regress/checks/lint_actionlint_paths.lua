-- @desc     a GitHub workflow with an actionlint error gets actionlint findings whether it is opened by a relative or an absolute path
-- @areas    lint
-- @budget   20
-- @needs    actionlint
local exe = vim.fn.exepath("actionlint")
if not check("actionlint is executable", exe ~= "", exe ~= "" and exe or "not on PATH; Mason package actionlint") then return end
local ns = require("lint").get_namespace("actionlint")
-- "ubuntu-latst" is an unknown runner label, an actionlint-only finding
local bad = { "on: push", "jobs:", "  a:", "    runs-on: ubuntu-latst", "    steps:", "      - run: echo hi" }
vim.fn.writefile(bad, ".github/workflows/rel.yml")
vim.fn.writefile(bad, ".github/workflows/abs.yml")
for _, case in ipairs({ { "relative", ".github/workflows/rel.yml" }, { "absolute", FIX .. "/.github/workflows/abs.yml" } }) do
  vim.cmd.edit(vim.fn.fnameescape(case[2]))
  local buf = vim.api.nvim_get_current_buf()
  wait_diagnostics(buf, function() return #vim.diagnostic.get(buf, { namespace = ns }) > 0 end, 5000)
  local got = vim.diagnostic.get(buf, { namespace = ns })
  check("workflow opened by its " .. case[1] .. " path has actionlint findings", #got > 0,
    #got > 0 and got[1].message:sub(1, 60) or ("none within 5s for " .. vim.api.nvim_buf_get_name(buf)))
end
