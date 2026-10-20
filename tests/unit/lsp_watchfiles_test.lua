-- Neovim's watched files as lsp/watchfiles.lua changes them, through the real vim.lsp: a fake server registers
-- watched files, and a fake inotifywait, first on PATH, stands in for the one Neovim's watcher runs on Linux
-- ($VIMRUNTIME/lua/vim/_watch.lua, inotify). It prints a case's lines on stderr, then a change to app.py on stdout,
-- and runs until it's stopped, as inotifywait --monitor does. What the user sees is what reaches vim.notify. Linux
-- only:
-- nvim --clean --headless -l tests/unit/lsp_watchfiles_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local server = require("fake_server")

-- Before vim.lsp._watchfiles loads: it picks the inotifywait backend when inotifywait is executable
local bin = h.tmpdir()
local stderr = bin .. "/stderr"
h.write(bin .. "/inotifywait", {
  "#!/bin/sh",
  "for root; do :; done", -- the watched root is the last argument
  ("cat '%s' >&2"):format(stderr),
  'printf "%s/ CREATE app.py\\n" "$root"',
  "exec sleep 60",
}, true)
vim.env.PATH = bin .. ":" .. vim.env.PATH
require("lsp.watchfiles").setup()

local notes = {} ---@type { msg: string, level: integer? }[]
vim.notify = function(msg, level) table.insert(notes, { msg = msg, level = level }) end

local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    vim.wait(1000, function() return ran end, 5)
  end
end

--- A server on a new root registers watched files; the fake inotifywait prints lines(root) on stderr for it. Returns
--- what reached vim.notify once the server has heard of the change reported after them, and that change's URIs.
---@param lines fun(root: string): string[]
---@return { msg: string, level: integer? }[] notes, string[] uris
local function watch(lines)
  local root = h.tmpdir()
  vim.fn.writefile(lines(root), stderr)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, root .. "/app.py")
  local srv = server.start({
    buf = buf,
    root_dir = root,
    client_capabilities = { workspace = { didChangeWatchedFiles = { dynamicRegistration = true } } },
  })
  local from = #notes
  srv.register({
    { id = "py", method = "workspace/didChangeWatchedFiles", registerOptions = { watchers = { { globPattern = "**/*.py" } } } },
  })
  local function heard()
    return vim.iter(srv.notifications):find(function(n) return n.method == "workspace/didChangeWatchedFiles" end)
  end
  -- Neovim sends a change 100 ms after its watcher reports it ($VIMRUNTIME/lua/vim/lsp/_watchfiles.lua,
  -- queue_change): by then the stderr written before it was read, and the notify it scheduled runs in the flush
  vim.wait(5000, heard, 5)
  flush()
  local changed = heard()
  srv.stop()
  vim.api.nvim_buf_delete(buf, { force = true })
  local uris = changed and vim.tbl_map(function(c) return c.uri end, changed.params.changes) or {}
  return vim.list_slice(notes, from + 1), uris
end

--- inotifywait's report of a directory created under the root and gone before it could watch it
--- (inotify-tools src/inotifywait.cpp, "Couldn't watch new directory")
local function vanished(root, name) return ("Couldn't watch new directory %s/%s/: No such file or directory"):format(root, name) end

for _, c in ipairs({
  { "one directory", function(root) return { vanished(root, "targetZ1UeUc") } end },
  { "two directories in one report", function(root) return { vanished(root, "target9JkyqT"), vanished(root, "targettz38ZE") } end },
}) do
  h.case("a directory gone before inotifywait watched it is no error, and changes still arrive: " .. c[1], function()
    local got, uris = watch(c[2])
    h.eq(#uris, 1, "changes the server heard of (precondition: the fake inotifywait ran)")
    h.ok(uris[1]:match("/app%.py$"), "the change is app.py's, got " .. tostring(uris[1]))
    h.eq(got, {}, "notifications")
  end)
end

-- Not the race above: inotifywait misses what happens in that directory, or watches nothing
for _, c in ipairs({
  { "a new directory it may not read", function(root) return ("Couldn't watch new directory %s/locked/: Permission denied"):format(root) end },
  { "a root that's gone", function(root) return ("Couldn't watch %s: No such file or directory"):format(root) end },
}) do
  h.case("any other inotifywait error is still one, in the same report as a vanished directory: " .. c[1], function()
    local err
    local got = watch(function(root)
      err = c[2](root)
      return { vanished(root, "targetaTF4aP"), err }
    end)
    h.eq(#got, 1, "notifications: " .. vim.inspect(got))
    h.eq(got[1].level, vim.log.levels.ERROR, "its level")
    h.ok(got[1].msg:find(err, 1, true), "it has the error, got " .. got[1].msg)
    h.ok(not got[1].msg:find("targetaTF4aP", 1, true), "it leaves out the vanished directory, got " .. got[1].msg)
  end)
end

h.finish()
