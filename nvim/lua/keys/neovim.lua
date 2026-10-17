-- Neovim's own keys as rows: its LSP keys, and labels and icons for the built-ins and the runtime's default and ftplugin
-- maps, and the ones the popup leaves out. Only the LSP rows map a key.
-- valid colors for reference: `azure`, `blue`, `cyan`, `green`, `grey`, `orange`, `purple`, `red`, `yellow`
local keys = require("keys")
local key = keys.feature("neovim")

local NXO = { "n", "x", "o" }

-- Neovim's LSP keys (:h lsp-defaults) as rows that act where a server supports the method. Its global maps go, so they
-- are no fallback: where no server can act the key says which method it lacks, instead of Vim's gr{char} editing the
-- text (D49). Loaded before lsp/buffer, whose grr row (the references picker) replaces Neovim's grr.
pcall(vim.keymap.del, "n", "grr")
local lsp = keys.feature("neovim lsp")
for _, builtin in ipairs({
  { "grn", "rename", "Rename" },
  { "gra", "codeAction", "Code action", { icon = "󱍔", color = "purple" } },
  { "gri", "implementation", "Implementation" },
  { "grt", "typeDefinition", "Type definition" },
  { "grx", "codeLens", "Run code lens" },
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
  -- text objects after an operator or in visual mode; the treesitter ones are config/textobjects' rows
  { "a", group = "Around", mode = { "x", "o" } },
  { "i", group = "Inside", mode = { "x", "o" } },

  -- the map's own desc is missing or names the normal-mode action
  { "gc", label = "Comment lines", mode = "x", icon = { icon = "󰅺", color = "grey" } },
  { "*", label = "Search selection forward", mode = "x" },
  { "#", label = "Search selection backward", mode = "x" },
  { "@", label = "Run macro on each line", mode = "x" },
  { "gx", label = "Open path or URL", mode = "x" },
  { ",", label = "Repeat f/t backward", mode = "x" },
  { ";", label = "Repeat f/t forward", mode = "x" },
  { "%", label = "Jump to matching pair", mode = NXO },
  { "g%", label = "Jump to previous match", mode = NXO },
  { "a%", label = "Around matching pair", mode = "x" },
  { "gc", icon = { icon = "󰅺", color = "grey" } },

  -- Folds (labels only; no remaps)
  { "z", group = "Folds", mode = { "n", "x" }, icon = { icon = "", color = "yellow" } },
  { "za", label = "Toggle fold", native = true },
  { "zA", label = "Toggle fold (recursive)", native = true },
  -- Only this one needs Visual too
  { "zf", label = "Create fold", mode = { "n", "x" }, icon = { icon = "", color = "yellow" }, native = true },
  { "zc", label = "Close fold", icon = { icon = "", color = "orange" }, native = true },
  { "zC", label = "Close fold (recursive)", icon = { icon = "", color = "orange" }, native = true },
  { "zo", label = "Open fold", icon = { icon = "", color = "cyan" }, native = true },
  { "zO", label = "Open fold (recursive)", icon = { icon = "", color = "cyan" }, native = true },
  { "zM", label = "Close all folds", icon = { icon = "", color = "orange" }, native = true },
  { "zR", label = "Open all folds", icon = { icon = "", color = "cyan" }, native = true },
  { "zm", label = "More folding (increase level)", icon = { icon = "", color = "cyan" }, native = true },
  { "zr", label = "Reduce folding (decrease level)", icon = { icon = "", color = "orange" }, native = true },
  { "zx", label = "Recompute folds", icon = { icon = "", color = "yellow" }, native = true },
  { "zd", label = "Delete fold under cursor", icon = { icon = "󰗨", color = "red" }, native = true },
  { "zD", label = "Delete all manual folds", icon = { icon = "󰗩", color = "red" }, native = true },
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
  -- Snacks words references, or the filetype plugin's sections
  { "]]", mode = NXO, icon = { icon = "", color = "grey" } },
  { "[[", mode = NXO, icon = { icon = "", color = "grey" } },
  -- Spelling
  { "]s", label = " misspelled word", mode = NXO, icon = { icon = "󰓆", color = "red" }, native = true },
  { "[s", label = "misspelled word", mode = NXO, icon = { icon = "󰓆", color = "red" }, native = true },
  -- Folds
  { "]z", label = " fold end", mode = NXO, icon = { icon = "", color = "yellow" }, native = true },
  { "[z", label = "fold start", mode = NXO, icon = { icon = "", color = "yellow" }, native = true },
  -- built-ins that do nothing in visual and operator-pending mode
  { "]d", label = " diagnostic", icon = { icon = "", color = "orange" }, native = true },
  { "[d", label = "diagnostic", icon = { icon = "", color = "orange" }, native = true },
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

-- The runtime ftplugins map these without a desc, so the popup would show their rhs. Its labels, in the buffers whose
-- ftplugin mapped them.
local ftplugin = {
  go = {
    ["]]"] = "Next top-level func/type",
    ["[["] = "Previous top-level func/type",
    ["]["] = "Next top-level block end",
    ["[]"] = "Previous top-level block end",
  },
  markdown = {
    ["]]"] = "Next heading",
    ["[["] = "Previous heading",
  },
  php = {
    ["]]"] = "Next function/class line",
    ["[["] = "Previous function/class line",
  },
  python = {
    ["]]"] = "Next top-level def/class",
    ["[["] = "Previous top-level def/class",
    ["]["] = "Next top-level block end",
    ["[]"] = "Previous top-level block end",
    ["]m"] = "Next def/class line",
    ["[m"] = "Previous def/class line",
    ["]M"] = "Next def/class end",
    ["[M"] = "Previous def/class end",
  },
  rust = {
    ["]]"] = "Next top-level item",
    ["[["] = "Previous top-level item",
  },
}
for ft, labels in vim.spairs(ftplugin) do
  local label = keys.language(ft, { mode = NXO })
  for lhs, text in vim.spairs(labels) do
    label({ lhs, label = text })
  end
end
