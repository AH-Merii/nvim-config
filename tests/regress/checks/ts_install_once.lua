-- @desc     with a UI, a parser that is available but not installed is installed once a session: not again for each buffer after a failed build, and every buffer opened while it installs attaches when it lands
-- @areas    treesitter
-- @budget   15
-- @needs    tree-sitter
local ts = require("nvim-treesitter")
-- installs need a UI (D120); headless, this stands in for one
vim.api.nvim_list_uis = function() return { {} } end
local installed = ts.get_installed()
-- two available languages without a parser, each with a filetype of its own
local probes = {}
for _, l in ipairs(ts.get_available()) do
  if not vim.list_contains(installed, l) and not vim.treesitter.language.add(l) then
    for _, f in ipairs(vim.treesitter.language.get_filetypes(l)) do
      if vim.treesitter.language.get_lang(f) == l then table.insert(probes, { l, f }) break end
    end
  end
  if #probes == 2 then break end
end
if not check("found two available parsers that are not installed", #probes == 2, #probes) then return end
local lang, ft = probes[1][1], probes[1][2]
info("probe languages " .. probes[1][1] .. " and " .. probes[2][1])

-- a stand-in for a build that fails, e.g. without the tree-sitter CLI
local calls = 0
ts.install = function(langs)
  if langs == lang or (type(langs) == "table" and vim.list_contains(langs, lang)) then calls = calls + 1 end
  return { await = function(_, cb) cb("nvr: install failed") end }
end
-- the failure's error toast is this check's own doing: caught here, so it doesn't count as an error of the config's
local notify, errors = vim.notify, {}
vim.notify = function(msg, level) if level == vim.log.levels.ERROR then table.insert(errors, msg) end end
for _ = 1, 3 do
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.bo.filetype = ft
end
wait_until(function() return #errors > 0 end, 3000)
vim.notify = notify
check("the missing parser is installed on first use", calls >= 1, calls)
check("a failed install is not retried for the next buffers", calls == 1, calls .. " installs for 3 buffers")
check("a failed install says so", #errors == 1 and errors[1]:find("Couldn't install " .. lang, 1, true) ~= nil, vim.inspect(errors))

-- an install still running when more buffers of its filetype open: each of them attaches once it lands
local lang2, ft2 = probes[2][1], probes[2][2]
local calls2, pending = 0, {}
ts.install = function(langs)
  if langs == lang2 or (type(langs) == "table" and vim.list_contains(langs, lang2)) then calls2 = calls2 + 1 end
  return { await = function(_, cb) table.insert(pending, cb) end }
end
local bufs = {}
for i = 1, 2 do
  vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
  vim.bo.filetype = ft2
  bufs[i] = vim.api.nvim_get_current_buf()
end
check("one install for buffers opened while it runs", calls2 == 1, calls2)
-- it lands: the lua grammar under the probe's name, with a highlights query of its own
local lua_so = vim.api.nvim_get_runtime_file("parser/lua.so", false)[1]
vim.treesitter.language.add(lang2, { path = lua_so, symbol_name = "lua" })
vim.treesitter.query.set(lang2, "highlights", "(identifier) @variable")
for _, cb in ipairs(pending) do cb(nil, true) end
local function active(b) return vim.treesitter.highlighter.active[b] ~= nil end
check("every buffer opened while the install ran attaches when it lands", wait_until(function() return active(bufs[1]) and active(bufs[2]) end, 3000),
  tostring(active(bufs[1])) .. " " .. tostring(active(bufs[2])))
