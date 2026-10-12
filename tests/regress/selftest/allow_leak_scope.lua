-- @desc     runner self-test: @allow-leak covers only its comm; another leaked process still fails
-- @areas    selftest
-- @budget   15
-- @allow-leak tflint selftest: the allowed comm, a copy of sleep
-- @expect-fail leaked: sleep\([0-9]+\)[^ ]
vim.uv.fs_copyfile(vim.fn.exepath("sleep"), "tflint")
vim.uv.fs_chmod("tflint", tonumber("755", 8))
vim.fn.jobstart({ "./tflint", "30" }, { detach = true })
vim.fn.jobstart({ "sleep", "30" }, { detach = true })
check("spawned a detached tflint and sleep", true)
