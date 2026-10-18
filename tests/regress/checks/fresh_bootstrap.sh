#!/usr/bin/env bash
# @desc     a first start from an empty data dir installs every plugin (vim.pack, from the lockfile) and parser, without a hit-enter prompt or an error, and the file opened at launch gets its servers from the suite's tools
# @areas    startup installer treesitter lsp tools
# @budget   180
# @fresh
# @needs    lua-language-server
# @network  the real first start: 24 plugin clones, blink.cmp binary, ~30 parser tarballs
#           Measured in the fresh sandbox (with Mason, before mise): VimEnter at 6.5-14s, parsers ~10s after it.
#
# Same TUI driver as fresh_no_prompt.sh (tmux, private server killed on exit; 3s init-time event loop that
# forces the first-start prompt race), on an empty data dir, launched with main.lua so the opened buffer must get
# lua_ls from the suite's tools (the binary is resolved before plugins install, in the tools phase). Installs are off: the suite's mise is shared by every check and only --refresh fills it.
set -u
unset TMUX
D=$FIX/.nvr
SOCK=nvr-$V-$$
DST=$NVR_DATA/nvim
BUDGET=$(sed -n -E 's/^# @budget +([0-9]+).*/\1/p' "$CHECK")
say() { echo "$1" >>"$CHECK_OUT"; }
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null; }
trap cleanup EXIT
trap 'exit 143' TERM INT
mkdir -p "$D"

mkdir -p "$DST/site/plugin"
echo 'vim.wait(3000)' >"$DST/site/plugin/zz_nvr_init_wait.lua"

# --cmd, before init.lua: record every nvim_echo (nvim-treesitter's log captures nvim_echo when it loads)
cat >"$D/pre.lua" <<'LUA'
_G.NVR = { echoes = {} }
-- nothing may install into the suite's shared mise; the launch file's tools are already there
vim.g.install_tools = "off"
local echo = vim.api.nvim_echo
vim.api.nvim_echo = function(chunks, history, opts)
  local ok, text = pcall(function() return table.concat(vim.tbl_map(function(c) return tostring(c[1]) end, chunks)) end)
  table.insert(NVR.echoes, { t = vim.uv.hrtime(), init = vim.v.vim_did_enter == 0, text = ok and text or "?" })
  return echo(chunks, history, opts)
end
LUA

# -c: after VimEnter, poll on a timer (the UI loop keeps running) until the parser installs settle
cat >"$D/drive.lua" <<'LUA'
local D, MODE = vim.env.NVR_CHECK_DIR, vim.env.NVR_MODE
local CAP = tonumber(vim.env.NVR_SETTLE_MAX or "60") * 1e9
local now = vim.uv.hrtime
local res = {}
local function rec(ok, name, detail)
  table.insert(res, string.format("%s %s%s", ok and "PASS" or "FAIL", name, detail and ("  -- " .. detail) or ""))
end
local function info(s) table.insert(res, "INFO " .. s) end
local function join(t, n) return table.concat(vim.list_slice(t, 1, n or #t), ", ") end

-- parser installs, from nvim-treesitter's log lines
local function ts_state()
  local started, done, errs = {}, {}, {}
  for _, e in ipairs(NVR.echoes) do
    local lang = e.text:match("nvim%-treesitter/install/([%w_]+)")
    if lang then
      if e.text:find("Downloading", 1, true) then started[lang] = true end
      if e.text:find("Language installed", 1, true) then done[lang] = true end
      if e.text:find("%] error:") then
        done[lang] = true
        errs[lang] = e.text
      end
    end
  end
  local pending = {}
  for l in pairs(started) do
    if not done[l] then table.insert(pending, l) end
  end
  table.sort(pending)
  return started, errs, pending
end

local function plugins_missing()
  local out = {}
  for _, p in ipairs(require("app.plugins").list()) do
    if not vim.uv.fs_stat(p.path) then table.insert(out, p.name) end
  end
  return out
end

-- servers that must attach to buf: enabled, covering its filetype, with a root when required, runnable; a catalog
-- server only when the tools resolver found its binary (the config's root_dir wrapper declines otherwise)
local function expected_servers(buf)
  local ft, names, want = vim.bo[buf].filetype, {}, {}
  local tools, catalog = require("tools"), require("tools.catalog")
  for _, f in ipairs(vim.api.nvim_get_runtime_file("lsp/*.lua", true)) do names[vim.fn.fnamemodify(f, ":t:r")] = true end
  for n in pairs(vim.lsp._enabled_configs or {}) do names[n] = true end
  for n in pairs(names) do
    local c = vim.lsp.is_enabled(n) and vim.lsp.config[n]
    if c and (c.filetypes == nil or vim.list_contains(c.filetypes, ft)) then
      local bin = catalog.binary("server", n)
      local found = not bin or (tools.get(bin, tools.root(buf)) or {}).path ~= nil
      local runnable = type(c.cmd) == "function" or (type(c.cmd) == "table" and vim.fn.executable(c.cmd[1]) == 1)
      local root_ok = not (c.workspace_required and type(c.root_dir) ~= "function" and c.root_markers)
        or vim.fs.root(buf, c.root_markers) ~= nil
      if found and runnable and root_ok then table.insert(want, n) end
    end
  end
  table.sort(want)
  return want
end
local function unattached(buf, want)
  return vim.tbl_filter(function(n) return not vim.lsp.get_clients({ bufnr = buf, name = n })[1] end, want)
end

local t_enter, t_phase, buf0 = nil, nil, nil
local phase = "settle"

local function report()
  local init = vim.tbl_filter(function(e) return e.init end, NVR.echoes)
  info(string.format("echoes before VimEnter: %d%s", #init,
    #init > 0 and (" (first: " .. join(vim.tbl_map(function(e) return e.text end, init), 3) .. ")") or ""))

  -- app.plugins reports a plugin function that raised as "<plugin>: setup failed:" (also init, build), echoed before
  -- snacks.notifier is set up and a notification after (checked below)
  local hook_errs = {}
  for _, e in ipairs(NVR.echoes) do
    local name, hook = e.text:match("([%w%._%-]+): (%w+) failed:")
    if hook then table.insert(hook_errs, name .. " " .. hook) end
  end
  rec(#hook_errs == 0, "every plugin's init, build and setup run without error at the first start",
    #hook_errs > 0 and join(hook_errs) or nil)

  local started, errs, pending = ts_state()
  local n, unloadable, errlist = 0, {}, {}
  for l in pairs(started) do
    n = n + 1
    local ok, r = pcall(vim.treesitter.language.add, l)
    if not errs[l] and not vim.list_contains(pending, l) and not (ok and r) then table.insert(unloadable, l) end
  end
  for _, t in pairs(errs) do table.insert(errlist, t) end
  if n == 0 then info("no parser install seen: the init-time echo race was not exercised") end
  rec(#pending == 0 and #errlist == 0 and #unloadable == 0, "parsers installed at first start load, no install errors",
    string.format("%d installed; pending [%s]; errors [%s]; not loadable [%s]", n, join(pending), join(errlist, 2), join(unloadable)))

  local pm = plugins_missing()
  rec(#pm == 0, "every plugin installed", #pm > 0 and ("missing " .. join(pm)) or nil)

  local attach_name = "file opened at launch gets its servers from the suite's tools"
  if MODE == "bootstrap" and not (buf0 and vim.api.nvim_buf_is_valid(buf0)) then
    rec(false, attach_name, "no buffer for the launch file " .. vim.fn.argv(0))
  elseif MODE == "bootstrap" then
    local want = expected_servers(buf0)
    local miss = unattached(buf0, want)
    local what = string.format("%s ft=%s want [%s] missing [%s]", vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf0), ":t"),
      vim.bo[buf0].filetype, join(want), join(miss))
    rec(#want > 0 and #miss == 0, attach_name, what)
  end

  local bad = {}
  for line in vim.api.nvim_exec2("messages", { output = true }).output:gmatch("[^\n]+") do
    if line:find("E%d+:") or line:find("Error") or line:find("stack traceback") then table.insert(bad, line) end
  end
  rec(#bad == 0, "no error in :messages", #bad > 0 and join(bad, 3) or nil)

  local okh, hist = pcall(function() return Snacks.notifier.get_history() end)
  local errn = {}
  for _, h in ipairs(okh and hist or {}) do
    if h.level == "error" or h.level == vim.log.levels.ERROR then table.insert(errn, tostring(h.msg)) end
  end
  rec(#errn == 0, "no error notification", #errn > 0 and join(errn, 3) or nil)
end

local function finish()
  local ok, err = pcall(report)
  if not ok then rec(false, "driver report ran", err) end
  vim.fn.writefile(vim.tbl_map(function(l) return (l:gsub("\n", "\\n")) end, res), D .. "/result")
  vim.cmd("qa!")
end

local timer = vim.uv.new_timer()
local function tick()
  if phase == "done" then return end
  local t = now()
  if phase == "settle" then
    local _, _, pending = ts_state()
    local settled = t - t_enter > 3e9 and #pending == 0
    if settled or t - t_enter > CAP then
      if not settled then
        rec(false, "first start settled", string.format("after %ds: parsers pending [%s]", CAP / 1e9, join(pending)))
      end
      phase, t_phase = MODE == "bootstrap" and "attach" or "report", t
    end
  end
  if phase == "attach" then
    local miss = buf0 and vim.api.nvim_buf_is_valid(buf0) and unattached(buf0, expected_servers(buf0)) or {}
    if #miss == 0 or t - t_phase > 20e9 then phase = "report" end
  end
  if phase == "report" then
    phase = "done"
    timer:stop()
    timer:close()
    finish()
  end
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    t_enter = now()
    -- by argv, not the current buffer, which a check's own window could take
    local b = vim.fn.argc() > 0 and vim.fn.bufnr(vim.fn.fnamemodify(vim.fn.argv(0), ":p")) or -1
    buf0 = b > 0 and b or nil
    timer:start(250, 250, vim.schedule_wrap(function()
      local ok, err = pcall(tick)
      if not ok and phase ~= "done" then
        phase = "done"
        timer:stop()
        rec(false, "driver ran", err)
        finish()
      end
    end))
  end,
})
LUA

{
  for v in PATH HOME NVR_HOME NVR_STATE NVR_DATA NVR_VERSION NVIM_REGRESS_TAG; do printf 'export %s=%q\n' "$v" "${!v}"; done
  printf 'export TERM=xterm-256color COLORTERM=truecolor NVR_CHECK_DIR=%q NVR_MODE=bootstrap NVR_SETTLE_MAX=%q\n' "$D" $((BUDGET - 35))
  printf 'cd %q || exit 1\n' "$FIX"
  printf '%q %q --cmd %q -c %q main.lua\n' "$NV" "$V" "luafile $D/pre.lua" "luafile $D/drive.lua"
  printf 'echo $? >%q\n' "$D/exit"
} >"$D/run.sh"

SHELL=/bin/sh tmux -L "$SOCK" -f /dev/null new-session -d -s t -x 200 -y 50 "bash $(printf %q "$D/run.sh")"

PROMPT='Press ENTER|-- More --'
prompts=0 first=
end=$((SECONDS + BUDGET - 15))
while [ ! -e "$D/exit" ] && [ $SECONDS -lt $end ] && tmux -L "$SOCK" has-session -t t 2>/dev/null; do
  screen=$(tmux -L "$SOCK" capture-pane -p -t t 2>/dev/null)
  if grep -q -E "$PROMPT" <<<"$screen"; then
    prompts=$((prompts + 1))
    [ -z "$first" ] && first="at ${SECONDS}s: $(grep -v -E '^~? *$' <<<"$screen" | tail -n 4 | tr -s ' ' | tr '\n' '|' | cut -c1-300)"
    # G jumps to the end of a more-prompt listing (q would set got_int and abort pending -c commands)
    if grep -q -e "-- More --" <<<"$screen"; then key=G; else key=Enter; fi
    tmux -L "$SOCK" send-keys -t t "$key"
    for _ in $(seq 20); do
      tmux -L "$SOCK" capture-pane -p -t t 2>/dev/null | grep -q -E "$PROMPT" || break
      sleep 0.1
    done
  fi
  sleep 0.25
done

if [ "$prompts" = 0 ]; then say "PASS no hit-enter or more prompt during the first start"
else say "FAIL no hit-enter or more prompt during the first start  -- $prompts prompt(s), first $first"; fi
if [ -e "$D/exit" ]; then
  if [ -s "$D/result" ]; then cat "$D/result" >>"$CHECK_OUT"
  else say "FAIL driver reported  -- nvim exited $(cat "$D/exit") without a result"; fi
else
  say "FAIL nvim settled and quit  -- still running after $((BUDGET - 15))s: $(tmux -L "$SOCK" capture-pane -p -t t 2>/dev/null | grep -v -E '^~? *$' | tail -n 3 | tr -s ' ' | tr '\n' '|' | cut -c1-300)"
fi
say DONE
