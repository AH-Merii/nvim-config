-- @desc     a buffer whose dotted filetype (a.b) gets linters from one of its parts lints on enter and on write; a buffer of the base filetype alone does not run them
-- @areas    lint tools
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
lint.linters_by_ft.nvrextra = { "nvr_probe" }

vim.cmd.edit("probe.txt")
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "nvrbase.nvrextra"
vim.cmd.edit("base.txt")
local base = vim.api.nvim_get_current_buf()
vim.bo[base].filetype = "nvrbase"
spawned = {}
vim.cmd.buffer(buf)
check("dotted filetype lints on BufEnter", wait_until(function() return (spawned[buf] or 0) > 0 end, 3000), spawned[buf] or 0)
spawned = {}
vim.cmd("silent write")
check("dotted filetype lints on BufWritePost", wait_until(function() return (spawned[buf] or 0) > 0 end, 3000), spawned[buf] or 0)
vim.cmd.buffer(base)
vim.cmd("silent write")
-- the dotted buffer's runs above came within 3s; give the base one as long
wait_until(function() return (spawned[base] or 0) > 0 end, 3000)
check("the base filetype alone does not run its sub-filetype's linters", (spawned[base] or 0) == 0, spawned[base] or 0)
