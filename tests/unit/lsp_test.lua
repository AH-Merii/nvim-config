-- The sweep of a server's process group (tools.proc's groups(), through lsp/init.lua's _groups and _sweep): it kills
-- the group it recorded, and leaves alone a group whose leader's pid now runs with another start time, a reused id.
-- Real processes stand in for a server: a detached sleep leads its own group, as vim.lsp.rpc.start's servers do. Linux
-- only (/proc):
-- nvim --clean --headless -l tests/unit/lsp_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local lsp = require("lsp")

--- A detached sleep: the leader of its own process group.
local function leader()
  local obj = vim.system({ "sleep", "60" }, { detach = true })
  return obj, obj.pid
end
local function alive(pid)
  local f = io.open(("/proc/%d/stat"):format(pid))
  if not f then return false end
  local stat = f:read("*a") or ""
  f:close()
  return stat:match("%) (%a)") ~= "Z"
end
--- The start time proc(5) gives as field 22 of /proc/<pid>/stat, read by awk (sleep's command name has no spaces)
local function start_time(pid) return vim.trim(vim.system({ "awk", "{ print $22 }", ("/proc/%d/stat"):format(pid) }):wait().stdout) end

h.case("a group whose leader runs with the recorded start time is killed", function()
  local obj, pid = leader()
  local start = start_time(pid)
  h.ok(start:match("^%d+$"), "precondition: a start time for the sleep, got " .. start)
  lsp._groups[pid] = start
  lsp._sweep(pid)
  -- SystemObj:wait(timeout) kills the process itself on a timeout, so the sleep is watched instead
  local gone = vim.wait(2000, function() return not alive(pid) end, 10)
  obj:kill("sigkill")
  h.ok(gone, "the sleep still runs")
end)

h.case("a group whose leader's pid runs with another start time is left alone", function()
  local obj, pid = leader()
  local start = start_time(pid)
  h.ok(start:match("^%d+$"), "precondition: a start time for the sleep, got " .. start)
  -- recorded for an earlier process given the same pid
  lsp._groups[pid] = tostring(tonumber(start) - 1)
  lsp._sweep(pid)
  vim.wait(200)
  h.ok(alive(pid), "the sleep was killed")
  obj:kill("sigkill")
  obj:wait(2000)
end)

h.finish()
