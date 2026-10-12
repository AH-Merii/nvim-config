# @desc     typed one key at a time, fast and slow, once which-key's triggers are attached, every gr* key the runtime or the config maps runs exactly once the action the config declares for it (normal mode, and visual for x maps), in a buffer with an LSP client: no shorter gr map swallows them
# @areas    keys lsp which-key
# @budget   90
# @needs    lua-language-server
# Ported from nvim-sbx-keys/checks2/interactive_gr.sh and spy_gr.lua. Keys go through --remote-send one at a
# time: feeding "grn" at once resolves the longest match and hides a shorter nowait map.
set -u
out() { printf '%s\n' "$*" >>"$CHECK_OUT"; }
sock=/tmp/nvr-gr-$V-$$.sock
spy=$FIX/.nvr-spy-gr.lua
cat >"$spy" <<'EOF'
-- headless never gets UIEnter, so fire VeryLazy; wait for a client that serves rename, code action and references
vim.g.did_very_lazy = true
vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
local buf = vim.api.nvim_get_current_buf()
local function ready()
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    if c.initialized and c:supports_method("textDocument/rename", buf) and c:supports_method("textDocument/codeAction", buf)
      and c:supports_method("textDocument/references", buf) then return true end
  end
  return false
end
local t0 = vim.uv.now()
vim.wait(15000, function() return ready() or (#vim.lsp.get_clients({ bufnr = buf }) == 0 and vim.uv.now() - t0 > 3000) end, 50)
if not ready() then
  vim.g.spy_ready = "no client serving rename, codeAction and references attached to " .. vim.api.nvim_buf_get_name(buf)
  return
end
-- let the LspAttach work the config scheduled (buffer-local maps) run
for _ = 1, 2 do
  local ran = false
  vim.schedule(function() ran = true end)
  vim.wait(1000, function() return ran end, 10)
end

-- the tables a gr* action is looked up in at call time
local NS = {
  { "Snacks.picker", function() return Snacks.picker end, function(t) Snacks.picker = t end },
  { "vim.lsp.buf", function() return vim.lsp.buf end, function(t) vim.lsp.buf = t end },
  { "vim.lsp.codelens", function() return vim.lsp.codelens end, function(t) vim.lsp.codelens = t end },
}
-- the first NS function fn calls, as "<table>.<function>", without running it
local function target(fn)
  local hit
  local saved = {}
  for i, ns in ipairs(NS) do
    local real = ns[2]()
    saved[i] = real
    ns[3](setmetatable({}, { __index = function(_, k)
      if ns[1] ~= "Snacks.picker" and type(real[k]) ~= "function" then return real[k] end
      return function() hit = hit or (ns[1] .. "." .. k) end
    end }))
  end
  local ok, err = pcall(fn)
  for i, ns in ipairs(NS) do ns[3](saved[i]) end
  return hit, not ok and tostring(err) or "it calls nothing in " .. table.concat(vim.tbl_map(function(ns) return ns[1] end, NS), ", ")
end
local function action(rhs, map)
  if type(rhs) == "function" then return rhs end
  local body = type(rhs) == "string" and rhs:match("^<[Cc][Mm][Dd]>(.*)<[Cc][Rr]>$")
  if body then return function() vim.cmd(body) end end
  return map and map.callback
end

-- every gr* key: the runtime's own (from a --clean nvim of the same binary), the config's gated ones, the buffer's
local order, seen = {}, {}
local function want(mode, lhs)
  if not seen[mode .. " " .. lhs] then
    seen[mode .. " " .. lhs] = true
    order[#order + 1] = { mode, lhs }
  end
end
local tmp = vim.fn.tempname()
vim.system({ vim.v.progpath, "--clean", "--headless", "-c",
  ([[lua local t = {} for _, mode in ipairs({ "n", "x" }) do for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do if m.lhs:match("^gr.") then t[#t + 1] = mode .. " " .. m.lhs end end end vim.fn.writefile(t, %q)]]):format(tmp),
  "-c", "qa!" }, { stdin = false }):wait()
local builtins = vim.fn.filereadable(tmp) == 1 and vim.fn.readfile(tmp) or {}
os.remove(tmp)
for _, line in ipairs(builtins) do
  local mode, lhs = line:match("^(%S+) (%S+)$")
  if mode then want(mode, lhs) end
end
local declared = {}
local ok_core, core = pcall(require, "core.lsp")
for _, k in ipairs(ok_core and type(core) == "table" and type(core.keys) == "table" and core.keys or {}) do
  if type(k[1]) == "string" and k[1]:match("^gr.") then
    for _, mode in ipairs(type(k.mode) == "table" and k.mode or { k.mode or "n" }) do
      declared[mode .. " " .. k[1]] = k
      want(mode, k[1])
    end
  end
end
for _, mode in ipairs({ "n", "x" }) do
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs:match("^gr.") and not (m.desc or ""):find("which-key-trigger", 1, true) then want(mode, m.lhs) end
  end
end

local clients = vim.lsp.get_clients({ bufnr = buf })
local function serves(entry)
  local methods = type(entry.method) == "table" and entry.method or { entry.method }
  for _, c in ipairs(clients) do
    for _, m in ipairs(methods) do
      if c:supports_method(m, buf) then return true end
    end
  end
  return type(entry.when) == "function" and entry.when(buf, clients) == true
end
local plan, notes, targets = {}, {}, {}
for _, w in ipairs(order) do
  local mode, lhs = w[1], w[2]
  local decl = declared[mode .. " " .. lhs]
  local map = vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode, false, true) end)
  if decl and not serves(decl) then
    notes[#notes + 1] = ("INFO %s %s not typed: no attached client serves %s, so the config leaves it out"):format(mode, lhs, vim.inspect(decl.method))
  elseif not next(map) then
    notes[#notes + 1] = ("FAIL %s %s is mapped in a buffer with an LSP client  -- no map"):format(mode, lhs)
  elseif not lhs:match("^%w+$") then
    notes[#notes + 1] = ("INFO %s %s not typed: the lhs has special keys"):format(mode, lhs)
  else
    -- what the config declares for the key, else what the map that resolves runs
    local fn = action(decl and decl[2], map)
    local t, why = target(fn or function() end)
    if t then
      plan[#plan + 1] = ("%s %s %s"):format(mode, lhs, t)
      targets[t] = true
    else
      notes[#notes + 1] = ("FAIL %s %s runs an action the spies can see  -- %s"):format(mode, lhs, why)
    end
  end
end
vim.g.gr_plan, vim.g.gr_notes = table.concat(plan, "\n"), table.concat(notes, "\n")

_G.HITS = {}
for t in pairs(targets) do
  for _, ns in ipairs(NS) do
    if t:sub(1, #ns[1] + 1) == ns[1] .. "." then
      ns[2]()[t:sub(#ns[1] + 2)] = function() table.insert(HITS, t .. ":" .. vim.fn.mode()) end
    end
  end
end

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

# a key left pending (r after a gr that ran on its own) blocks --remote-expr until the next key
R() { timeout 5 "$NV" "$V" --clean --headless --server "$sock" "$@" </dev/null 2>/dev/null; }
"$NV" "$V" --headless --listen "$sock" main.lua \
  -c "autocmd VimEnter * ++once lua vim.schedule(function() dofile('$spy') end)" </dev/null >/dev/null 2>&1 &
pid=$!
finish() {
  [ -S "$sock" ] && R --remote-send '<C-\><C-n>:qa!<CR>' >/dev/null
  for _ in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  kill "$pid" 2>/dev/null
  rm -f "$sock" "$spy"
  out DONE
}

ready=0
for _ in $(seq 250); do
  kill -0 "$pid" 2>/dev/null || break
  if [ -S "$sock" ]; then
    ready=$(R --remote-expr 'get(g:, "spy_ready", 0)')
    [ "$ready" != 0 ] && break
  fi
  sleep 0.1
done
if [ "$ready" != 1 ]; then
  out "FAIL spies and which-key ready on main.lua  -- ${ready:-nvim exited}"
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
  local got="" k why=""
  for _ in $(seq 50); do
    why=$(R --remote-expr 'luaeval("WK_READY()")')
    [ "$why" = 1 ] && break
    sleep 0.1
  done
  if [ "$why" != 1 ]; then
    out "FAIL which-key ready before [$1] with ${2}s gaps  -- ${why:-no answer}"
    return
  fi
  R --remote-expr 'luaeval("(function() HITS = {} return 0 end)()")' >/dev/null
  for k in $1; do
    R --remote-send "$k"
    sleep "$2"
  done
  for _ in $(seq 30); do
    got=$(hits) || break
    [ -n "$got" ] && break
    sleep 0.1
  done
  # past the first hit: wait until which-key has finished the sequence, then take every hit it caused
  if [ -n "$got" ]; then
    for _ in $(seq 20); do [ "$(R --remote-expr 'luaeval("WK_IDLE()")')" = 1 ] && break; sleep 0.1; done
  fi
  R --remote-send '<Esc><C-\><C-n>'
  got=$(hits)
  for _ in $(seq 20); do [ "$(R --remote-expr 'mode()')" = n ] && break; sleep 0.1; done
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
