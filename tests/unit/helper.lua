-- Cases, assertions and throwaway files for the unit tests. A test file requires it after putting tests/unit on
-- package.path, runs its cases with case(), and ends with finish(), which raises when any case failed.

local M = {}

local passed, failed = 0, {} ---@type integer, string[]

--- Runs fn as one case now; a failure is recorded and printed, and the next case still runs.
---@param name string what the case checks
---@param fn fun()
function M.case(name, fn)
  -- The error and where the test files were in its traceback; the frames in Neovim and in helpers are noise
  local ok, err = xpcall(fn, function(e)
    local frames = vim.iter(vim.split(debug.traceback("", 2), "\n")):filter(function(l) return l:find("_test%.lua:%d+:") end)
    return table.concat(vim.list_extend({ tostring(e) }, frames:map(vim.trim):totable()), "\n")
  end)
  if ok then
    passed = passed + 1
  else
    table.insert(failed, name)
    io.stderr:write(("FAIL %s\n  %s\n"):format(name, tostring(err):gsub("\n", "\n  ")))
  end
end

--- Raises unless got equals want (deep comparison); what names the value in the message.
---@param got any
---@param want any
---@param what? string
function M.eq(got, want, what)
  if not vim.deep_equal(got, want) then
    error(("%s\n    want: %s\n     got: %s"):format(what or "values differ", vim.inspect(want), vim.inspect(got)), 2)
  end
end

--- Raises with msg unless cond holds.
---@param cond any
---@param msg string
function M.ok(cond, msg)
  if not cond then
    error(msg, 2)
  end
end

--- Starts fn with a callback and waits (running the event loop) until it is called; returns what it was called with.
---@param fn fun(done: fun(...))
---@param timeout? integer ms, default 5000
---@return any ...
function M.await(fn, timeout)
  local got ---@type table?
  fn(function(...) got = got or vim.F.pack_len(...) end)
  if not vim.wait(timeout or 5000, function() return got ~= nil end, 5) then
    error("timed out waiting for a callback", 2)
  end
  return vim.F.unpack_len(got)
end

--- A new empty dir under Neovim's temp dir, which Neovim deletes on exit.
---@return string
function M.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return vim.fs.normalize(vim.uv.fs_realpath(dir) or dir)
end

--- Writes lines to path, making its dirs; exec makes it executable.
---@param path string
---@param lines string[]
---@param exec? boolean
---@return string path
function M.write(path, lines, exec)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  if exec then
    vim.uv.fs_chmod(path, tonumber("755", 8))
  end
  return path
end

--- Writes an executable at path whose `--version` prints "<name> <version>".
---@param path string
---@param version string
---@return string path
function M.bin(path, version) return M.write(path, { "#!/bin/sh", ("echo '%s %s'"):format(vim.fs.basename(path), version) }, true) end

--- Prints the count and raises when any case failed, so the run exits non-zero.
function M.finish()
  if #failed + passed == 0 then
    error("no cases ran", 0)
  elseif #failed > 0 then
    error(("%d of %d cases failed: %s"):format(#failed, #failed + passed, table.concat(failed, "; ")), 0)
  end
  print(("%d cases passed"):format(passed))
end

return M
