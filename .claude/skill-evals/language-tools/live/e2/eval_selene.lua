-- @desc     eval e2: selene findings appear on a Lua buffer through nvim-lint's selene, also while lua_ls is attached, and not on a non-Lua buffer
-- @areas    eval
-- @budget   60
local ns = require("lint").get_namespace("selene")
vim.fn.writefile({ "local unused = 1", "return 2" }, "sel.lua")
vim.cmd.edit("sel.lua")
local buf = vim.api.nvim_get_current_buf()
check("sel.lua is a lua buffer", vim.bo[buf].filetype == "lua", vim.bo[buf].filetype)
-- lua_ls attaching must not silence selene: they report different rules
local missing, why = wait_attach(buf, { "lua_ls" }, 30000)
check("lua_ls attaches to sel.lua", #missing == 0, table.concat(why, "; "))
vim.cmd.write()
wait_diagnostics(buf, function() return #vim.diagnostic.get(buf, { namespace = ns }) > 0 end, 15000)
local codes = vim.tbl_map(function(d) return d.code end, vim.diagnostic.get(buf, { namespace = ns }))
check("selene reports unused_variable on sel.lua with lua_ls attached", vim.list_contains(codes, "unused_variable"), vim.inspect(codes))

-- a shell buffer with the same text gets no selene findings
vim.fn.writefile({ "local unused = 1", "return 2" }, "sel.sh")
vim.cmd.edit("sel.sh")
local sbuf = vim.api.nvim_get_current_buf()
wait_until(function() return #vim.diagnostic.get(sbuf, { namespace = ns }) > 0 end, 3000)
check("a sh buffer gets no selene findings", #vim.diagnostic.get(sbuf, { namespace = ns }) == 0, vim.bo[sbuf].filetype)
