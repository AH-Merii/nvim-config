-- @desc     each LSP key acts (its request reaches the server) and is listed by which-key in a buffer iff an attached client supports its method, through attach, detach, dynamic (un)registration and a second client; elsewhere it does what Vim's own key does, and an ftplugin's buffer map always wins
-- @areas    keys lsp which-key
-- @budget   40
-- Judged by pressing the keys and reading which-key's popup, never by which maps exist, so it holds for any
-- gating mechanism. In-process fake servers record the requests they get, so no tool needs installing.

local cur, n, bad
local function done()
  if cur and bad == 0 then check(cur, true, n .. " assertions") end
end
local function section(name)
  done()
  cur, n, bad = name, 0, 0
end
local function expect(ok, fmt, ...)
  n = n + 1
  if not ok then
    bad = bad + 1
    check(cur .. ": " .. fmt:format(...), false)
  end
  return ok
end
-- run what autocmds and handlers scheduled; two rounds cover a schedule made from a scheduled callback
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end

-- The LSP keys and the method each needs (any one of a list), from the config's key list, written out here so the
-- check does not read the config's tables. `sends`: the request a press makes, when it is not the need itself;
-- `fallback`: where Vim's own key leaves the cursor in LINES, from the x on line 3, where no client supports the
-- method (gr* keys are judged in their own section below).
local DEF, REF, IMPL, TYPE, DECL, CALLS =
  "textDocument/definition", "textDocument/references", "textDocument/implementation", "textDocument/typeDefinition",
  "textDocument/declaration", "textDocument/prepareCallHierarchy"
local KEYS = {
  { "gd", need = { DEF }, fallback = { 1, 0 } }, -- Vim's gd: the local declaration
  { "gD", need = { DECL }, fallback = { 1, 0 } }, -- Vim's gD: the global declaration
  { "gI", need = { IMPL } },
  { "grr", need = { REF } },
  { "gt", need = { TYPE }, fallback = "tab" }, -- Vim's gt: the next tab page
  { "gCi", need = { CALLS } },
  { "gCo", need = { CALLS } },
  -- Vim's ]] and [[: no { in column 1, so the last and the first line
  { "]]", need = { "textDocument/documentHighlight" }, sends = "jump", fallback = { 5, 0 } },
  { "[[", need = { "textDocument/documentHighlight" }, sends = "jump", fallback = { 1, 0 } },
  { "K", need = { "textDocument/hover" }, fallback = "keywordprg" },
  { "<leader>lr", need = { "textDocument/rename" }, sends = "textDocument/prepareRename" },
  { "<leader>cs", need = { "textDocument/documentSymbol" } },
  { "<leader>cl", need = { DEF, REF, IMPL, TYPE, DECL, CALLS } },
  { "<leader>Th", need = { "textDocument/inlayHint" }, sends = "inlay" },
  { "<leader>Tc", need = { "textDocument/codeLens" }, sends = "codelens" },
  { "<leader>sS", need = { "workspace/symbol" } },
  { "grn", need = { "textDocument/rename" }, sends = "textDocument/prepareRename" },
  { "gra", need = { "textDocument/codeAction" } },
  { "gra", mode = "x", need = { "textDocument/codeAction" } },
  { "gri", need = { IMPL } },
  { "grt", need = { TYPE } },
  { "gO", need = { "textDocument/documentSymbol" }, fallback = "nothing" },
}
local function name(key) return (key.mode or "n") .. " " .. key[1] end

local function caps_for(methods)
  local caps = {}
  for _, m in ipairs(methods) do
    local path = assert(vim.lsp.protocol._request_name_to_server_capability[m], "no capability path for " .. m)
    local t = caps
    for i = 1, #path - 1 do
      if type(t[path[i]]) ~= "table" then t[path[i]] = {} end
      t = t[path[i]]
    end
    if t[path[#path]] == nil then t[path[#path]] = true end
  end
  -- a rename key then asks prepareRename first, which answers "nothing to rename" instead of prompting for a name
  if caps.renameProvider then caps.renameProvider = { prepareProvider = true } end
  return caps
end
local function client_dynamic(m)
  local td = vim.lsp.protocol.make_client_capabilities().textDocument or {}
  local short = m:gsub("^textDocument/", "")
  local key = ({ prepareCallHierarchy = "callHierarchy" })[short] or short
  return td[key] ~= nil and td[key].dynamicRegistration == true
end
-- the references a documentHighlight answers with: the x on lines 1 to 3 of LINES
local HIGHLIGHTS = {
  { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 1 } } },
  { range = { start = { line = 1, character = 4 }, ["end"] = { line = 1, character = 5 } } },
  { range = { start = { line = 2, character = 4 }, ["end"] = { line = 2, character = 5 } } },
}
local servers = {}
local requests = {} -- method -> times any fake server got it
-- an in-process server advertising exactly `methods`, attached to buf; it records every request
local function start_fake(buf, name, methods)
  local srv = {}
  local function cmd(dispatchers)
    srv.dispatchers = dispatchers
    local closing, id = false, 0
    local function close()
      if not closing then
        closing = true
        vim.schedule(function() dispatchers.on_exit(0, 15) end)
      end
    end
    return {
      request = function(method, _, callback)
        id = id + 1
        requests[method] = (requests[method] or 0) + 1
        -- no locations, symbols or actions; no hover and nothing to rename
        local result = {}
        if method == "initialize" then
          result = { capabilities = caps_for(methods) }
        elseif method == "textDocument/documentHighlight" then
          result = HIGHLIGHTS
        elseif method == "textDocument/hover" or method == "textDocument/prepareRename" or method == "shutdown" then
          result = nil
        end
        vim.schedule(function() callback(nil, result) end)
        return true, id
      end,
      notify = function(method)
        if method == "exit" then close() end
        return true
      end,
      is_closing = function() return closing end,
      terminate = close,
    }
  end
  local id = vim.lsp.start({ name = name, cmd = cmd, root_dir = FIX }, { bufnr = buf, reuse_client = function() return false end })
  wait_until(function()
    local c = id and vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized and vim.lsp.buf_is_attached(buf, id)
  end, 3000)
  servers[id] = srv
  flush()
  return id
end
local function server_request(id, method, params)
  local sent = false
  vim.schedule(function()
    servers[id].dispatchers.server_request(method, params)
    sent = true
  end)
  wait_until(function() return sent end, 2000)
  flush()
end
local function stop(id)
  local c = vim.lsp.get_client_by_id(id)
  if c then c:stop(true) end
  wait_until(function() return vim.lsp.get_client_by_id(id) == nil end, 3000)
  flush()
end

-- a prompt a key opens is cancelled, as the user would, so no press waits for input
vim.ui.input = function(_, on_confirm) on_confirm(nil) end

local DIR = FIX .. "/.nvr-lsp"
vim.fn.mkdir(DIR, "p")
local LINES = { "x = 1", "y = x", "z = x", "w = 4", "v = 5" }
-- K's fallback is 'keywordprg'; this one records the word instead of running man
local kw = {}
vim.api.nvim_create_user_command("NvrKeyword", function(a) kw[#kw + 1] = a.args end, { nargs = "*" })
local function scratch(file)
  vim.cmd.edit(DIR .. "/" .. file)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  vim.bo[buf].filetype = "sbxfake"
  vim.bo[buf].keywordprg = ":NvrKeyword"
  flush()
  return buf
end

-- back to buf alone in one tab, in normal mode, with LINES, no picker, list or float left open
local function reset(buf)
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  vim.cmd("stopinsert")
  -- a picker closed while its finder still runs fails in the finder's next step
  local ok, pickers = pcall(function() return Snacks.picker.get() end)
  for _, p in ipairs(ok and pickers or {}) do
    wait_until(function() return not p:is_active() end, 2000)
    pcall(function() p:close() end)
  end
  pcall(function() require("trouble").close() end)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then pcall(vim.api.nvim_win_close, w, true) end
  end
  flush()
  vim.cmd("silent! tabonly | silent! only | silent! lclose | silent! cclose")
  if vim.api.nvim_get_current_buf() ~= buf then vim.cmd.buffer(buf) end
  if table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= table.concat(LINES, "\n") then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  end
  vim.bo[buf].modified = false
end

-- press key in buf from the x on line 3; what it did: the requests it made, where the cursor went, the tab page,
-- 'keywordprg' runs, inlay hints or code lenses flipped, and whether the text changed. `acts`: whether it should act, so a press
-- that should waits for its request and one that should not only lets what it scheduled run
local function press(buf, key, acts)
  reset(buf)
  local mode = key.mode or "n"
  local before = vim.deepcopy(requests)
  if key.sends == "jump" and #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/documentHighlight" }) > 0 then
    -- the references Snacks.words jumps between, as the editor shows them once the cursor rests on x
    vim.api.nvim_win_set_cursor(0, { 2, 4 })
    vim.lsp.buf.document_highlight()
    wait_until(function() return #vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("nvim.lsp.references"), 0, -1, {}) == #HIGHLIGHTS end, 2000)
  end
  vim.api.nvim_win_set_cursor(0, key[1] == "]]" and { 2, 4 } or { 3, 4 })
  -- a second tab page, for gt to go to
  vim.cmd("tab split | tabprevious")
  local tabs, nkw = vim.fn.tabpagenr(), #kw
  local hints, lenses = vim.lsp.inlay_hint.is_enabled({ bufnr = buf }), vim.lsp.codelens.is_enabled({ bufnr = buf })
  feed((mode == "x" and "v" or "") .. key[1])
  local r = { cursor = vim.api.nvim_win_get_cursor(0), tab = vim.fn.tabpagenr() ~= tabs, keyword = #kw > nkw }
  local want = key.sends ~= nil and key.sends:find("/") and { key.sends } or key.need
  local function asked()
    for _, m in ipairs(want) do
      if (requests[m] or 0) > (before[m] or 0) then return m end
    end
  end
  local ms = acts and 2000 or 0
  if not acts then flush() end
  if key.sends == "inlay" then
    r.acted = wait_until(function() return vim.lsp.inlay_hint.is_enabled({ bufnr = buf }) ~= hints end, ms)
    -- back as it was
    if r.acted then vim.lsp.inlay_hint.enable(hints, { bufnr = buf }) end
  elseif key.sends == "codelens" then
    r.acted = wait_until(function() return vim.lsp.codelens.is_enabled({ bufnr = buf }) ~= lenses end, ms)
    if r.acted then vim.lsp.codelens.enable(lenses, { bufnr = buf }) end
  elseif key.sends == "jump" then
    -- Snacks.words jumps from the x on line 2 or 3 to the next or previous one, not where Vim's ]] or [[ go
    r.acted = r.cursor[1] == (key[1] == "]]" and 3 or 2) and r.cursor[2] == 4
  else
    r.acted = wait_until(asked, ms) and true or false
  end
  r.changed = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") ~= table.concat(LINES, "\n")
  r.text = vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1]
  reset(buf)
  return r
end
local function show(r) return ("cursor %d:%d%s%s%s"):format(r.cursor[1], r.cursor[2], r.tab and ", tab changed" or "", r.keyword and ", keywordprg ran" or "", r.changed and ", text changed" or "") end

local function holds(key, supported)
  for _, m in ipairs(key.need) do
    if supported[m] then return true end
  end
  return false
end
local function set(list)
  local s = {}
  for _, m in ipairs(list) do s[m] = true end
  return s
end
-- what which-key lists for every key in buf, against what the clients support
local function listing(label, buf, supported)
  for _, key in ipairs(KEYS) do
    local listed = wk_lists(buf, key.mode or "n", key[1]) ~= nil
    expect(listed == holds(key, supported), "[%s] %s %s, want %s", label, name(key), listed and "listed" or "not listed", holds(key, supported) and "listed" or "not listed")
  end
end
-- press every key: it acts where a client supports it; elsewhere it does not, and does Vim's own key instead
local function presses(label, buf, supported, keys)
  for _, key in ipairs(keys or KEYS) do
    local r = press(buf, key, holds(key, supported))
    if holds(key, supported) then
      expect(r.acted, "[%s] %s acts (%s)", label, name(key), show(r))
    else
      expect(not r.acted, "[%s] %s does not act where no client supports it (%s)", label, name(key), show(r))
      local fb = key.fallback
      if type(fb) == "table" then
        expect(r.cursor[1] == fb[1] and r.cursor[2] == fb[2], "[%s] %s does Vim's own: cursor to %d:%d (%s)", label, name(key), fb[1], fb[2], show(r))
      elseif fb == "tab" then
        expect(r.tab, "[%s] %s does Vim's own: next tab page (%s)", label, name(key), show(r))
      elseif fb == "keywordprg" then
        expect(r.keyword, "[%s] %s does Vim's own: runs 'keywordprg' (%s)", label, name(key), show(r))
      elseif fb == "nothing" then
        expect(not r.changed and r.cursor[1] == 3 and r.cursor[2] == 4, "[%s] %s leaves the text and cursor alone (%s)", label, name(key), show(r))
      end
    end
  end
end

local all = {}
for _, key in ipairs(KEYS) do
  for _, m in ipairs(key.need) do all[m] = true end
end
local methods = vim.tbl_keys(all)
table.sort(methods)
-- two halves, so each single-method key is seen with and without a supporting client
local S1, S2 = {}, {}
for i, m in ipairs(methods) do table.insert(i % 2 == 1 and S1 or S2, m) end

section("no client")
local b0 = scratch("none.sbxfake")
listing("no client", b0, {})
presses("no client", b0, {})

section("attach and detach")
local b1 = scratch("half.sbxfake")
local c1 = start_fake(b1, "fake-S1", S1)
listing("client S1", b1, set(S1))
presses("client S1", b1, set(S1))
stop(c1)
listing("S1 stopped", b1, {})
local c2 = start_fake(b1, "fake-S2", S2)
listing("client S2", b1, set(S2))
presses("client S2", b1, set(S2))
stop(c2)
listing("S2 stopped", b1, {})

section("dynamic registration")
local dyn = vim.tbl_filter(client_dynamic, methods)
expect(#dyn > 0, "some method is accepted by dynamic registration")
local dyn_keys = vim.tbl_filter(function(k) return holds(k, set(dyn)) end, KEYS)
local b3 = scratch("dyn.sbxfake")
local c3 = start_fake(b3, "fake-dyn", {})
listing("dyn before register", b3, {})
-- rename with prepareProvider, as caps_for gives it
local function registration(m) return { id = m, method = m, registerOptions = m == "textDocument/rename" and { prepareProvider = true } or nil } end
server_request(c3, "client/registerCapability", { registrations = vim.tbl_map(registration, dyn) })
listing("dyn registered", b3, set(dyn))
presses("dyn registered", b3, set(dyn), dyn_keys)
server_request(c3, "client/unregisterCapability", { unregisterations = vim.tbl_map(function(m) return { id = m, method = m } end, dyn) })
listing("dyn unregistered", b3, {})
stop(c3)

section("two clients")
local b4 = scratch("two.sbxfake")
local ca = start_fake(b4, "fake-all", methods)
local cb = start_fake(b4, "fake-S1b", S1)
listing("two clients", b4, set(methods))
stop(ca)
listing("all-client stopped, S1 remains", b4, set(S1))
stop(cb)
listing("both stopped", b4, {})

section("an ftplugin's buffer map wins")
local b5 = scratch("foreign.sbxfake")
local ran = {}
for _, key in ipairs(KEYS) do
  vim.keymap.set(key.mode or "n", key[1], function() ran[name(key)] = (ran[name(key)] or 0) + 1 end, { buf = b5 })
end
local c5 = start_fake(b5, "fake-all5", methods)
for _, key in ipairs(KEYS) do
  local r = press(b5, key, false)
  expect(ran[name(key)] == 1 and not r.acted, "[attached] %s runs the buffer's own map, not the LSP action (own map ran %d times)", name(key), ran[name(key)] or 0)
end
stop(c5)
ran = {}
for _, key in ipairs(KEYS) do
  press(b5, key, false)
  expect(ran[name(key)] == 1, "[detached] %s still runs the buffer's own map", name(key))
end

section("every key a server brings is judged")
-- the keys the popup gains when a server that supports every method attaches: each is one of KEYS, or a key a
-- check of its own judges (the format keys in keys_format_gate, the diagnostics keys in keys_diag_gate, grx, which
-- needs a code lens on its line, in keys_act_here)
local ELSEWHERE = { "n <leader>lf", "x <leader>lf", "n <leader>Tf", "n <leader>xX", "n <leader>sd", "n grx" }
local Util = require("which-key.util")
local known = {}
for _, key in ipairs(KEYS) do known[(key.mode or "n") .. " " .. Util.norm(key[1])] = true end
for _, k in ipairs(ELSEWHERE) do
  local mode, lhs = k:match("^(%S+) (%S+)$")
  known[mode .. " " .. Util.norm(lhs)] = true
end
-- every method but the ones Neovim requests by itself once supported, whose answers this server cannot fake
local AUTO = { "textDocument/diagnostic", "workspace/diagnostic", "textDocument/linkedEditingRange", "textDocument/semanticTokens",
  "textDocument/inlayHint", "textDocument/documentColor", "textDocument/foldingRange", "textDocument/codeLens",
  "textDocument/inlineCompletion", "textDocument/documentLink" }
local every = vim.tbl_filter(function(m)
  return not vim.iter(AUTO):any(function(a) return m == a or vim.startswith(m, a .. "/") end)
end, vim.tbl_keys(vim.lsp.protocol._request_name_to_server_capability))
local b7 = scratch("every.sbxfake")
local before = { n = wk_menu(b7, "n"), x = wk_menu(b7, "x") }
local c7 = start_fake(b7, "fake-every", every)
local gained, unknown = {}, {}
for _, mode in ipairs({ "n", "x" }) do
  for lhs, label in pairs(wk_menu(b7, mode)) do
    if before[mode][lhs] == nil then
      gained[#gained + 1] = mode .. " " .. lhs
      if not known[mode .. " " .. lhs] then unknown[#unknown + 1] = mode .. " " .. lhs .. " (" .. tostring(label) .. ")" end
    end
  end
end
stop(c7)
table.sort(gained)
table.sort(unknown)
info("gained with every method: " .. table.concat(gained, ", "))
expect(#gained > 0, "a server with every method brings keys")
expect(#unknown == 0, "every key a server brings is judged here or by its own check; not judged: %s", table.concat(unknown, ", "))

section("gr* with no server: a message naming the missing need")
-- D49: Vim's gr{char} would replace the character under the cursor; the key says which method no server supports
local b6 = scratch("grchar.sbxfake")
for _, key in ipairs(KEYS) do
  if key[1]:match("^gr.$") and (key.mode or "n") == "n" then
    vim.cmd("messages clear")
    local r = press(b6, key, false)
    local said = vim.api.nvim_exec2("messages", { output = true }).output
    local named = said:find(key.need[1], 1, true) ~= nil
    expect(not r.acted and r.text == "z = x", "%s leaves the x under the cursor (line 3 now %q)", key[1], tostring(r.text))
    expect(named, "%s says it needs %s (said: %q)", key[1], key.need[1], said)
  end
end

section("Neovim's gr* and gO keys are among the LSP keys")
-- read from a --clean nvim of the same binary, so the list follows the runtime
local tmp = vim.fn.tempname()
vim.system({ vim.v.progpath, "--clean", "--headless", "-c",
  ([[lua local t = {} for _, mode in ipairs({ "n", "x" }) do for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do if m.lhs:match("^gr") or m.lhs == "gO" then t[#t + 1] = mode .. " " .. m.lhs end end end vim.fn.writefile(t, %q)]]):format(tmp),
  "-c", "qa!" }):wait()
local builtins = vim.fn.filereadable(tmp) == 1 and vim.fn.readfile(tmp) or {}
info("runtime built-ins: " .. table.concat(builtins, ", "))
expect(#builtins > 0, "the runtime defines gr* maps")
-- grx acts where a code lens is on its line (D132), judged in keys_act_here
local ours = { ["n grx"] = true }
for _, key in ipairs(KEYS) do ours[name(key)] = true end
for _, line in ipairs(builtins) do
  expect(ours[line], "runtime %s is judged here or in keys_act_here, so it acts only where it can", line)
end
done()
