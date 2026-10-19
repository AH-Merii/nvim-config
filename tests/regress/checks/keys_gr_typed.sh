# @desc     typed one key at a time, fast and slow, once which-key's triggers are attached, every gr* key the runtime or the config maps sends its LSP request exactly once (normal mode, and visual for x maps), in a buffer with a server that serves them all: no shorter gr map swallows them
# @areas    keys lsp which-key
# @budget   90
# Ported from nvim-sbx-keys/checks2/interactive_gr.sh and spy_gr.lua. Keys go through --remote-send one at a
# time: feeding "grn" at once resolves the longest match and hides a shorter nowait map. An in-process fake server
# records the requests, so what a key runs is judged by what reaches the server, not by the maps.
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
sock=/tmp/nvr-gr-$V-$$.sock
spy=$FIX/.nvr-spy-gr.lua
cat >"$spy" <<'EOF'
-- headless never gets UIEnter, so fire VeryLazy; then a buffer with an in-process server that serves every gr* key
vim.g.did_very_lazy = true
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    vim.wait(1000, function() return ran end, 10)
  end
end

-- The request each gr* key makes, the runtime's and the config's: the LSP action the key runs, as the server sees
-- it. Written out here so the check does not read the config's tables. Rename asks prepareRename first, which the
-- server answers with nothing to rename, so no prompt opens.
local SENDS = {
  ["n grn"] = "textDocument/prepareRename",
  ["n gra"] = "textDocument/codeAction",
  ["x gra"] = "textDocument/codeAction",
  ["n grr"] = "textDocument/references",
  ["n gri"] = "textDocument/implementation",
  ["n grt"] = "textDocument/typeDefinition",
  ["n grx"] = "textDocument/codeLens",
}
local caps = { renameProvider = { prepareProvider = true } }
for _, method in pairs(SENDS) do
  local path = vim.lsp.protocol._request_name_to_server_capability[method]
  if path[1] ~= "renameProvider" then caps[path[1]] = true end
end
-- every request after initialize, as "<method>:<mode when it was sent>"
_G.HITS = {}
local function cmd(dispatchers)
  local closing, id = false, 0
  return {
    request = function(method, _, callback)
      id = id + 1
      local result = {}
      if method == "initialize" then
        result = { capabilities = caps }
      else
        if method ~= "shutdown" then table.insert(HITS, method .. ":" .. vim.fn.mode()) end
        if method == "shutdown" or method == "textDocument/prepareRename" then result = nil end
      end
      vim.schedule(function() callback(nil, result) end)
      return true, id
    end,
    notify = function(method)
      if method == "exit" and not closing then
        closing = true
        vim.schedule(function() dispatchers.on_exit(0, 15) end)
      end
      return true
    end,
    is_closing = function() return closing end,
    terminate = function() closing = true end,
  }
end
vim.cmd.edit(vim.fn.getcwd() .. "/.nvr-gr.sbxfake")
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local x = 1", "print(x)" })
vim.bo[buf].filetype = "sbxfake"
local id = vim.lsp.start({ name = "fake-gr", cmd = cmd, root_dir = vim.fn.getcwd() }, { bufnr = buf })
vim.wait(3000, function()
  local c = id and vim.lsp.get_client_by_id(id)
  return c ~= nil and c.initialized and vim.lsp.buf_is_attached(buf, id)
end, 10)
if not (id and vim.lsp.buf_is_attached(buf, id)) then
  vim.g.spy_ready = "the fake server did not attach to " .. vim.api.nvim_buf_get_name(buf)
  return
end
-- let what the attach scheduled run
flush()
_G.HITS = {}

-- every gr* key: the runtime's own (from a --clean nvim of the same binary) and the ones written out above
local order, seen = {}, {}
local function want(key)
  if not seen[key] then
    seen[key] = true
    order[#order + 1] = key
  end
end
local tmp = vim.fn.tempname()
vim.system({ vim.v.progpath, "--clean", "--headless", "-c",
  ([[lua local t = {} for _, mode in ipairs({ "n", "x" }) do for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do if m.lhs:match("^gr.") then t[#t + 1] = mode .. " " .. m.lhs end end end vim.fn.writefile(t, %q)]]):format(tmp),
  "-c", "qa!" }, { stdin = false }):wait()
local builtins = vim.fn.filereadable(tmp) == 1 and vim.fn.readfile(tmp) or {}
os.remove(tmp)
for _, line in ipairs(builtins) do want(line) end
for key in pairs(SENDS) do want(key) end
table.sort(order)

local plan, notes = {}, {}
for _, key in ipairs(order) do
  local mode, lhs = key:match("^(%S+) (%S+)$")
  if not SENDS[key] then
    notes[#notes + 1] = ("FAIL %s %s has a request to wait for  -- the runtime maps it; add it to SENDS"):format(mode, lhs)
  elseif not lhs:match("^%w+$") then
    notes[#notes + 1] = ("INFO %s %s not typed: the lhs has special keys"):format(mode, lhs)
  else
    plan[#plan + 1] = ("%s %s %s"):format(mode, lhs, SENDS[key])
  end
end
vim.g.gr_plan, vim.g.gr_notes = table.concat(plan, "\n"), table.concat(notes, "\n")

-- typing is safe once which-key has loaded its spec, is not mid-sequence, and has attached every trigger it
-- computed for the buffer in normal mode
function _G.WK_READY()
  local c = package.loaded["which-key.config"]
  if not (c and rawget(c, "loaded") == true) then return "which-key has not loaded its spec" end
  local S, B, T = package.loaded["which-key.state"], package.loaded["which-key.buf"], package.loaded["which-key.triggers"]
  if not (S and B and T) then return "which-key is not set up" end
  if S.state ~= nil then return "which-key is mid-sequence" end
  local mode = B.bufs[buf] and B.bufs[buf].modes.n
  if not mode then return "which-key has no normal-mode state for the buffer" end
  if T.suspended[mode] then return "which-key's triggers are suspended" end
  for _, node in ipairs(mode.triggers) do
    if not T.has({ buf = buf, mode = "n", keys = node.keys }) then return "which-key trigger " .. node.keys .. " is not attached" end
  end
  return "1"
end
function _G.WK_IDLE()
  local S = package.loaded["which-key.state"]
  return (S == nil or S.state == nil) and 1 or 0
end
vim.wait(5000, function() return WK_READY() == "1" end, 20)
vim.g.spy_ready = WK_READY()
EOF

# The client that drives it: the binary nv.sh runs, called straight, as nv.sh's setup on every call (a mise lookup when
# NVR_NVIM is unset) costs more than the call; in the check's own XDG dirs, as nv.sh would run it. A key left pending
# (r after a gr that ran on its own) blocks --remote-expr until the next key
BIN=$("$NV" "$V" --clean --headless --cmd 'lua io.stdout:write(vim.v.progpath)' --cmd 'qa!' </dev/null 2>/dev/null)
R() {
  XDG_CONFIG_HOME=$NVR_HOME/config XDG_DATA_HOME=$NVR_DATA XDG_STATE_HOME=$NVR_STATE XDG_CACHE_HOME=$NVR_HOME/cache \
    timeout 5 "$BIN" --clean --headless --server "$sock" "$@" </dev/null 2>/dev/null
}
"$NV" "$V" --headless --listen "$sock" \
  -c "autocmd VimEnter * ++once lua vim.schedule(function() dofile('$spy') end)" </dev/null >/dev/null 2>&1 &
pid=$!
finish() {
  [ -S "$sock" ] && R --remote-send '<C-\><C-n>:qa!<CR>' >/dev/null
  for _ in $(seq 150); do kill -0 "$pid" 2>/dev/null || break; sleep 0.02; done
  kill "$pid" 2>/dev/null
  rm -f "$sock" "$spy"
  out DONE
}

ready=0
for _ in $(seq 1250); do
  kill -0 "$pid" 2>/dev/null || break
  if [ -S "$sock" ]; then
    ready=$(R --remote-expr 'get(g:, "spy_ready", 0)')
    [ "$ready" != 0 ] && break
  fi
  sleep 0.02
done
if [ "$ready" != 1 ]; then
  out "FAIL fake server and which-key ready  -- ${ready:-nvim exited}"
  finish
  exit 0
fi

notes=$(R --remote-expr 'get(g:, "gr_notes", "")')
[ -n "$notes" ] && printf '%s\n' "$notes" >>"$CHECK_OUT"
mapfile -t plan < <(R --remote-expr 'get(g:, "gr_plan", "")')
out "INFO typed: ${plan[*]}"
if [ "${#plan[@]}" -eq 0 ] || [ -z "${plan[0]}" ]; then
  out "FAIL some gr* key to type  -- none mapped"
  finish
  exit 0
fi

hits() { local h; h=$(R --remote-expr 'luaeval("table.concat(HITS, \",\")")'); printf '%s' "${h//$'\n'/}"; }
seq_check() { # $1 keys, $2 gap between keys (the typing speed under test), $3 expected hits
  local got="" k why="" n=0 typed
  for _ in $(seq 250); do
    why=$(R --remote-expr 'luaeval("WK_READY()")')
    [ "$why" = 1 ] && break
    sleep 0.02
  done
  if [ "$why" != 1 ]; then
    out "FAIL which-key ready before [$1] with ${2}s gaps  -- ${why:-no answer}"
    return
  fi
  R --remote-expr 'luaeval("(function() HITS = {} return 0 end)()")' >/dev/null
  read -ra typed <<<"$1"
  # the gap is the typing speed under test, so it goes between keys only; after the last one the wait is for its hit
  for k in "${typed[@]}"; do
    R --remote-send "$k"
    n=$((n + 1))
    [ "$n" -lt "${#typed[@]}" ] && sleep "$2"
  done
  for _ in $(seq 150); do
    got=$(hits) || break
    [ -n "$got" ] && break
    sleep 0.02
  done
  # past the first hit: wait until which-key has finished the sequence, then take every hit it caused
  if [ -n "$got" ]; then
    for _ in $(seq 100); do [ "$(R --remote-expr 'luaeval("WK_IDLE()")')" = 1 ] && break; sleep 0.02; done
  fi
  R --remote-send '<Esc><C-\><C-n>'
  got=$(hits)
  for _ in $(seq 100); do [ "$(R --remote-expr 'mode()')" = n ] && break; sleep 0.02; done
  if [ "$got" = "$3" ]; then
    out "PASS typed [$1] with ${2}s gaps runs $3"
  else
    out "FAIL typed [$1] with ${2}s gaps runs $3 once  -- got '${got:-nothing}'"
  fi
}
for gap in 0.05 0.7; do
  for line in "${plan[@]}"; do
    read -r mode lhs target <<<"$line"
    keys=$(printf '%s' "$lhs" | sed 's/./& /g')
    if [ "$mode" = x ]; then
      seq_check "v $keys" "$gap" "$target:v"
    else
      seq_check "$keys" "$gap" "$target:n"
    fi
  done
done
finish
