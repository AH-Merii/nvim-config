-- Neovim's own keys as rows: its LSP keys, and labels and icons for the built-ins and the runtime's default and ftplugin
-- maps, and the ones the popup leaves out. Only the LSP rows map a key.
-- valid colors for reference: `azure`, `blue`, `cyan`, `green`, `grey`, `orange`, `purple`, `red`, `yellow`
local keys = require("keys")
local key = keys.feature("neovim")

local NXO = { "n", "x", "o" }

-- Where Neovim's own keys would act at the cursor now (D132): each a lookup, read on a press and once per popup
-- rebuild. win is the window whose cursor and folds to read; nil where no window shows the buffer.

---@param win integer
---@param fn fun(): any
local function in_win(win, fn)
  if win == vim.api.nvim_get_current_win() then
    return fn()
  end
  return vim.api.nvim_win_call(win, fn)
end
---@param win integer
local function lnum(win) return vim.api.nvim_win_get_cursor(win)[1] end

-- Folds, which are the window's: za, zA, ]z and [z need a fold on the line; zo and zO a closed one; zc and zC one
-- they can close, an open fold or a closed one inside an open one
keys.need("a fold here", function(_, win)
  return win ~= nil and in_win(win, function() return vim.fn.foldlevel(lnum(win)) > 0 end)
end)
keys.need("a closed fold here", function(_, win)
  return win ~= nil and in_win(win, function() return vim.fn.foldclosed(lnum(win)) ~= -1 end)
end)
keys.need("an open fold here", function(_, win)
  return win ~= nil
    and in_win(win, function()
      local l = lnum(win)
      return vim.fn.foldclosed(l) == -1 and vim.fn.foldlevel(l) > 0 or vim.fn.foldlevel(l) > 1
    end)
end)
-- zf creates folds only with manual or marker folding; zd and zD delete them only on a fold there
---@param win integer
local function manual(win) return vim.wo[win].foldmethod == "manual" or vim.wo[win].foldmethod == "marker" end
keys.need("manual folding", function(_, win) return win ~= nil and manual(win) end)
keys.need("a manual fold here", function(_, win)
  return win ~= nil and manual(win) and in_win(win, function() return vim.fn.foldlevel(lnum(win)) > 0 end)
end)

-- Spelling, which is the window's: ]s and [s with spell checking on (whether a misspelled word is anywhere would
-- take a scan of the buffer); z= on a misspelled word
keys.need("spell checking", function(_, win) return win ~= nil and vim.wo[win].spell end)
keys.need("a misspelled word here", function(_, win)
  return win ~= nil
    and vim.wo[win].spell
    and in_win(win, function()
      local word = vim.fn.expand("<cword>")
      return word ~= "" and vim.fn.spellbadword(word)[1] ~= ""
    end)
end)

-- ]d and [d, and the buffer's diagnostics lists (features/diagnostics.lua): a diagnostic anywhere in the buffer
keys.need("a diagnostic in the buffer", function(buf) return next(vim.diagnostic.count(buf)) ~= nil end)

-- The quickfix and location lists in Trouble (features/diagnostics.lua): a list with entries; the location list is
-- the current window's
keys.need("a quickfix list", function() return vim.fn.getqflist({ size = 0 }).size > 0 end)
keys.need("a location list", function() return vim.fn.getloclist(0, { size = 0 }).size > 0 end)

-- gx: what Neovim's gx opens (vim.ui._get_urls), less the server's document links, which it asks for with a
-- synchronous request: a URL extmark at the cursor, a URL the highlights query names there (a markdown link's text),
-- or <cfile> as a URL or an existing path

-- Whether a language's highlights query sets a url anywhere (markdown_inline's does, python's doesn't), read once per
-- language. The lookup at the cursor costs 0.5 ms a check in the TUI on a 4208-line python buffer, so only a buffer
-- with such a language pays it
local url_langs = {} ---@type table<string, boolean>
---@param lang string
local function sets_url(lang)
  if url_langs[lang] == nil then
    local query = vim.treesitter.query.get(lang, "highlights")
    url_langs[lang] = query ~= nil
      and vim.iter(pairs(query.info.patterns)):any(function(_, directives)
        return vim.iter(directives):any(function(d) return d[1] == "set!" and vim.list_contains(d, "url") end)
      end)
  end
  return url_langs[lang]
end
---@param tree vim.treesitter.LanguageTree
local function any_url_lang(tree)
  if sets_url(tree:lang()) then
    return true
  end
  for _, child in pairs(tree:children()) do
    if any_url_lang(child) then
      return true
    end
  end
  return false
end
---@param buf integer
---@param row integer 0-based
---@param col integer
local function ts_url(buf, row, col)
  local highlighter = vim.treesitter.highlighter.active[buf]
  if not highlighter or not any_url_lang(highlighter.tree) then
    return false
  end
  local range = { row, col, row, col }
  local ltree = highlighter.tree:language_for_range(range)
  local query = vim.treesitter.query.get(ltree:lang(), "highlights")
  local tree = query and ltree:tree_for_range(range)
  if not tree then
    return false
  end
  for _, match, metadata in query:iter_matches(tree:root(), buf, row, row + 1) do
    for id, nodes in pairs(match) do
      local url = metadata[id] and metadata[id].url
      if url and match[url] then
        for _, node in ipairs(nodes) do
          if vim.treesitter.node_contains(node, range) then
            return true
          end
        end
      end
    end
  end
  return false
end
keys.need("a path or URL here", function(buf, win)
  if not win then
    return false
  end
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  row = row - 1
  local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { row, col }, { row, col }, { details = true, type = "highlight", overlap = true })
  for _, m in ipairs(marks) do
    if m[4].url then
      return true
    end
  end
  if ts_url(buf, row, col) then
    return true
  end
  -- gx reads <cfile> with "@" in 'isfname'; setting the option costs 25 µs, so only on a line with an "@"
  local at = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]:find("@", 1, true)
  local file = in_win(win, function()
    if not at then
      return vim.fn.expand("<cfile>")
    end
    return vim._with({ go = { isfname = vim.o.isfname .. ",@-@" } }, function() return vim.fn.expand("<cfile>") end)
  end)
  return file ~= "" and (file:match("^%a[%w+.-]*://") ~= nil or vim.uv.fs_stat(vim.fs.normalize(file)) ~= nil)
end)

-- grx runs the lenses on the cursor's line, which it asks the servers for: with lenses shown, one drawn there; with
-- them off in the buffer, a server that has lenses (D133's closest answer)
keys.need("a code lens on this line", function(buf, win)
  if not vim.lsp.codelens.is_enabled({ bufnr = buf }) then
    return keys.holds("codeLens", buf)
  end
  if not win then
    return false
  end
  local row = lnum(win) - 1
  for _, l in ipairs(vim.lsp.codelens.get({ bufnr = buf })) do
    if l.lens.range.start.line == row then
      return true
    end
  end
  return false
end)

-- Neovim's LSP keys (:h lsp-defaults) as rows that act where a server supports the method (D133), grx where a code
-- lens is on the line (D132). Their global maps go, so they are no fallback: where no server can act the key says
-- which need it lacks, instead of Vim's gr{char} editing the text (D49). Loaded before lsp/buffer, whose grr row (the references picker) replaces Neovim's grr.
pcall(vim.keymap.del, "n", "grr")
local lsp = keys.feature("neovim lsp")
for _, builtin in ipairs({
  { "grn", "rename", "Rename" },
  { "gra", "codeAction", "Code action", { icon = "󱍔", color = "purple" } },
  { "gri", "implementation", "Implementation" },
  { "grt", "typeDefinition", "Type definition" },
  { "grx", "a code lens on this line", "Run code lens" },
  { "gO", "documentSymbol", "Document symbols" },
}) do
  local lhs, need, label, icon = builtin[1], builtin[2], builtin[3], builtin[4]
  for _, mode in ipairs({ "n", "x" }) do
    local map = vim.fn.maparg(lhs, mode, false, true)
    if map.callback then
      vim.keymap.del(mode, lhs)
      lsp({ lhs, map.callback, label, mode = mode, need = need, echo = true, icon = icon })
    end
  end
end

key({
  -- text objects after an operator or in visual mode; the treesitter ones are textobjects/' rows
  { "a", group = "Around", mode = { "x", "o" } },
  { "i", group = "Inside", mode = { "x", "o" } },

  -- the map's own desc is missing or names the normal-mode action
  { "gc", label = "Comment lines", mode = "x", icon = { icon = "󰅺", color = "grey" } },
  { "*", label = "Search selection forward", mode = "x" },
  { "#", label = "Search selection backward", mode = "x" },
  { "@", label = "Run macro on each line", mode = "x" },
  { "gx", label = "Open path or URL", mode = "x" },
  -- Neovim's own gx map: listed where it would open something, and pressed as before everywhere
  { "gx", label = "Open path or URL", need = "a path or URL here" },
  { ",", label = "Repeat f/t backward", mode = "x" },
  { ";", label = "Repeat f/t forward", mode = "x" },
  { "%", label = "Jump to matching pair", mode = NXO },
  { "g%", label = "Jump to previous match", mode = NXO },
  { "a%", label = "Around matching pair", mode = "x" },
  { "gc", icon = { icon = "󰅺", color = "grey" } },

  -- Folds (labels only; no remaps)
  { "z", group = "Folds", mode = { "n", "x" }, icon = { icon = "", color = "yellow" } },
  { "za", label = "Toggle fold", native = true, need = "a fold here" },
  { "zA", label = "Toggle fold (recursive)", native = true, need = "a fold here" },
  -- Only this one needs Visual too
  { "zf", label = "Create fold", mode = { "n", "x" }, icon = { icon = "", color = "yellow" }, native = true, need = "manual folding" },
  { "zc", label = "Close fold", icon = { icon = "", color = "orange" }, native = true, need = "an open fold here" },
  { "zC", label = "Close fold (recursive)", icon = { icon = "", color = "orange" }, native = true, need = "an open fold here" },
  { "zo", label = "Open fold", icon = { icon = "", color = "cyan" }, native = true, need = "a closed fold here" },
  { "zO", label = "Open fold (recursive)", icon = { icon = "", color = "cyan" }, native = true, need = "a closed fold here" },
  { "zM", label = "Close all folds", icon = { icon = "", color = "orange" }, native = true },
  { "zR", label = "Open all folds", icon = { icon = "", color = "cyan" }, native = true },
  { "zm", label = "More folding (increase level)", icon = { icon = "", color = "cyan" }, native = true },
  { "zr", label = "Reduce folding (decrease level)", icon = { icon = "", color = "orange" }, native = true },
  { "zx", label = "Recompute folds", icon = { icon = "", color = "yellow" }, native = true },
  { "zd", label = "Delete fold under cursor", icon = { icon = "󰗨", color = "red" }, native = true, need = "a manual fold here" },
  { "zD", label = "Delete all manual folds", icon = { icon = "󰗩", color = "red" }, native = true, need = "a manual fold here" },
  -- Global toggle
  { "zi", label = "Toggle folding (foldenable)", native = true },

  -- Jump groups
  { "]", group = "Jump to next", mode = NXO, icon = { icon = "󰒭", color = "cyan" } },
  { "[", group = "Jump to previous", mode = NXO, icon = { icon = "󰒮", color = "orange" } },
  -- Filetype plugin motions, labelled below per language
  { "[m", mode = NXO, icon = { icon = "", color = "orange" } },
  { "]m", mode = NXO, icon = { icon = "", color = "purple" } },
  { "[M", mode = NXO, icon = { icon = "", color = "cyan" } },
  { "]M", mode = NXO, icon = { icon = "", color = "cyan" } },
  { "[]", mode = NXO, icon = { icon = "", color = "cyan" } },
  { "][", mode = NXO, icon = { icon = "", color = "cyan" } },
  -- Snacks words references, or the filetype plugin's sections. Labels only, with no need: they stay at buffer
  -- level, as the word-reference rows in lsp/buffer.lua do (D132)
  { "]]", mode = NXO, icon = { icon = "", color = "grey" } },
  { "[[", mode = NXO, icon = { icon = "", color = "grey" } },
  -- Spelling
  { "]s", label = " misspelled word", mode = NXO, icon = { icon = "󰓆", color = "red" }, native = true, need = "spell checking" },
  { "[s", label = "misspelled word", mode = NXO, icon = { icon = "󰓆", color = "red" }, native = true, need = "spell checking" },
  { "z=", label = "Spelling suggestions", icon = { icon = "󰓆", color = "red" }, native = true, need = "a misspelled word here" },
  -- Folds
  { "]z", label = " fold end", mode = NXO, icon = { icon = "", color = "yellow" }, native = true, need = "a fold here" },
  { "[z", label = "fold start", mode = NXO, icon = { icon = "", color = "yellow" }, native = true, need = "a fold here" },
  -- built-ins that do nothing in visual and operator-pending mode; Neovim maps ]d and [d, so their need only hides
  -- them
  { "]d", label = " diagnostic", icon = { icon = "", color = "orange" }, native = true, need = "a diagnostic in the buffer" },
  { "[d", label = "diagnostic", icon = { icon = "", color = "orange" }, native = true, need = "a diagnostic in the buffer" },
  { "]t", label = " tag", icon = { icon = "", color = "yellow" }, native = true },
  { "[t", label = "tag", icon = { icon = "", color = "yellow" }, native = true },
  { "]q", label = " quickfix item", icon = { icon = "", color = "yellow" }, native = true },
  { "[q", label = "quickfix item", icon = { icon = "", color = "yellow" }, native = true },
  { "[ ", label = "Add Space Above", icon = { icon = "󰞙", color = "grey" }, native = true },
  { "] ", label = "Add Space Below", icon = { icon = "󰞖", color = "grey" }, native = true },

  -- left out of the popup
  { "]L", hidden = true },
  { "]T", hidden = true },
  { "]D", hidden = true },
  { "]A", hidden = true },
  { "]Q", hidden = true },
  { "]<C-T>", hidden = true },
  { "]<C-Q>", hidden = true },
  { "]<C-L>", hidden = true },
  { "]%", mode = NXO, hidden = true },
  { "[L", hidden = true },
  { "[T", hidden = true },
  { "[D", hidden = true },
  { "[A", hidden = true },
  { "[Q", hidden = true },
  { "[<C-T>", hidden = true },
  { "[<C-Q>", hidden = true },
  { "[<C-L>", hidden = true },
  { "[%", mode = NXO, hidden = true },
  -- node selection, labelled on + and -
  { "an", mode = "x", hidden = true },
  { "in", mode = "x", hidden = true },
})
