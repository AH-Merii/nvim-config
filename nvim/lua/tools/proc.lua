-- Runs a process off the main loop: the resolver's --version and rustup checks, and the backends' commands.

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

return M
