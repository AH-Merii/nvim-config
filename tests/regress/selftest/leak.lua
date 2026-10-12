-- @desc     runner self-test: a detached child that outlives nvim is reported as a leak
-- @areas    selftest
-- @budget   15
-- @expect-fail leaked: sleep
vim.fn.jobstart({ "sleep", "30" }, { detach = true })
check("spawned a detached sleep", true)
