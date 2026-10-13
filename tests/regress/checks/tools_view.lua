-- @desc     :Tools rows name each tool's roles in plain words and where it comes from with its version, never an install path or a command; the picker is wide enough for its longest row; the mise.toml row says what picking it does and is hidden for a config that pins nothing; the last row rescans
-- @areas    tools ui
-- @budget   30
-- @needs    lua-language-server stylua ruff
-- The pickers are stubbed: each :Tools list is recorded with the width it asked for, then dismissed.
local tools = require("tools")
vim.g.install_tools = "off"
vim.o.columns = 200

local function put(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
--- The :Tools list for path: its rows and the width it asked for.
local function list(path, lines)
  put(path, lines)
  vim.cmd.edit(path)
  local got
  local select = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    local layout = ((opts.snacks or {}).layout or {}).layout or {}
    got = { prompt = opts.prompt, width = layout.width, rows = vim.tbl_map(opts.format_item, items) }
    on_choice(nil, nil)
  end
  vim.cmd("Tools")
  wait_until(function() return got ~= nil end, 15000)
  vim.ui.select = select
  return got or { rows = {} }
end
local function row(view, name) return vim.iter(view.rows):find(function(r) return r:find(" " .. name .. " ", 1, true) ~= nil end) end
--- The version the binary itself reports, to compare the row against
local function reported(bin, root)
  local r = tools.wait(bin, root, 10000)
  local out = r and r.path and vim.system({ r.path, "--version" }, { text = true, env = r.env }):wait(10000).stdout or ""
  return out:match("%d+%.%d+%.%d+")
end

local view = list(FIX .. "/lua/main.lua", { "return 1" })
local lsp, fmt = row(view, "lua-language-server"), row(view, "stylua")
local lsp_version, fmt_version = reported("lua-language-server", FIX .. "/lua"), reported("stylua", FIX .. "/lua")
check("the server row says lsp and global mise with its version", lsp and lsp_version and lsp:find("lsp", 1, true)
  and lsp:find("global mise · " .. lsp_version, 1, true), vim.inspect({ lsp, lsp_version }))
check("the formatter row says formatter and global mise with its version", fmt and fmt_version and fmt:find("formatter", 1, true)
  and fmt:find("global mise · " .. fmt_version, 1, true), vim.inspect({ fmt, fmt_version }))
check("no row shows a path or a command", #view.rows > 0 and not vim.iter(view.rows):any(function(r)
  return r:find("/", 1, true) ~= nil or r:find("mise use", 1, true) ~= nil
end), vim.inspect(view.rows))
check("the last row rescans the tool sources", view.rows[#view.rows] == "Rescan tool sources", vim.inspect(view.rows))
local longest = 0
for _, r in ipairs({ view.prompt, unpack(view.rows) }) do
  longest = math.max(longest, vim.fn.strdisplaywidth(r))
end
check("the picker asks for a width that fits its longest row and title", view.width and view.width > longest and view.width <= vim.o.columns,
  vim.inspect({ width = view.width, longest = longest }))

-- A project whose mise.toml pins ruff: the row offers to use it, naming the pin, and to stop once it is used
local version = reported("ruff", FIX)
put(FIX .. "/py/mise.toml", { "[tools]", ('ruff = "%s"'):format(version) })
view = list(FIX .. "/py/a.py", { "x = 1" })
local use = vim.iter(view.rows):find(function(r) return vim.startswith(r, "Use mise.toml") end)
check("an unused config's row offers to use it, names its pin and says it trusts it", use and use:find("ruff " .. version, 1, true)
  and use:find("trusts it", 1, true), vim.inspect(view.rows))
local done
tools.set_choice(FIX .. "/py", "installed", function() done = true end)
wait_until(function() return done end, 10000)
view = list(FIX .. "/py/b.py", { "x = 2" })
check("with only installed versions in use, the row still offers to use it", vim.iter(view.rows):any(function(r) return vim.startswith(r, "Use mise.toml") end),
  vim.inspect(view.rows))
check("ruff's row then says project mise", (row(view, "ruff") or ""):find("project mise · " .. version, 1, true) ~= nil, vim.inspect(view.rows))
-- the "use" answer, stored the way the prompt stores it; installs are off, so nothing is trusted or installed
require("tools.state").set(tools.project(FIX .. "/py").configs, "use")
tools.refresh()
view = list(FIX .. "/py/c.py", { "x = 3" })
check("a config in use: the row offers to stop using it", vim.iter(view.rows):any(function(r) return vim.startswith(r, "Stop using mise.toml (ruff") end),
  vim.inspect(view.rows))

put(FIX .. "/none/mise.toml", { "[tools]" })
view = list(FIX .. "/none/a.py", { "x = 1" })
check("a config that pins nothing has no row", #view.rows > 1 and not vim.iter(view.rows):any(function(r) return r:find("mise.toml", 1, true) ~= nil end),
  vim.inspect(view.rows))
