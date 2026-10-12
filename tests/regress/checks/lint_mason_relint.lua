-- @desc     after Mason installs packages, each loaded buffer lints again once per burst of installs, not once per package
-- @areas    lint installer
-- @budget   20
local lint = require("lint")
local spawned = {}
lint.linters.nvr_probe = {
  cmd = "sh",
  args = { function() local b = vim.api.nvim_get_current_buf(); spawned[b] = (spawned[b] or 0) + 1; return "-c" end, ":" },
  stdin = false, append_fname = false, ignore_exitcode = true,
  parser = function() return {} end,
}
lint.linters_by_ft.nvrprobe = { "nvr_probe" }
local bufs = {}
for i = 1, 2 do
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.bo.filetype = "nvrprobe"
  bufs[i] = vim.api.nvim_get_current_buf()
end
local function count(b) return spawned[b] or 0 end
spawned = {}

-- a burst: three packages finish installing 50ms apart; the stand-in provides the probe's command
local registry = require("mason-registry")
local pkg = { name = "nvr-probe", spec = { bin = { sh = "sh" } } }
for i = 1, 3 do
  registry:emit("package:install:success", pkg, {})
  if i < 3 then vim.wait(50) end
end
local relinted = wait_until(function() return count(bufs[1]) > 0 and count(bufs[2]) > 0 end, 5000)
check("every loaded buffer lints again after the installs", relinted, count(bufs[1]) .. " " .. count(bufs[2]))
local extra = wait_until(function() return count(bufs[1]) > 1 or count(bufs[2]) > 1 end, 3000)
check("the burst relints each buffer once", not extra, count(bufs[1]) .. " " .. count(bufs[2]) .. " runs")
