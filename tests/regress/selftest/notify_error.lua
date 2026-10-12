-- @desc     runner self-test: vim.notify at ERROR level fails the check (NOTIFY from snacks.notifier's history, or MSG)
-- @areas    selftest
-- @budget   15
-- @expect-fail (NOTIFY|MSG) .*nvr selftest notification
vim.notify("nvr selftest notification", vim.log.levels.ERROR)
check("notified at ERROR level", true)
