-- @desc     a :Tools tool menu acts only on that tool: a found server binary offers its server, a missing one an install and no restart, neither re-resolves every tool; a tool without a server opens no menu and says where it comes from
-- @areas    tools ui lsp
-- @budget   25
-- @needs    lua-language-server stylua
-- The pickers are stubbed: the :Tools list picks the tool under test and the actions picker is recorded and dismissed.
-- Which tools are missing depends on the suite's mise: lua-language-server is there, tinymist is not (no check needs it).
local tools = require("tools")
vim.g.install_tools = "off"

--- The actions :Tools offers for bin in path's buffer.
local function actions(path, lines, bin)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  vim.cmd.edit(path)
  local result = tools.wait(bin, tools.root(0), 10000)
  local offered
  local select = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    local texts = vim.tbl_map(function(i) return opts.format_item and opts.format_item(i) or i end, items)
    if opts.kind == "tools" then
      for i, text in ipairs(texts) do
        if text:find(bin, 1, true) then
          return on_choice(items[i], i)
        end
      end
      return on_choice(nil, nil)
    end
    offered = texts
    on_choice(nil, nil)
  end
  local notify = vim.notify
  local said
  vim.notify = function(msg, ...)
    if type(msg) == "string" and vim.startswith(msg, bin) then
      said = msg
    end
    return notify(msg, ...)
  end
  vim.cmd("Tools")
  wait_until(function() return offered ~= nil or said ~= nil end, 10000)
  vim.ui.select, vim.notify = select, notify
  return offered or {}, result, said
end
local function has(texts, pattern) return vim.iter(texts):any(function(t) return t:find(pattern) ~= nil end) end
-- Re-resolving every tool of the folder is the main list's job, not one tool's
local function rescans(texts) return has(texts, "^Retry") or has(texts, "[Rr]escan") or has(texts, "[Rr]esolve") end

local offered, result = actions(FIX .. "/doc/main.typ", { "= Title" }, "tinymist")
if check("tinymist is missing in the suite", result ~= nil and result.path == nil, result and result.source) then
  check("a missing server binary is not offered a start or restart", #offered > 0 and not has(offered, "^Restart") and not has(offered, "^Start"), vim.inspect(offered))
  check("it is offered an install", has(offered, "^Install"), vim.inspect(offered))
  check("its menu does not re-resolve every tool", not rescans(offered), vim.inspect(offered))
end

offered, result = actions(FIX .. "/main.lua", { "return 1" }, "lua-language-server")
if check("lua-language-server is found in the suite", result ~= nil and result.path ~= nil, result and result.source) then
  check("a found server binary is offered a start or restart of lua_ls", has(offered, "^Restart lua_ls") or has(offered, "^Start lua_ls"), vim.inspect(offered))
  check("its menu does not re-resolve every tool", not rescans(offered), vim.inspect(offered))
end

local said
offered, result, said = actions(FIX .. "/main.lua", { "return 1" }, "stylua")
if check("stylua is found in the suite", result ~= nil and result.path ~= nil, result and result.source) then
  check("a found tool without a server opens no menu", #offered == 0, vim.inspect(offered))
  check("it says its full path instead", said ~= nil and said:find(vim.fn.fnamemodify(result.path, ":~"), 1, true) ~= nil, said)
end
