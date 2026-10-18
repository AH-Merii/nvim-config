-- @desc     runner self-test: a detached child that outlives nvim is reported as a leak, with its pid, parent pid, age and command line
-- @areas    selftest
-- @budget   15
-- @expect-fail leaked: sleep\([0-9]+\).*pid [0-9]+ ppid [0-9]+ age [0-9]+s: [^ ]*sleep 30
vim.fn.jobstart({ "sleep", "30" }, { detach = true })
check("spawned a detached sleep", true)
