-- blink.cmp's path source, plus project paths (D163). blink resolves `./` and `../` from get_cwd, which it calls with
-- the context; get_cwd stays at blink's default, the file's folder (blink.cmp/lua/blink/cmp/sources/path/init.lua:26).
-- A relative path with no `./` in front (`src/`, `docs/`) blink lists nothing for, whatever get_cwd says: it reads
-- `src/` as part of a URL (`prefix:match('%a/$')`, sources/path/lib.lua:32; get_cwd serves only `./` and `../`,
-- lib.lua:17-22). This source lists those from the project root, tools.root(buf), with blink's own items
-- (lib.candidates); everything else (absolute, `~/`, `$VAR/`, `./`, `../`) stays blink's.
local path = require("blink.cmp.sources.path")

local M = setmetatable({}, { __index = path })
M.__index = M

---@param opts blink.cmp.PathOpts
function M.new(opts) return setmetatable(path.new(opts), M) end

-- The path being completed ends at the cursor; it is cut at whitespace, quotes and brackets, as a path in prose or code
-- would be
local PATH = "[^%s\"'`(){}%[%]<>=,;]*$"

--- The folder a relative path with no `./` or `../` in front lists, and whether to list hidden files; nil for any
--- other text (blink's own cases, a URL, a word with no `/`).
---@param context blink.cmp.Context
---@return string? dir
---@return boolean? hidden
function M.project_dir(context)
  local typed = context.line:sub(1, context.cursor[2]):match(PATH)
  local dir, name = typed:match("^(.*/)([^/]*)$")
  if not dir or dir:match("^%.%.?/") or dir:match("^[/~$]") or dir:find(":", 1, true) then
    return nil
  end
  return vim.fs.joinpath(require("tools").root(context.bufnr), dir), name:sub(1, 1) == "."
end

function M:get_completions(context, callback)
  local dir, hidden = M.project_dir(context)
  if not dir then
    return path.get_completions(self, context, callback)
  end
  callback = vim.schedule_wrap(callback)
  require("blink.cmp.sources.path.lib")
    .candidates(context, dir, hidden or self.opts.show_hidden_files_by_default, self.opts)
    :map(function(items) callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = items }) end)
    -- a folder that isn't there (`and/or` in prose) lists nothing
    :catch(
      function() callback({ is_incomplete_forward = false, is_incomplete_backward = false, items = {} }) end
    )
end

return M
