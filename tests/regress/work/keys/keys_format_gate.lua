-- @desc     the format keys (<leader>lf in normal and visual mode, the <leader>Tf toggle) are listed by which-key and act in a buffer iff conform has a formatter configured for its filetype (list, function or a dot-part of the filetype) or an attached client formats, and there <leader>lf runs the formatter
-- @areas    keys format lsp which-key
-- @budget   20
-- Judged by pressing the keys and reading which-key's popup, never by which maps exist. Controlled
-- conform.formatters_by_ft entries and in-process fake servers that record their requests.

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

local function caps_for(methods)
  local caps = {}
  for _, m in ipairs(methods) do
    local path = assert(vim.lsp.protocol._request_name_to_server_capability[m], "no capability path for " .. m)
    local t = caps
    for i = 1, #path - 1 do
      t[path[i]] = t[path[i]] or {}
      t = t[path[i]]
    end
    t[path[#path]] = true
  end
  return caps
end
local servers = {}
local requests = {} -- method -> times any fake server got it
-- an in-process server advertising exactly `methods`, attached to buf; it records every request and edits nothing
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
        local result = {}
        if method == "initialize" then
          result = { capabilities = caps_for(methods) }
        elseif method == "shutdown" then
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

local DIR = FIX .. "/.nvr-fmt"
vim.fn.mkdir(DIR, "p")
local LINES = { "alpha", "beta" }
local nbuf = 0
local function buf_of(ft)
  nbuf = nbuf + 1
  vim.cmd.edit(("%s/f%d.txt"):format(DIR, nbuf))
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  vim.bo[buf].filetype = ft
  flush()
  return buf
end

local conform = require("conform")
-- a formatter that works: it upper-cases the text
conform.formatters.nvr_upper = { command = "tr", args = { "a-z", "A-Z" } }
local NORMAL, VISUAL, TOGGLE = { "<leader>lf", "n" }, { "<leader>lf", "x" }, { "<leader>Tf", "n" }
local KEYS = { NORMAL, VISUAL, TOGGLE }
local function notifications() return #Snacks.notifier.get_history() end
local function text(buf) return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") end

-- press key in buf over its whole text; what it did: a formatting request, a notification, the text changed,
-- the toggle's which-key label flipped
local function press(buf, key, acts)
  vim.cmd.buffer(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local asked = (requests["textDocument/formatting"] or 0) + (requests["textDocument/rangeFormatting"] or 0)
  local said, label = notifications(), wk_lists(buf, "n", TOGGLE[1])
  feed((key[2] == "x" and "VG" or "") .. key[1])
  if vim.fn.mode() ~= "n" then vim.cmd("normal! \27") end
  local function now()
    return {
      asked = (requests["textDocument/formatting"] or 0) + (requests["textDocument/rangeFormatting"] or 0) > asked,
      said = notifications() > said,
      changed = text(buf) ~= table.concat(LINES, "\n"),
      flipped = key == TOGGLE and wk_lists(buf, "n", TOGGLE[1]) ~= label,
    }
  end
  local r
  wait_until(function()
    r = now()
    return r.asked or r.said or r.changed or r.flipped
  end, acts and 3000 or 0)
  if not acts then
    flush()
    r = now()
  end
  r.acted = r.asked or r.changed or r.flipped or (acts and r.said)
  -- an LSP format reports when it is done; changing the text before then discards its edits with an error
  if r.asked then wait_until(function() return notifications() > said end, 3000) end
  -- the toggle back as it was
  if r.flipped then feed(TOGGLE[1]) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  vim.bo[buf].modified = false
  return r
end
local function show(r) return ("request %s, notification %s, text changed %s, label flipped %s"):format(tostring(r.asked), tostring(r.said), tostring(r.changed), tostring(r.flipped)) end

-- each key is listed, and acts when pressed, iff want[key] holds. Where it does not, a press makes no formatting
-- request and leaves the text alone; its message, if any, is not judged (a key with nothing to fall back to may say
-- what it needs).
local function judge(label, buf, want)
  for _, key in ipairs(KEYS) do
    local w = want == true or (type(want) == "table" and want[key] == true)
    local listed = wk_lists(buf, key[2], key[1]) ~= nil
    expect(listed == w, "[%s] %s %s %s, want %s", label, key[2], key[1], listed and "listed" or "not listed", w and "listed" or "not listed")
    local r = press(buf, key, w)
    if w then
      expect(r.acted, "[%s] %s %s acts (%s)", label, key[2], key[1], show(r))
    else
      expect(not r.acted, "[%s] %s %s does not act (%s)", label, key[2], key[1], show(r))
    end
  end
end

section("conform configuration")
expect(conform.formatters_by_ft.sbxnone == nil, "precondition: no formatter for sbxnone")
judge("unconfigured ft, no client", buf_of("sbxnone"), false)
conform.formatters_by_ft.sbxlist = { "a_tool_that_is_not_installed" }
local blist = buf_of("sbxlist")
judge("formatter configured but not installed", blist, true)
conform.formatters_by_ft.sbxfn = function() return {} end
judge("formatter function that finds nothing yet", buf_of("sbxfn"), true)
judge("compound ft with a configured part", buf_of("sbxother.sbxlist"), true)
conform.formatters_by_ft.sbxlist = nil
vim.bo[blist].filetype = "sbxlist"
flush()
judge("config removed, FileType again", blist, false)

section("formatting clients")
local bl = buf_of("sbxnone")
local c1 = start_fake(bl, "fake-fmt", { "textDocument/formatting" })
judge("client formats", bl, { [NORMAL] = true, [TOGGLE] = true })
stop(c1)
judge("formatting client stopped", bl, false)
local c2 = start_fake(bl, "fake-range", { "textDocument/formatting", "textDocument/rangeFormatting" })
judge("client formats ranges", bl, true)
stop(c2)
local bd = buf_of("sbxnone")
local c3 = start_fake(bd, "fake-late", {})
judge("late client before registering", bd, false)
server_request(c3, "client/registerCapability", { registrations = { { id = "f", method = "textDocument/formatting" } } })
judge("late client registered formatting", bd, { [NORMAL] = true, [TOGGLE] = true })
stop(c3)
judge("late client stopped", bd, false)

section("configured filetype with a client")
conform.formatters_by_ft.sbxboth = { "a_tool_that_is_not_installed" }
local bb = buf_of("sbxboth")
local c4 = start_fake(bb, "fake-both", { "textDocument/formatting", "textDocument/rangeFormatting" })
judge("configured and formatting client", bb, true)
stop(c4)
judge("configured, client stopped", bb, true)

section("<leader>lf runs the formatter")
conform.formatters_by_ft.sbxup = { "nvr_upper" }
local bu = buf_of("sbxup")
vim.cmd.buffer(bu)
vim.api.nvim_buf_set_lines(bu, 0, -1, false, LINES)
feed(NORMAL[1])
expect(wait_until(function() return text(bu) == "ALPHA\nBETA" end, 5000), "the buffer is formatted (now %q)", text(bu))
done()
