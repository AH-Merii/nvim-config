-- The keys module through its interface (require("keys")): rows pressed with real keys, needs read live from fake
-- servers and test words, keys.menu, keys.holds and keys.list. No plugins: nvim --clean --headless -l tests/unit/keys_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local server = require("fake_server")

vim.g.mapleader = " "
local keys = require("keys")

-- every notification, newest last
local said = {} ---@type string[]
vim.notify = function(msg) table.insert(said, msg) end

local function press(lhs) vim.api.nvim_feedkeys(vim.keycode(lhs), "mx", false) end

local LINES = { "local x = 1", "", "print(x)" }
local n = 0
--- A fresh buffer with LINES, current, cursor on the x of line 3; ft sets its filetype.
---@param ft? string
local function scratch(ft)
  n = n + 1
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, ("%s/scratch%d.txt"):format(h.tmpdir(), n))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, LINES)
  if ft then
    vim.bo[buf].filetype = ft
  end
  vim.api.nvim_win_set_cursor(0, { 3, 6 })
  return buf
end
local function cursor() return vim.api.nvim_win_get_cursor(0) end
local function text(buf) return vim.api.nvim_buf_get_lines(buf, 0, -1, false) end

--- The menu's items by lhs.
local function menu(buf, mode)
  local out = {}
  for _, item in ipairs(keys.menu(buf, mode)) do
    out[item.lhs] = item
  end
  return out
end

local ran = {} ---@type table<string, integer>
local function counter(name)
  return function() ran[name] = (ran[name] or 0) + 1 end
end

local lsp = keys.feature("lsp")
lsp({ "gd", counter("gd"), "Definition", need = "definition" })
lsp({ "grn", counter("grn"), "Rename", need = "rename", echo = true })
lsp({ "K", counter("K"), "Hover", need = "textDocument/hover" })
lsp({ "<leader>sS", counter("symbols"), "Workspace symbols", need = "workspace/symbol" })

h.case("with no server a non-leader key does Vim's own key and is not listed", function()
  local buf = scratch()
  press("gd")
  h.eq(cursor(), { 1, 6 }, "Vim's gd: the local declaration")
  h.eq(ran.gd, nil, "the row's action")
  h.eq(menu(buf).gd, nil, "gd in the menu")
  h.eq(keys.holds("definition", buf), false, "holds")
end)

h.case("with a server that supports the method the key runs its action and is listed", function()
  local buf = scratch()
  local srv = server.start({ buf = buf, methods = { "textDocument/definition" } })
  press("gd")
  h.eq(ran.gd, 1, "the row's action ran")
  h.eq(cursor(), { 3, 6 }, "the cursor did not move")
  h.eq(menu(buf).gd and menu(buf).gd.label, "Definition", "gd's menu label")
  h.ok(keys.holds("textDocument/definition", buf) and keys.holds("definition", buf), "holds by full and short name")
  srv.stop()
  ran.gd = nil
  press("gd")
  h.eq({ ran.gd, cursor() }, { nil, { 1, 6 } }, "after the server stopped: Vim's gd again")
  h.eq(menu(buf).gd, nil, "gd after the server stopped")
end)

h.case("a method a server registers later is listed and acts, with no event in between", function()
  local buf = scratch()
  local srv = server.start({ buf = buf, methods = {} })
  h.eq(menu(buf).grn, nil, "grn before the registration")
  srv.register({ "textDocument/rename" })
  h.ok(menu(buf).grn ~= nil, "grn listed after the registration")
  press("grn")
  h.eq(ran.grn, 1, "grn ran")
  srv.unregister({ "textDocument/rename" })
  h.eq(menu(buf).grn, nil, "grn after the unregistration")
  srv.stop()
end)

--- The messages echoed while fn ran.
local function echoed(fn)
  vim.cmd("messages clear")
  fn()
  return vim.api.nvim_exec2("messages", { output = true }).output
end

h.case("an echo row where its need fails says so and leaves the text alone (D49)", function()
  local buf = scratch()
  ran.grn = nil
  local msg = echoed(function() press("grn") end)
  h.eq(text(buf), LINES, "the text (Vim's gr{char} would replace the x)")
  h.eq(ran.grn, nil, "grn's action")
  h.ok(msg:find("textDocument/rename", 1, true), "a message naming the need, got " .. msg)
end)

h.case("a leader key whose need fails only says which need it lacks", function()
  local buf = scratch()
  local msg = echoed(function() press("<leader>sS") end)
  h.eq({ ran.symbols, cursor(), text(buf) }, { nil, { 3, 6 }, LINES }, "action, cursor and text")
  h.ok(msg:find("workspace/symbol", 1, true), "a message naming the need, got " .. msg)
end)

h.case("a buffer's own map wins, where the need holds and where it fails", function()
  local buf = scratch()
  vim.keymap.set("n", "gd", counter("own gd"), { buf = buf })
  press("gd")
  local srv = server.start({ buf = buf, methods = { "textDocument/definition" } })
  ran.gd = nil
  press("gd")
  h.eq({ ran["own gd"], ran.gd }, { 2, nil }, "presses of the buffer's map and of the row")
  srv.stop()
end)

h.case("where a buffer's own map wins the press, the popup shows that map's desc, not a row's label", function()
  local buf = scratch()
  local srv = server.start({ buf = buf, methods = { "textDocument/definition" } })
  vim.keymap.set("n", "gd", counter("own gd"), { buf = buf, desc = "The buffer's gd" })
  h.eq(menu(buf).gd and menu(buf).gd.label, "The buffer's gd", "a row whose need holds")
  h.eq(menu(buf).gd.icon, nil, "the row's icon")
  vim.keymap.set("n", "gd", counter("own gd"), { buf = buf })
  h.ok(menu(buf).gd == nil or menu(buf).gd.label ~= "Definition", "a map with no desc gets no row label")
  srv.stop()
  -- a language's label is for the buffer's maps that have no desc
  keys.language("fixdesc")({ "]y", label = "Next fix item" })
  local lang = scratch()
  vim.keymap.set("n", "]y", "<Nop>", { buf = lang, desc = "The ftplugin's own words" })
  vim.bo[lang].filetype = "fixdesc"
  h.eq(menu(lang)["]y"] and menu(lang)["]y"].label, "The ftplugin's own words", "a label-only language row")
end)

h.case("a global K row keeps Neovim from mapping K in a hover server's buffer", function()
  local buf = scratch()
  local srv = server.start({ buf = buf, methods = { "textDocument/hover" } })
  h.eq(vim.fn.maparg("K", "n", false, true).buffer, 0, "K's map is the global one")
  press("K")
  h.eq(ran.K, 1, "K ran the row")
  srv.stop()
end)

h.case("where the need fails the key runs the global map it took over", function()
  vim.keymap.set("n", "]x", counter("prior callback"))
  vim.keymap.set("n", "]y", "G")
  keys.feature("taker")({ { "]x", counter("]x"), "Next x", need = "word-off" }, { "]y", counter("]y"), "Next y", need = "word-off" } })
  local on = false
  keys.need("word-off", function() return on end)
  scratch()
  press("]x")
  press("]y")
  h.eq({ ran["prior callback"], ran["]x"], cursor()[1] }, { 1, nil, 3 }, "prior callback ran; ]y's prior G went to the last line")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  on = true
  press("]x")
  press("]y")
  h.eq({ ran["prior callback"], ran["]x"], ran["]y"], cursor()[1] }, { 1, 1, 1, 1 }, "the rows ran instead")
end)

h.case("a word need is read on each press and each menu", function()
  local on = false
  keys.need("flag", function() return on end)
  keys.feature("flagged", { need = "flag" })({ "<leader>F", counter("flagged"), "Flagged" })
  local buf = scratch()
  press("<leader>F")
  h.eq({ ran.flagged, menu(buf)["<Space>F"] }, { nil, nil }, "off: action and menu")
  on = true
  press("<leader>F")
  h.eq(ran.flagged, 1, "on: the action ran")
  h.ok(menu(buf)["<Space>F"] ~= nil, "on: listed")
end)

h.case("a client:<name> need holds where that server is attached", function()
  keys.feature("pyrefly")({ "<leader>P", counter("P"), "Pyrefly only", need = "client:fakepy" })
  local buf = scratch()
  local other = server.start({ buf = buf, name = "other", methods = {} })
  h.eq(keys.holds("client:fakepy", buf), false, "another server")
  local srv = server.start({ buf = buf, name = "fakepy", methods = {} })
  h.eq(keys.holds("client:fakepy", buf), true, "fakepy attached")
  press("<leader>P")
  h.eq(ran.P, 1, "the row ran")
  srv.stop()
  other.stop()
  h.eq(keys.holds("client:fakepy", buf), false, "fakepy stopped")
end)

h.case("an unknown need never holds and is reported", function()
  said = {}
  h.eq(keys.holds("no such need", scratch()), false, "holds")
  h.ok(said[1] and said[1]:find("no such need", 1, true), "reported, got " .. vim.inspect(said))
end)

h.case("a visual row runs in visual mode, on the selection", function()
  local mode
  keys.feature("visual")({ "<leader>V", function() mode = vim.fn.mode() end, "In visual", mode = "x" })
  scratch()
  press("V<leader>V")
  h.eq(mode, "V", "the mode the action saw")
  vim.cmd("normal! \27")
end)

h.case("a toggle row flips its state, says so, and its label follows", function()
  local state = false
  keys.feature("toggles")({ "<leader>Tz", toggle = { get = function() return state end, set = function(v) state = v end }, label = "Zed" })
  local buf = scratch()
  h.eq(menu(buf)["<Space>Tz"].label, "Enable Zed", "label while off")
  said = {}
  press("<leader>Tz")
  h.eq(state, true, "state after a press")
  h.eq(menu(buf)["<Space>Tz"].label, "Disable Zed", "label while on")
  h.ok(said[1] and said[1]:find("Enabled", 1, true) and said[1]:find("Zed", 1, true), "the notice, got " .. vim.inspect(said))
  press("<leader>Tz")
  h.eq(state, false, "state after a second press")
end)

h.case("a toggle with a need flips only where the need holds", function()
  local state, on = false, false
  keys.need("toggle-need", function() return on end)
  keys.feature("toggles")({ "<leader>Ty", toggle = { get = function() return state end, set = function(v) state = v end }, label = "Why", need = "toggle-need" })
  local buf = scratch()
  press("<leader>Ty")
  h.eq({ state, menu(buf)["<Space>Ty"] }, { false, nil }, "need fails: state and menu")
  on = true
  press("<leader>Ty")
  h.eq(state, true, "need holds: flipped")
end)

h.case("a language row is buffer-local in its filetype and gives way to the buffer's own map", function()
  keys.language("fixlang")({ "<leader>L", counter("L"), "Language key" })
  local other = scratch("fixother")
  press("<leader>L")
  h.eq(ran.L, nil, "another filetype")
  h.eq(menu(other)["<Space>L"], nil, "listed in another filetype")
  local buf = scratch("fixlang")
  press("<leader>L")
  h.eq(ran.L, 1, "its filetype")
  h.eq(vim.fn.maparg("<leader>L", "n", false, true).buffer, 1, "the map is the buffer's")
  h.ok(menu(buf)["<Space>L"] ~= nil, "listed in its filetype")
  scratch("fixother.fixlang")
  press("<leader>L")
  h.eq(ran.L, 2, "a dotted filetype with its part")
  -- an ftplugin's map is in the buffer before keys places its own on FileType
  local own = scratch()
  vim.keymap.set("n", "<leader>L", counter("ftplugin L"), { buf = own })
  vim.bo[own].filetype = "fixlang"
  press("<leader>L")
  h.eq({ ran["ftplugin L"], ran.L }, { 1, 2 }, "the buffer's own map ran, not the row")
end)

h.case("a label-only language row labels the buffer's map, only in its filetype and only where the map is", function()
  keys.language("fixlabel")({ "]j", label = "Next fix item" })
  local buf = scratch()
  vim.keymap.set("n", "]j", "<Nop>", { buf = buf })
  h.eq(menu(buf)["]j"], nil, "another filetype with a map")
  vim.bo[buf].filetype = "fixlabel"
  h.eq(menu(buf)["]j"] and menu(buf)["]j"].label, "Next fix item", "its filetype with a map")
  local bare = scratch("fixlabel")
  h.eq(menu(bare)["]j"], nil, "its filetype with no map")
  h.eq(vim.fn.maparg("]j", "n"), "", "a label-only row maps nothing")
end)

h.case("a native row is listed without a map, a group only with a listed key under it", function()
  local on = false
  keys.need("native-need", function() return on end)
  keys.feature("natives")({
    { "zZ", label = "A native key", native = true, need = "native-need" },
    { "<leader>Q", group = "Q things" },
    { "<leader>Qa", counter("Qa"), "Qa", need = "native-need" },
  })
  local buf = scratch()
  local m = menu(buf)
  h.eq({ m.zZ, m["<Space>Q"] }, { nil, nil }, "need fails: the native key and the group")
  on = true
  m = menu(buf)
  h.eq(m.zZ and m.zZ.label, "A native key", "the native key")
  h.eq(m["<Space>Q"] and { m["<Space>Q"].label, m["<Space>Q"].group }, { "Q things", true }, "the group")
  h.eq(vim.fn.maparg("zZ", "n"), "", "a native row maps nothing")
end)

h.case("a need shared by many rows is tested once per menu", function()
  local calls = 0
  keys.need("counted", function()
    calls = calls + 1
    return true
  end)
  local add = keys.feature("counted", { need = "counted" })
  for i = 1, 5 do
    add({ "<leader>C" .. i, counter("C"), "C" .. i })
  end
  local buf = scratch()
  calls = 0
  keys.menu(buf, "n")
  h.eq(calls, 1, "tests per menu")
end)

h.case("a row with an unknown field is refused, naming where it was declared", function()
  local add = keys.feature("bad")
  local ok, err = pcall(function() add({ "<leader>B", counter("B"), "Bad", needs = "typo" }) end)
  h.ok(not ok and err:find("needs", 1, true) and err:find("keys_test.lua", 1, true), "error: " .. tostring(err))
end)

h.case("rows declared again from the same place (a module sourced again) replace the first ones", function()
  -- :source of a feature file runs its rows again (CONTRIBUTING.md, "Testing Changes")
  local function spec(name)
    keys.feature("again")({ { "<leader>A", counter(name), name }, { "<leader>B", counter(name .. "B"), "B", need = "again" } })
    keys.language("againlang")({ "<leader>C", counter(name .. "C"), "C" })
  end
  keys.need("again", function() return true end)
  spec("first")
  spec("second")
  local buf = scratch("againlang")
  press("<leader>A")
  press("<leader>B")
  press("<leader>C")
  h.eq({ ran.first, ran.firstB, ran.firstC }, { nil, nil, nil }, "the first declaration's actions")
  h.eq({ ran.second, ran.secondB, ran.secondC }, { 1, 1, 1 }, "the second declaration's actions")
  local count = {}
  for _, r in ipairs(keys.list()) do
    count[r.lhs] = (count[r.lhs] or 0) + 1
  end
  h.eq({ count["<leader>A"], count["<leader>B"], count["<leader>C"] }, { 1, 1, 1 }, "rows listed")
  h.eq(menu(buf)["<Space>A"] and menu(buf)["<Space>A"].label, "second", "the label is the second's")
end)

h.case("list gives every row with its owner and the line that declared it", function()
  local row
  for _, r in ipairs(keys.list()) do
    if r.lhs == "gd" then
      row = r
    end
  end
  h.ok(row ~= nil, "gd is listed")
  h.eq({ row.owner, row.label, row.need, row.mode }, { "lsp", "Definition", { "definition" }, "n" }, "gd's entry")
  h.ok(row.at:find("keys_test.lua:%d+$") ~= nil, "where: " .. row.at)
end)

h.finish()
