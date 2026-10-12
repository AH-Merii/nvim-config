-- @desc     runner self-test: an error the user sees in :messages fails the check (MSG)
-- @areas    selftest
-- @budget   15
-- @expect-fail MSG E117: Unknown function: NvrSelftestNoSuchFunc
feed(":call NvrSelftestNoSuchFunc()<CR>")
check("typed a command that errors", true)
