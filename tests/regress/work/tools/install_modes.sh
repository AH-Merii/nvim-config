# @desc     vim.g.install_tools "auto" installs without a prompt and the linter runs once installed (no ENOENT, no extra BufEnter needed), also for a workflow opened by absolute path; "off" and headless runs install nothing
# @areas    installer lint
# @budget   300
# @fixture  tools
. ./.tui.sh

# probe: a linter the fixture has findings for runs once auto installs it, if the config lints <file> with it
lands() {
  local file=$1 linter=$2 secs=$3
  if hq | jq -e --arg f "$file" --arg l "$linter" '.bufs[] | select(.name == $f) | .tools[] | select(.name == $l and .kind == "linter")' >/dev/null; then
    check "auto: $linter findings on $file land after its install" "wait_q '[.bufs[] | select(.name == \"$file\") | .diags[\"$linter\"] // 0] | add > 0' $secs"
  else info "$file is not linted with $linter: its findings are not checked"; fi
}

start NVR_INSTALL_TOOLS=auto -- notes.md
check "auto: tools install with no prompt" "wait_q '(.installed + .installing) | length > 0' 60 && ! screen | grep -qE '$prompt_re'"
if complete notes.md 180; then pass "auto: notes.md completes, its servers attached and its tools on PATH"
else fail "auto: notes.md completes, its servers attached and its tools on PATH" "$(incomplete notes.md)"; fi
lands notes.md markdownlint 60
check "a linter not installed yet is skipped, not run" "[ \"\$(q '[.notes[] | select(test(\"ENOENT|Error running\"))] | length')\" = 0 ]"
check "the linter ran without another BufEnter" "[ \"\$(q '.bufenters')\" -le 1 ]"
stop

start NVR_INSTALL_TOOLS=auto -- "$FIX/.github/workflows/ci.yml"
if complete ci.yml 180; then pass "auto: ci.yml completes, its servers attached and its tools on PATH"
else fail "auto: ci.yml completes, its servers attached and its tools on PATH" "$(incomplete ci.yml)"; fi
if [ "$(q '.installed | index("actionlint") != null')" = true ]; then
  check "workflow by absolute path: actionlint findings once installed" "wait_q '[.bufs[] | select(.name == \"ci.yml\") | .diags.actionlint // 0] | add > 0' 60"
else info "auto installed no actionlint: workflow findings are not checked"; fi
stop

base=$(pkgs)
start NVR_INSTALL_TOOLS=off -- app.py; sleep 10
check "off: no prompt, nothing installed" "! screen | grep -qE '$prompt_re' && [ \"\$(pkgs)\" = $base ] && [ \"\$(q '.installing | length')\" = 0 ]"
stop

for mode in ask auto; do
  timeout 60 env NVR_INSTALL_TOOLS=$mode "$NV" "$V" --headless --cmd 'luafile .state.lua' \
    -c 'lua vim.defer_fn(function() vim.fn.writefile({ NVR_TOOLS_STATE() }, "headless.json"); vim.cmd("qa!") end, 15000)' app.py > /dev/null 2>&1
  check "headless ($mode): nothing installs" "[ \"\$(pkgs)\" = $base ] && jq -e '.installing | length == 0' headless.json > /dev/null"
  rm -f headless.json
done
