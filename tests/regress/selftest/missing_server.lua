-- @desc     runner self-test: an enabled server whose binary is missing fails wait_attach within seconds
-- @areas    selftest
-- @budget   15
-- @expect-fail bogus_ls attaches  -- failed fast [^:]*: bogus_ls: (no client started|client exited)
vim.lsp.config("bogus_ls", { cmd = { "/nonexistent/bogus-ls" }, filetypes = { "lua" } })
vim.lsp.enable("bogus_ls")
vim.cmd.edit("main.lua")
local t = vim.uv.hrtime()
local missing, why = wait_attach(0, { "bogus_ls" }, 15000)
local secs = (vim.uv.hrtime() - t) / 1e9
-- the speed is in the expected line itself, so a slow failure cannot match @expect-fail
check("bogus_ls attaches", #missing == 0,
  string.format("failed %s (%.1fs): %s", secs < 5 and "fast" or "slow", secs, table.concat(why, "; ")))
