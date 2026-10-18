-- Loaded with -c by suite.sh. On VimEnter it fires User VeryLazy (headless never gets UIEnter, lua/app/init.lua),
-- runs $CHECK and appends one line per result to $CHECK_OUT, then quits. See README.md for the API.
local OUT = assert(vim.env.CHECK_OUT, "CHECK_OUT unset")
local CHECK = assert(vim.env.CHECK, "CHECK unset")

local function emit(line)
  local f = assert(io.open(OUT, "a"))
  f:write((line:gsub("\n", "\\n")), "\n")
  f:close()
end

_G.FIX = vim.fn.getcwd()
_G.VERSION = vim.env.NVR_VERSION

function _G.check(name, ok, detail)
  emit(string.format("%s %s%s", ok and "PASS" or "FAIL", name, detail ~= nil and ("  -- " .. tostring(detail)) or ""))
  return ok
end
function _G.info(msg) emit("INFO " .. tostring(msg)) end
function _G.feed(keys) vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false) end
function _G.wait_until(pred, ms) return vim.wait(ms or 5000, pred, 10) end

-- :checkhealth <name>, complete. Nightly renders it asynchronously; both versions set filetype checkhealth as the last step.
function _G.health(name, ms)
  local done = {}
  local au = vim.api.nvim_create_autocmd("FileType", {
    pattern = "checkhealth",
    callback = function(a) done[a.buf] = true end,
  })
  vim.cmd("checkhealth " .. name)
  local buf = vim.api.nvim_get_current_buf()
  local ok = vim.wait(ms or 10000, function() return done[buf] end, 10)
  pcall(vim.api.nvim_del_autocmd, au)
  local text = ok and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") or nil
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  return text or "TIMEOUT"
end
function _G.deprecations() return health("vim.deprecated") end

-- Servers that must attach to buf: enabled, covering the filetype, accepted by a root_dir function or
-- holding a root when workspace_required, and with a runnable cmd.
-- A function cmd picks its binary itself (the tools resolver's absolute path), so it is expected and judged by attaching.
-- A root_dir function declines by never calling on_dir; the resolver's wrapper does that when the binary is
-- missing, so a declined catalog server whose binary did not resolve gets a note saying why.
-- Waits up to ms for root_dir lookups to answer; one still looking at the deadline is expected, so a hang fails.
function _G.lsp_expected(buf, ms)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  ms = ms or 10000
  local names = {}
  for _, f in ipairs(vim.api.nvim_get_runtime_file("lsp/*.lua", true)) do
    names[vim.fn.fnamemodify(f, ":t:r")] = true
  end
  for n in pairs(vim.lsp._enabled_configs or {}) do names[n] = true end
  local ft, want, notes = vim.bo[buf].filetype, {}, {}
  local fname = vim.api.nvim_buf_get_name(buf)
  local cands, roots = {}, {}
  local system = vim.system
  for name in pairs(names) do
    if vim.lsp.is_enabled(name) then
      local c = vim.lsp.config[name]
      if c and (c.filetypes == nil or vim.list_contains(c.filetypes, ft)) then
        cands[name] = c
        if type(c.root_dir) == "function" then
          -- a root_dir function declines a buffer by never calling on_dir (biome without a biome.json)
          local r = { n = 0, cmds = {} }
          roots[name] = r
          vim.system = function(cmd, opts, on_exit)
            if type(opts) == "function" then opts, on_exit = nil, opts end
            if not on_exit then return system(cmd, opts) end
            r.n = r.n + 1
            table.insert(r.cmds, cmd[1])
            local ok, obj = pcall(system, cmd, opts, function(res)
              on_exit(res)
              r.n = r.n - 1
            end)
            if not ok then
              r.n = r.n - 1
              error(obj, 0)
            end
            return obj
          end
          r.ok = pcall(c.root_dir, buf, function(dir) r.got = dir or false end)
          vim.system = system
        end
      end
    end
  end
  local function looking(r) return r.ok and r.got == nil and r.n > 0 end
  wait_until(function() return not vim.iter(vim.tbl_values(roots)):any(looking) end, ms)
  -- a lookup's callback may schedule on_dir rather than call it; two rounds cover a nested schedule
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
  for name, c in pairs(cands) do
    local root_ok, r = true, roots[name]
    if r then
      root_ok = r.ok and (r.got ~= nil or looking(r))
      if looking(r) then
        notes[name] = string.format("root_dir ran %s, no on_dir within %gs", table.concat(r.cmds, ","), ms / 1000)
      end
    elseif c.workspace_required and c.root_markers then
      root_ok = vim.fs.root(fname, c.root_markers) ~= nil
    end
    local runnable = type(c.cmd) == "function" or (type(c.cmd) == "table" and vim.fn.executable(c.cmd[1]) == 1)
    if root_ok and runnable then
      table.insert(want, name)
    elseif r and r.got == nil then
      local bin = package.loaded["tools"] and require("tools.catalog").binary("server", name)
      local res = bin and require("tools").get(bin, require("tools").root(buf))
      if res and not res.path then notes[name] = ("not expected: %s is missing (%s)"):format(bin, res.reason or "?") end
    end
  end
  table.sort(want)
  return want, notes
end

-- Last lines of lsp.log that mention pat (server name or binary).
function _G.lsp_log_tail(pat, n)
  local lines = {}
  local ok, all = pcall(vim.fn.readfile, vim.lsp.log.get_filename())
  if not ok then return "" end
  for _, l in ipairs(all) do
    if l:find(pat, 1, true) then table.insert(lines, l) end
  end
  return table.concat(vim.list_slice(lines, math.max(1, #lines - (n or 2) + 1)), " | ")
end

-- Wait for names to attach to buf. Returns early once every missing server has failed: its client
-- exited, never got created after a spawn error, or detached. Returns missing names and reasons.
function _G.wait_attach(buf, names, ms)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local seen, reason = {}, {}
  local au = vim.api.nvim_create_autocmd("LspDetach", {
    buffer = buf,
    callback = function(a)
      local c = vim.lsp.get_client_by_id(a.data.client_id)
      if c then reason[c.name] = "detached" end
    end,
  })
  local function missing()
    return vim.tbl_filter(function(n) return not vim.lsp.get_clients({ bufnr = buf, name = n })[1] end, names)
  end
  local t0 = vim.uv.hrtime()
  vim.wait(ms or 15000, function()
    local m = missing()
    if #m == 0 then return true end
    for _, n in ipairs(m) do
      if vim.lsp.get_clients({ name = n, _uninitialized = true })[1] then
        seen[n] = true
      elseif seen[n] then
        reason[n] = reason[n] or "client exited before attaching"
      elseif (vim.uv.hrtime() - t0) > 3e9 then
        reason[n] = reason[n] or "no client started within 3s"
      end
    end
    for _, n in ipairs(m) do
      if not reason[n] then return false end
    end
    return true
  end, 20)
  pcall(vim.api.nvim_del_autocmd, au)
  local m = missing()
  local why = {}
  for _, n in ipairs(m) do
    local c = vim.lsp.config[n]
    local bin = c and type(c.cmd) == "table" and c.cmd[1] or n
    table.insert(why, string.format("%s: %s%s", n, reason[n] or "timeout",
      (function() local t = lsp_log_tail(bin, 2) return t ~= "" and (" [lsp.log " .. t .. "]") or "" end)()))
  end
  return m, why
end

-- Wait until pred(vim.diagnostic.get(buf)) is true; returns the diagnostics.
function _G.wait_diagnostics(buf, pred, ms)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  pred = pred or function(d) return #d > 0 end
  vim.wait(ms or 10000, function() return pred(vim.diagnostic.get(buf)) end, 20)
  return vim.diagnostic.get(buf)
end

-- which-key's popup for buf and mode, built as a key press builds it, with buf current: which-key's filter gets no
-- buffer, so a global map that the filter hides where it cannot act is left out as a buffer-local one would be.
-- Each read schedules which-key work, so a wait_until predicate that reads it wakes itself forever: wait with
-- wk_wait instead.
local function wk_tree(buf, mode, fn)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local function loaded()
    local c = package.loaded["which-key.config"]
    return c ~= nil and rawget(c, "loaded") == true
  end
  assert(loaded() or wait_until(loaded, 5000), "which-key never loaded its spec")
  return vim.api.nvim_buf_call(buf, function()
    local m = require("which-key.buf").get({ buf = buf, mode = mode, update = true })
    return fn(m and m.tree)
  end)
end
-- the label a node shows: its desc, true for none, nil for a node the popup leaves out
local function wk_label(node)
  if not node or node.hidden or not (node.keymap or node.mapping or node:is_group()) then return nil end
  local d = node.desc
  if type(d) == "function" then d = d() end
  return type(d) == "string" and d ~= "" and d or true
end

-- What which-key's popup lists for lhs in buf and mode: its label (true when it has none), or nil where the popup
-- leaves it out.
function _G.wk_lists(buf, mode, lhs)
  return wk_tree(buf, mode, function(tree)
    return wk_label(tree and tree.root:find(require("which-key.util").keys(lhs, { norm = true })))
  end)
end

-- Every key the popup lists for buf and mode, groups left out, as { [keys] = label }, keys as which-key writes them
-- ("<Space>Gu").
function _G.wk_menu(buf, mode)
  return wk_tree(buf, mode, function(tree)
    local out = {}
    if tree then
      tree:walk(function(node)
        local label = wk_label(node)
        if label ~= nil and (node.keymap or not node:is_group()) then out[node.keys] = label end
      end)
    end
    return out
  end)
end

-- Wait up to ms (5000) until which-key lists lhs in buf and mode (listed true) or leaves it out (false); returns
-- whether it got there, and the last wk_lists answer.
function _G.wk_wait(buf, mode, lhs, listed, ms)
  local deadline, got = vim.uv.now() + (ms or 5000), nil
  repeat
    got = wk_lists(buf, mode, lhs)
    if (got ~= nil) == listed then return true, got end
    vim.wait(50)
  until vim.uv.now() >= deadline
  return false, got
end

-- @needs: catalog binaries the check needs; each must resolve to a path (suite.sh --refresh installs them
-- into the suite's own mise). A missing one fails the check before its body runs.
function _G.needs_resolve()
  local list
  for line in io.lines(CHECK) do
    list = line:match("^%-%- @needs +(.*)$")
    if list or not line:match("^%-%-") then break end
  end
  local ok = true
  for name in (list or ""):gmatch("%S+") do
    local r = require("tools").wait(name, FIX, 15000)
    if not (r and r.path) then
      ok = false
      check("needed tool " .. name .. " resolves", false,
        (r and (r.source .. ": " .. (r.reason or "")) or "no answer within 15s") .. " (run suite.sh --refresh)")
    end
  end
  return ok
end

local function main()
  if not vim.g.did_very_lazy then
    vim.g.did_very_lazy = true
    vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
  end
  vim.wait(30) -- what the deferred plugins' setups schedule
  vim.v.errmsg = ""
  local ok, err = true, nil
  if needs_resolve() then ok, err = xpcall(dofile, debug.traceback, CHECK) end
  if not ok then check("check script ran", false, err) end
  -- The quit kills nvim-lint's runs still going (linting/nvim_lint.lua); let them finish first, so an error one reports
  -- late still reaches the MSG and NOTIFY lines below
  local lint = package.loaded["lint"]
  if lint and lint.get_running then
    if not wait_until(function() return #lint.get_running() == 0 end, 15000) then
      info("linters still running at exit: " .. table.concat(lint.get_running(), ","))
    end
  end
  -- ui2 keeps no history of its own: its msg and cmd windows clear, and its pager renders this same
  -- :messages history, so :messages holds every error ui2 shows (and ui2 stays off headless anyway)
  local msgs = vim.api.nvim_exec2("messages", { output = true }).output
  for line in msgs:gmatch("[^\n]+") do
    if line:find("E%d+:") or line:find("Error") or line:find("stack traceback") then emit("MSG " .. line) end
  end
  -- snacks.notifier takes over vim.notify and never echoes, so :messages misses its errors
  -- a require that failed leaves a non-table here; the MSG lines above already report why
  local notifier = package.loaded["snacks.notifier"]
  if type(notifier) == "table" and notifier.get_history then
    for _, n in ipairs(notifier.get_history({ filter = vim.log.levels.ERROR })) do emit("NOTIFY " .. tostring(n.msg)) end
  end
  emit("DONE")
  vim.cmd("qa!")
end

vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = function() vim.schedule(main) end })
