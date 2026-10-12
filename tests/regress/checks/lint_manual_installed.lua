-- @desc     <leader>ll runs the filetype's linters whose command exists and skips the ones Mason has not installed
-- @areas    lint keys
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
lint.linters_by_ft.nvrprobe = { "nvr_present", "nvr_absent" }

vim.cmd.edit("probe.txt")
vim.bo.filetype = "nvrprobe"
local map = vim.fn.maparg("<leader>ll", "n", false, true)
if not check("<leader>ll is mapped in the buffer", map.buffer == 1, map.buffer ~= 1 and vim.inspect(map) or nil) then return end
spawned = {}
feed("<leader>ll")
check("<leader>ll runs the installed linter", wait_until(function() return (spawned.sh or 0) > 0 end, 3000), spawned.sh or 0)
check("<leader>ll skips the linter whose command is missing", (spawned["nvr-absent-linter"] or 0) == 0, spawned["nvr-absent-linter"])
