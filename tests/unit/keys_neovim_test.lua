-- Neovim's own keys as rows (keys/neovim.lua) are listed only where they would act at the cursor now (D132): the
-- fold keys on a fold, the spelling keys with spell checking, the diagnostic moves with a diagnostic in the buffer,
-- gx on a path or URL, grx on a code lens. Read through keys.menu, with the real runtime and a fake server; no
-- plugins. nvim --clean --headless -l tests/unit/keys_neovim_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local server = require("fake_server")

vim.g.mapleader = " "
local keys = require("keys")
require("keys.neovim")

local function listed(buf, mode)
  local out = {}
  for _, item in ipairs(keys.menu(buf, mode)) do
    out[item.lhs] = true
  end
  return out
end
--- Which of lhss the menu lists for the current buffer in mode, as "lhs lhs ...", in the order given.
local function which(lhss, mode)
  local got = listed(vim.api.nvim_get_current_buf(), mode or "n")
  return table.concat(vim.tbl_filter(function(l) return got[l] end, lhss), " ")
end

local DIR = h.tmpdir()
local n = 0
---@param lines string[]
local function scratch(lines)
  n = n + 1
  vim.cmd.enew()
  vim.cmd("silent! only")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, ("%s/scratch%d.txt"):format(DIR, n))
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end
local function at(row, col) vim.api.nvim_win_set_cursor(0, { row, col or 0 }) end

local FOLDS = { "za", "zA", "]z", "[z", "zo", "zO", "zc", "zC", "zd", "zD", "zf" }
local BODY = { "a", "  b", "  c", "  d", "e", "f", "g", "h" }

h.case("the fold keys are listed only where they would act on the cursor's line", function()
  scratch(BODY)
  vim.wo.foldmethod = "manual"
  vim.cmd("2,4fold")
  at(6)
  h.eq(which(FOLDS), "zf", "manual folding, no fold on the line: only creating one")
  at(3)
  h.eq(which(FOLDS), "za zA ]z [z zo zO zd zD zf", "a closed fold: toggle, open, delete, moves, create")
  vim.cmd("normal! zo")
  h.eq(which(FOLDS), "za zA ]z [z zc zC zd zD zf", "the fold opened: toggle, close, delete, moves, create")
  at(1)
  h.eq(which(FOLDS), "zf", "back on a line with no fold")
  h.eq(which({ "zf" }, "x"), "zf", "Visual zf with manual folding")
end)

h.case("a closed fold inside an open one can still be closed further", function()
  scratch(BODY)
  vim.wo.foldmethod = "manual"
  vim.cmd("2,6fold")
  vim.cmd("normal! zR")
  vim.cmd("3,4fold")
  at(3)
  h.eq(vim.fn.foldclosed(3) ~= -1 and vim.fn.foldlevel(3) == 2, true, "precondition: a closed fold at level 2")
  h.eq(which({ "zo", "zc", "zC" }), "zo zc zC", "zc closes the enclosing open fold")
end)

h.case("folds by indent: the fold keys act, the manual ones do not", function()
  scratch(BODY)
  vim.bo.shiftwidth = 2
  vim.wo.foldmethod = "indent"
  vim.wo.foldlevel = 99
  at(3)
  h.eq(which(FOLDS), "za zA ]z [z zc zC", "an open fold by indent")
  at(6)
  h.eq(which(FOLDS), "", "no fold on the line")
  h.eq(which({ "zf" }, "x"), "", "Visual zf")
end)

h.case("folds by marker: zf adds markers anywhere, zd removes them on a fold", function()
  scratch({ "a {{{", "b", "c }}}", "d" })
  vim.wo.foldmethod = "marker"
  vim.wo.foldlevel = 99
  at(2)
  h.eq(which({ "zd", "zD", "zf", "zc" }), "zd zD zf zc", "on the marker fold")
  at(4)
  h.eq(which({ "zd", "zD", "zf", "zc" }), "zf", "off it")
end)

h.case("the fold keys follow the window's folds, not another window's on the same buffer", function()
  local buf = scratch(BODY)
  vim.wo.foldmethod = "manual"
  vim.cmd("2,4fold")
  vim.cmd("vsplit")
  -- the new window copies the folds; open them there only, and read the first window from the second
  at(3)
  vim.cmd("normal! zo")
  h.eq(which({ "zo", "zc" }), "zc", "this window's fold is open")
  vim.cmd("wincmd p")
  at(3)
  h.eq(vim.api.nvim_get_current_buf(), buf, "precondition: the same buffer")
  h.eq(which({ "zo", "zc" }), "zo", "the other window's is closed")
  vim.cmd("silent! only")
end)

h.case("the spelling moves are listed only with spell checking on, in every mode they have", function()
  scratch({ "helo wrld", "hello world" })
  at(1)
  for _, mode in ipairs({ "n", "x", "o" }) do
    vim.wo.spell = false
    h.eq(which({ "]s", "[s" }, mode), "", mode .. ": spell off")
    vim.wo.spell = true
    h.eq(which({ "]s", "[s" }, mode), "]s [s", mode .. ": spell on")
  end
end)

h.case("z= is listed on a misspelled word with spell checking on", function()
  scratch({ "helo wrld", "hello world" })
  vim.wo.spell = true
  at(1, 1)
  h.eq(which({ "z=" }), "z=", "on helo")
  at(2, 1)
  h.eq(which({ "z=" }), "", "on hello")
  vim.wo.spell = false
  at(1, 1)
  h.eq(which({ "z=" }), "", "on helo, spell off")
end)

h.case("the diagnostic moves are listed only where the buffer has a diagnostic", function()
  local ns = vim.api.nvim_create_namespace("keys_neovim_test")
  local buf = scratch({ "one", "two", "three" })
  local other = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(other, 0, -1, false, { "x" })
  h.eq(which({ "]d", "[d" }), "", "no diagnostics anywhere")
  vim.diagnostic.set(ns, other, { { lnum = 0, col = 0, message = "elsewhere", severity = vim.diagnostic.severity.ERROR } })
  h.eq(which({ "]d", "[d" }), "", "a diagnostic in another buffer only")
  vim.diagnostic.set(ns, buf, { { lnum = 2, col = 0, message = "here", severity = vim.diagnostic.severity.HINT } })
  at(1)
  h.eq(which({ "]d", "[d" }), "]d [d", "a diagnostic on another line of this buffer: the moves reach it")
  vim.diagnostic.reset(ns, buf)
  h.eq(which({ "]d", "[d" }), "", "after the reset")
  vim.diagnostic.reset(ns)
end)

h.case("gx is listed on a URL or an existing path under the cursor, not on other text", function()
  vim.fn.writefile({ "x" }, DIR .. "/exists.txt")
  vim.fn.writefile({ "x" }, DIR .. "/a@b.txt")
  vim.cmd.cd(DIR)
  local buf = scratch({ "see https://example.com/x here", "open ./exists.txt now", "a plain word", "gone ./nope.txt", "at ./a@b.txt" })
  at(1, 8)
  h.eq(which({ "gx" }), "gx", "a URL")
  at(2, 8)
  h.eq(which({ "gx" }), "gx", "a path that exists")
  at(3, 3)
  h.eq(which({ "gx" }), "", "a plain word")
  at(4, 8)
  h.eq(which({ "gx" }), "", "a path that does not exist")
  at(5, 5)
  h.eq(which({ "gx" }), "gx", "a path with an @, which gx reads as part of the name")
  vim.api.nvim_buf_set_extmark(buf, vim.api.nvim_create_namespace("keys_neovim_url"), 2, 2, { end_col = 7, url = "https://example.com/plain", hl_group = "Underlined" })
  at(3, 3)
  h.eq(which({ "gx" }), "gx", "a word with a URL extmark")
end)

h.case("gx is listed on a markdown link's text, whose target the highlights query names", function()
  local buf = scratch({ "read [the docs](https://example.com/docs) first", "" })
  vim.bo[buf].filetype = "markdown"
  vim.treesitter.start(buf, "markdown")
  vim.treesitter.get_parser(buf):parse(true)
  at(1, 7)
  h.eq(which({ "gx" }), "gx", "on the link text")
  at(1, 47)
  h.eq(which({ "gx" }), "", "on the word after the link")
end)

h.case("grx is listed on a line with a code lens; with lenses off, where a server has them", function()
  local buf = scratch({ "def a():", "  pass", "def b():" })
  vim.bo[buf].filetype = "sbxlens"
  vim.lsp.codelens.enable(true)
  local lens = function(line) return { range = { start = { line = line, character = 0 }, ["end"] = { line = line, character = 3 } }, command = { title = "run", command = "fake.run" } } end
  local srv = server.start({ buf = buf, capabilities = { codeLensProvider = {} }, handlers = { ["textDocument/codeLens"] = function() return { lens(0), lens(2) } end } })
  vim.cmd.redraw()
  h.ok(vim.wait(3000, function()
    vim.cmd.redraw()
    return #vim.lsp.codelens.get({ bufnr = buf }) == 2
  end, 10), "the lenses arrived")
  at(1)
  h.eq(which({ "grx" }), "grx", "on a lens's line")
  at(2)
  h.eq(which({ "grx" }), "", "on a line without one")
  vim.lsp.codelens.enable(false, { bufnr = buf })
  h.eq(which({ "grx" }), "grx", "lenses off in the buffer: grx still asks the server, which has lenses")
  srv.stop()
  h.eq(which({ "grx" }), "", "no server")
  vim.lsp.codelens.enable(true, { bufnr = buf })
end)

h.finish()
