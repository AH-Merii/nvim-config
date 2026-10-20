-- @desc     the buffer-diagnostics keys (<leader>dd, <leader>sd) are listed by which-key, and open their list when pressed, iff the buffer has a diagnostic (D132): not for an attached client or a linted filetype alone, nor for another buffer's diagnostics
-- @areas    keys lint lsp which-key
-- @budget   40
-- Judged by pressing the keys and reading which-key's popup, never by which maps exist.

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

local servers = {}
-- an in-process server with no capabilities, attached to buf
local function start_fake(buf, name)
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
        vim.schedule(function() callback(nil, method == "initialize" and { capabilities = {} } or vim.NIL) end)
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
local function stop(id)
  local c = vim.lsp.get_client_by_id(id)
  if c then c:stop(true) end
  wait_until(function() return vim.lsp.get_client_by_id(id) == nil end, 3000)
  flush()
end
local DIR = FIX .. "/.nvr-diag"
vim.fn.mkdir(DIR, "p")
local nbuf = 0
local function buf_of(ft)
  nbuf = nbuf + 1
  vim.cmd.edit(("%s/d%d.txt"):format(DIR, nbuf))
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = ft
  flush()
  return buf
end

local lint, lang = require("lint"), require("lang")
-- a language for ft that names linters, as a file in lua/lang/ would, and nvim-lint's entry as lang's views give it
-- at startup
local function declare(ft, linters)
  local named = {}
  for _, name in ipairs(linters) do
    named[name] = {}
  end
  lang._declare("nvr_" .. ft, { filetypes = { ft }, linters = named })
  lint.linters_by_ft[ft] = #linters > 0 and linters or nil
end
-- the buffer-diagnostics keys, from the config's key list
local KEYS = { "<leader>dd", "<leader>sd" }

-- windows open, so a press that opens a list or a picker shows
local function windows() return #vim.api.nvim_list_wins() end
local function close_all(buf)
  -- a picker closed while its finder still runs fails in the finder's next step
  for _, p in ipairs(Snacks.picker.get()) do
    wait_until(function() return not p:is_active() end, 2000)
    pcall(function() p:close() end)
  end
  pcall(function() require("trouble").close() end)
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then pcall(vim.api.nvim_win_close, w, true) end
  end
  flush()
  vim.cmd("silent! only")
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  vim.cmd("stopinsert")
  if vim.api.nvim_get_current_buf() ~= buf then vim.cmd.buffer(buf) end
end
-- press lhs in buf: whether it opened a window (the diagnostics list or picker)
local function opens(buf, lhs, acts)
  close_all(buf)
  local lines, wins = vim.api.nvim_buf_get_lines(buf, 0, -1, false), windows()
  feed(lhs)
  local opened = wait_until(function() return windows() > wins end, acts and 3000 or 0)
  if not acts then
    flush()
    opened = windows() > wins
  end
  close_all(buf)
  -- a press that falls back to Vim's own keys may have edited the text
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  return opened
end

-- each key is listed by which-key, and opens its list when pressed, iff want
local function judge(label, buf, want)
  for _, lhs in ipairs(KEYS) do
    local listed = wk_lists(buf, "n", lhs) ~= nil
    expect(listed == want, "[%s] %s %s, want %s", label, lhs, listed and "listed" or "not listed", want and "listed" or "not listed")
    local opened = opens(buf, lhs, want)
    expect(opened == want, "[%s] %s %s, want %s", label, lhs, opened and "opens a window" or "opens nothing", want and "a window" or "nothing")
  end
end

local ns = vim.api.nvim_create_namespace("nvr.diag")
local function diagnose(buf) vim.diagnostic.set(ns, buf, { { lnum = 0, col = 0, message = "x", severity = vim.diagnostic.severity.WARN } }) end

section("a diagnostic in the buffer")
local bn = buf_of("sbxnone")
vim.api.nvim_buf_set_lines(bn, 0, -1, false, { "one", "two" })
judge("no diagnostics", bn, false)
diagnose(bn)
judge("a diagnostic", bn, true)
vim.diagnostic.reset(ns, bn)
judge("after the reset", bn, false)

section("what could produce diagnostics is not enough")
local c1 = start_fake(bn, "fake-nothing")
judge("an attached client with no diagnostics", bn, false)
stop(c1)
declare("sbxlint", { "a_linter_that_is_not_installed" })
judge("a linted filetype with no diagnostics", buf_of("sbxlint"), false)

section("another buffer's diagnostics do not count")
local other = buf_of("sbxnone")
diagnose(other)
local here = buf_of("sbxnone")
judge("a diagnostic in another buffer only", here, false)
diagnose(here)
judge("and one here", here, true)
vim.diagnostic.reset(ns)
done()
