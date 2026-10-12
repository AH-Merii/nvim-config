-- @desc     runner self-test: a check past its budget is killed and fails
-- @areas    selftest
-- @budget   3
-- @expect-fail over budget
check("about to overrun", true)
vim.wait(10000, function() return false end)
