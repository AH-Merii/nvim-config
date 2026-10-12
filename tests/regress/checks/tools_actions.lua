-- @desc     :Tools offers to restart a tool's servers only when its binary was found; a missing server binary gets install and retry, not restart
-- @areas    tools ui lsp
-- @budget   25
-- @needs    lua-language-server
-- The pickers are stubbed: the :Tools list picks the tool under test and the actions picker is recorded and dismissed.
-- Which tools are missing depends on the suite's mise: lua-language-server is there, docker-language-server is not.
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
  vim.cmd("Tools")
  wait_until(function() return offered ~= nil end, 10000)
  vim.ui.select = select
  return offered or {}, result
end
local function has_restart(texts) return vim.iter(texts):any(function(t) return t:find("^Restart") ~= nil end) end

local offered, result = actions(FIX .. "/dock/Dockerfile", { "FROM scratch" }, "docker-language-server")
if check("docker-language-server is missing in the suite", result ~= nil and result.path == nil, result and result.source) then
  check("a missing server binary is not offered a restart", #offered > 0 and not has_restart(offered), vim.inspect(offered))
  check("it is offered a retry", vim.iter(offered):any(function(t) return t:find("^Retry") ~= nil end), vim.inspect(offered))
end

offered, result = actions(FIX .. "/main.lua", { "return 1" }, "lua-language-server")
if check("lua-language-server is found in the suite", result ~= nil and result.path ~= nil, result and result.source) then
  check("a found server binary is offered a restart of its server", has_restart(offered), vim.inspect(offered))
end
