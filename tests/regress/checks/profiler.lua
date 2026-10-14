-- @desc     stopping the profiler after it traced Neovim's built-in vim/ modules loads its results without error
-- @areas    ui
-- @budget   20
vim.cmd.edit("main.lua")
local loaded = false
vim.api.nvim_create_autocmd("User", { pattern = "SnacksProfilerLoaded", once = true, callback = function() loaded = true end })
vim.v.errmsg = ""
Snacks.profiler.start()
-- calls into a built-in module, whose chunk is named "@vim/loader" on nightly
vim.loader.find("snacks")
Snacks.profiler.stop({ pick = false, highlights = false })
wait_until(function() return loaded or vim.v.errmsg ~= "" end, 10000)
check("the profiler's results load", loaded, vim.v.errmsg)
check("no error while loading them", vim.v.errmsg == "", vim.v.errmsg)
