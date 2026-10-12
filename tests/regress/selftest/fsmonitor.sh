# @desc     runner self-test: a git fsmonitor daemon started from a check is a leak
# @areas    selftest
# @budget   15
# @expect-fail leaked: git
env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 git -c core.fsmonitor=true status >/dev/null 2>&1
echo "PASS ran git with fsmonitor on" >>"$CHECK_OUT"
echo DONE >>"$CHECK_OUT"
