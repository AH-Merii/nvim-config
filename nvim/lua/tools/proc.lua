-- Runs a process off the main loop: the resolver's --version and rustup checks, and the backends' commands. And keeps
-- the process groups of the tools the config starts detached (servers, linters), to kill what is left of them later.

local M = {}

---@class tools.Run
---@field code integer
---@field stdout string
---@field stderr string

--- Runs cmd and calls back with its result on the main loop; a missing executable is code -1.
---@param cmd string[]
---@param opts? { cwd?: string, env?: table<string, string>, timeout?: integer }
---@param on_exit fun(result: tools.Run)
function M.run(cmd, opts, on_exit)
  opts = opts or {}
  local done = vim.schedule_wrap(function(out) on_exit({ code = out.code, stdout = out.stdout or "", stderr = out.stderr or "" }) end)
  local ok, err = pcall(vim.system, cmd, { cwd = opts.cwd, env = opts.env, timeout = opts.timeout, text = true, stdin = false }, done)
  if not ok then
    vim.schedule(function() on_exit({ code = -1, stdout = "", stderr = tostring(err) }) end)
  end
end

--- Runs an install command: ok when it exits 0, else the command and its error output.
---@param cmd string[]
---@param opts { cwd?: string, env?: table<string, string> }
---@param cb fun(ok: boolean, err?: string)
function M.install(cmd, opts, cb)
  M.run(cmd, opts, function(out)
    if out.code ~= 0 then
      return cb(false, ("%s: %s"):format(table.concat(cmd, " "), vim.trim(out.stderr ~= "" and out.stderr or out.stdout)))
    end
    cb(true)
  end)
end

--- A process's start time, field 22 of /proc/<pid>/stat; nil without one (no procfs, or no such process).
---@param pid integer
---@return string?
local function started(pid)
  local f = io.open(("/proc/%d/stat"):format(pid))
  if not f then
    return nil
  end
  local stat = f:read("*a") or ""
  f:close()
  -- After the command name, in parentheses and maybe with spaces, the fields from the third on
  return vim.split(stat:match(".*%) (.*)") or "", " ")[20]
end

---@class tools.Groups
---@field leaders table<integer, string> each group's leader pid -> the leader's start time
local Groups = {}
Groups.__index = Groups

--- A set of process groups, each led by a process started detached: its pid is also the id of the group its children
--- are born in. The leader's start time tells the group from a later one given the same id.
---@return tools.Groups
function M.groups() return setmetatable({ leaders = {} }, Groups) end

--- Records the group that pid, a process just started detached, leads.
---@param pid integer
function Groups:add(pid) self.leaders[pid] = started(pid) end

--- Forgets the group pid leads, leaving it running.
---@param pid integer
function Groups:forget(pid) self.leaders[pid] = nil end

--- Kills (SIGKILL) what is left of the group pid leads: the children it didn't stop, and the leader if it still runs.
--- Skipped when the id names another group: one whose processes are all gone frees it, and a new process with that pid
--- can lead a group of its own. Callable in a fast event.
---@param pid integer
function Groups:kill(pid)
  local start = self.leaders[pid]
  self.leaders[pid] = nil
  local now = start and started(pid)
  if start and (now == nil or now == start) then
    vim.uv.kill(-pid, "sigkill")
  end
end

--- Kills what is left of every group recorded.
function Groups:kill_all()
  for pid in pairs(self.leaders) do
    self:kill(pid)
  end
end

return M
