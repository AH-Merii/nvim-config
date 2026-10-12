# @desc     opening a file with missing tools asks "Install X for <ft>?" once per filetype; Yes installs and the server attaches, Not now lasts the session, Never survives a restart, Esc cancels, a markdown float never asks, several files queue one prompt at a time
# @areas    installer lsp
# @budget   420
# @fixture  tools
# real TUI in tmux; tools install from the network into a data dir without Mason
. ./.tui.sh

start -- main.lua
check "prompt for lua" "wait_screen 'Install .* for lua\?' 60" "$(screen | tail -5)"
mapfile -t lua_pkgs < <(offered lua)
check "nothing installs before the answer" "nothing_for ${lua_pkgs[*]}"
answer Yes
check "Yes installs what the prompt offered" "[ ${#lua_pkgs[@]} -gt 0 ] && all_installed 180 ${lua_pkgs[*]}" "offered: ${lua_pkgs[*]}"
if complete main.lua 120; then pass "Yes: main.lua completes, its servers attached and its tools on PATH"
else fail "Yes: main.lua completes, its servers attached and its tools on PATH" "$(incomplete main.lua)"; fi
base=$(pkgs)
no_new() { [ "$(pkgs)" = "$base" ] && [ "$(q '.installing | length')" = 0 ]; }
send '<Cmd>call win_gotoid(bufwinid("main.lua"))<CR><Cmd>lua vim.lsp.util.open_floating_preview({ "# hover" }, "markdown", {})<CR>'
check "a markdown nofile float is open" "wait_q '[.bufs[] | select(.ft == \"markdown\" and .bt == \"nofile\")] | length > 0' 10"
sleep 3
check "markdown float: no prompt and no markdown installs" "! screen | grep -qE 'for markdown\?' && no_new"
send '<Esc><Esc>:e notes.md<CR>'
check "prompt for markdown on a real file" "wait_screen 'Install .* for markdown\?' 30"
answer "Not now"; sleep 3
check "Not now: nothing installs" "no_new"
send '<Esc>:e more.md<CR>'; sleep 4
check "Not now: no second markdown prompt this session" "! screen | grep -qE 'for markdown\?'"
send '<Esc>:e script.sh<CR>'
check "prompt for sh" "wait_screen 'Install .* for sh\?' 30"
answer Never; sleep 2
check "Never: nothing installs" "no_new"
stop
start -- script.sh; sleep 8
check "Never survives a restart: no sh prompt, no sh installs" "! screen | grep -qE 'for sh\?' && no_new"
send '<Esc>:e notes.md<CR>'
check "Not now does not survive a restart" "wait_screen 'Install .* for markdown\?' 30"
cancel; sleep 3
check "Esc Esc closes the prompt and installs nothing" "! screen | grep -qE 'for markdown\?' && no_new"
stop

rm -rf "$NVR_STATE"; mkdir -p "$NVR_STATE"
before=$(pkgs)
start -- -O app.py index.ts
check "a first prompt for python or typescript" "wait_screen 'Install .* for (python|typescript)\?' 60"
first=$(screen | grep -oE 'for (python|typescript)\?' | head -1 | sed -E 's/for (.*)\?/\1/')
other=$([ "$first" = python ] && echo typescript || echo python); sleep 2
check "one prompt at a time" "[ \"\$(screen | grep -cE '$prompt_re')\" = 1 ]"
cancel
check "Esc on the first prompt releases the next: $other" "wait_screen 'Install .* for $other\?' 20"
answer "Not now"; sleep 4
check "no third prompt, nothing installed" "! screen | grep -qE '$prompt_re' && [ \"\$(pkgs)\" = $before ] && [ \"\$(q '.installing | length')\" = 0 ]"
stop
