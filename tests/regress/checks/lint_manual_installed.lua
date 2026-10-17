-- @desc     <leader>ll runs the filetype's linters that resolve and skips, without an error, the ones whose binary is missing
-- @areas    lint keys tools
-- @budget   15
local lint = require("lint")
local spawned = {}
local function probe(cmd)
  return {
    cmd = cmd,
    args = { function() spawned[cmd] = (spawned[cmd] or 0) + 1; return "-c" end, ":" },
    stdin = false, append_fname = false, ignore_exitcode = true,
    parser = function() return {} end,
  }
end
lint.linters.nvr_present = probe("sh")
lint.linters.nvr_absent = probe("nvr-absent-linter")
-- a language for nvrprobe, as a file in lua/lang/ would declare it
require("lang")._declare("nvr_probe", { filetypes = { "nvrprobe" }, linters = { nvr_present = {}, nvr_absent = {} } })

vim.cmd.edit("probe.txt")
vim.bo.filetype = "nvrprobe"
local missing = require("tools").wait("nvr-absent-linter", require("tools").root(0), 10000)
check("the absent linter's binary is missing", missing ~= nil and missing.path == nil, missing and missing.source)
if not check("which-key lists <leader>ll in the buffer", wk_lists(0, "n", "<leader>ll") ~= nil) then return end
spawned = {}
feed("<leader>ll")
check("<leader>ll runs the linter that resolves", wait_until(function() return (spawned.sh or 0) > 0 end, 3000), spawned.sh or 0)
check("<leader>ll skips the linter whose binary is missing", (spawned["nvr-absent-linter"] or 0) == 0, spawned["nvr-absent-linter"])
-- a missing linter that ran anyway would leave an ENOENT error, which the harness records as MSG/NOTIFY
