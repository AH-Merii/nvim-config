-- @desc     a buffer whose compound filetype (a.b) gets linters from one of its parts lints on enter and on write
-- @areas    lint
-- @budget   15
local lint = require("lint")
local spawned = {}
-- args are evaluated once per spawn, so this counts runs even when a later run cancels an earlier one
lint.linters.nvr_probe = {
  cmd = "sh",
  args = { function() local b = vim.api.nvim_get_current_buf(); spawned[b] = (spawned[b] or 0) + 1; return "-c" end, ":" },
  stdin = false, append_fname = false, ignore_exitcode = true,
  parser = function() return {} end,
}
lint.linters_by_ft.nvrprobe = { "nvr_probe" }

vim.cmd.edit("probe.txt")
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "nvrprobe.extra"
vim.cmd.enew()
spawned = {}
vim.cmd.buffer(buf)
check("compound filetype lints on BufEnter", wait_until(function() return (spawned[buf] or 0) > 0 end, 3000), spawned[buf] or 0)
spawned = {}
vim.cmd("silent write")
check("compound filetype lints on BufWritePost", wait_until(function() return (spawned[buf] or 0) > 0 end, 3000), spawned[buf] or 0)
