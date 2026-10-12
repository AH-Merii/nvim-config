-- @desc     runner self-test: a check that exits nvim before the harness writes DONE fails
-- @areas    selftest
-- @budget   15
-- @expect-fail did not finish
check("about to quit early", true)
vim.cmd("cquit")
