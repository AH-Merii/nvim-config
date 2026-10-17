-- @desc     the statusline draws the shown buffer's facts (the last file buffer while the current one isn't a file): its servers, the formatters and linters that will run, and the count of missing tools; it redraws on its own when they change
-- @areas    ui tools
-- @budget   30
-- @needs    ruff pyrefly
local facts = require("ui.facts")
vim.g.install_tools = "off"
vim.api.nvim_list_uis = function() return { { width = 120, height = 40 } } end -- the tools indicator shows only with a UI

-- No refresh is forced here: the line must follow the facts by itself
local function statusline()
  return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = vim.api.nvim_get_current_win(), maxwidth = 400 }).str
end
--- The texts the line must hold for f: each non-empty list, joined as the segments join them, and the missing count.
local function drawn(f)
  local want = { "LSP: " .. (#f.servers > 0 and table.concat(f.servers, ", ") or "No Active LSP") }
  for _, list in ipairs({ f.formatters, f.linters }) do
    if #list > 0 then
      table.insert(want, table.concat(list, ", "))
    end
  end
  if #f.missing > 0 then
    table.insert(want, "󰖷 " .. #f.missing)
  end
  return want
end
local function shows(f)
  local line = statusline()
  -- each text whole, between the spaces that pad a segment, so "LSP: pyrefly" is not found in "LSP: pyrefly, ruff"
  return vim.iter(drawn(f)):all(function(text) return line:find(" " .. text .. " ", 1, true) ~= nil end)
end

vim.fn.mkdir(FIX .. "/py", "p")
vim.fn.writefile({ "x = 1" }, FIX .. "/py/a.py")
vim.cmd.edit(FIX .. "/py/a.py")
local buf = vim.api.nvim_get_current_buf()
local missing = wait_attach(buf, { "ruff", "pyrefly" }, 20000)
check("ruff and pyrefly attach", #missing == 0, table.concat(missing, ", "))
wait_until(function() return #facts.get(buf).formatters > 0 and shows(facts.get(buf)) end, 10000)
local f = facts.get(buf)
check("the facts have servers and formatters to draw", #f.servers > 0 and #f.formatters > 0, vim.inspect(f))
check("the line draws them", shows(f), vim.inspect({ want = drawn(f), line = statusline() }))

-- A window on a buffer that isn't a file (a picker, a terminal) keeps the file's lists
vim.cmd("new | setlocal buftype=nofile")
wait_until(function() return statusline():find("No Active LSP", 1, true) ~= nil end, 300)
check("a non-file buffer shows the last file buffer's facts", shows(f), vim.inspect({ want = drawn(f), line = statusline() }))
vim.cmd.close()

-- A change: ruff detaches, so its server goes and ruff's linting, which it covered, comes back. Only FactsChanged may
-- redraw the line: lualine's 1 s timer is stopped, and the detach's DiagnosticChanged and the servers' progress
-- messages are ignored
local timers = 0
vim.uv.walk(function(handle)
  if handle:get_type() == "timer" and handle:get_repeat() == 1000 then
    handle:stop()
    timers = timers + 1
  end
end)
check("set up: lualine's 1 s timer is stopped", timers == 1, timers)
vim.o.eventignore = "DiagnosticChanged,Progress"
vim.lsp.buf_detach_client(buf, vim.lsp.get_clients({ bufnr = buf, name = "ruff" })[1].id)
wait_until(function() return not vim.list_contains(facts.get(buf).servers, "ruff") end, 5000)
f = facts.get(buf)
check("the facts lose the detached server", not vim.list_contains(f.servers, "ruff"), vim.inspect(f.servers))
check("the line follows on FactsChanged", wait_until(function() return shows(facts.get(buf)) end, 2000),
  vim.inspect({ want = drawn(facts.get(buf)), line = statusline() }))
vim.o.eventignore = ""

-- Missing tools: the Dockerfile's are not in the suite
vim.fn.mkdir(FIX .. "/dock", "p")
vim.fn.writefile({ "FROM scratch" }, FIX .. "/dock/Dockerfile")
vim.cmd.edit(FIX .. "/dock/Dockerfile")
local dock = vim.api.nvim_get_current_buf()
wait_until(function() return #facts.get(dock).missing > 0 and shows(facts.get(dock)) end, 10000)
f = facts.get(dock)
check("the Dockerfile has missing tools in the suite", #f.missing > 0, vim.inspect(f))
check("the line draws their count", shows(f), vim.inspect({ want = drawn(f), line = statusline() }))
