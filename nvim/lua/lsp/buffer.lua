-- Diagnostics display and the LSP keys, which act where an attached client supports their method (lua/keys/);
-- the lsp module (lsp/init.lua) starts the servers
vim.diagnostic.config({
  virtual_text = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = "󰅚 ",
      [vim.diagnostic.severity.WARN] = "󰀪 ",
      [vim.diagnostic.severity.INFO] = "󰋽 ",
      [vim.diagnostic.severity.HINT] = "󰌶 ",
    },
    numhl = {
      [vim.diagnostic.severity.ERROR] = "ErrorMsg",
      [vim.diagnostic.severity.WARN] = "WarningMsg",
    },
  },
})

local keys = require("keys")

-- Loaded here, at startup, so their plans are dropped on attach, detach and ToolsChanged before any other handler
-- reads them (the statusline's)
local formatting, linting = require("format"), require("linting")

-- A formatter the filetype's language names, installed or not, or an attached client that formats (a range, for a
-- selection)
keys.need("formatter", function(buf) return formatting.has(buf) end)
keys.need("range formatter", function(buf) return formatting.has(buf, true) end)
-- Diagnostics come from attached clients, and from the linters the filetype's language names
keys.need("diagnostics", function(buf) return #vim.lsp.get_clients({ bufnr = buf }) > 0 or linting.has(buf) end)

local function format() formatting.buffer() end

local key = keys.feature("lsp")
local PURPLE = "purple"
---@param icon string
local function purple(icon) return { icon = icon, color = PURPLE } end

key({
  { "<leader>l", group = "LSP", mode = { "n", "x" }, icon = purple("󱍔") },
  { "<leader>c", group = "LSP (Trouble)", icon = purple("󰙎") },
  { "<leader>x", group = "Diagnostics", icon = { icon = "", color = "orange" } },
  { "g", group = "Goto", mode = { "n", "x" }, icon = { icon = "", color = "cyan" } },
  { "gr", group = "LSP", mode = { "n", "x" }, icon = purple("󱍔") },
  { "gC", group = "calls", icon = { icon = "󰃻", color = "yellow" } },

  { "gd", function() Snacks.picker.lsp_definitions() end, "Definition", need = "definition", icon = purple("󰊕") },
  { "gD", function() Snacks.picker.lsp_declarations() end, "Declaration", need = "declaration", icon = purple("󱈸") },
  { "gI", function() Snacks.picker.lsp_implementations() end, "Implementations", need = "implementation", icon = purple("󰡱") },
  { "gt", function() Snacks.picker.lsp_type_definitions() end, "Type Definition", need = "typeDefinition", icon = purple("") },
  { "gCi", function() Snacks.picker.lsp_incoming_calls() end, "Incoming Calls", need = "prepareCallHierarchy", icon = { icon = "󰃺", color = "cyan" } },
  { "gCo", function() Snacks.picker.lsp_outgoing_calls() end, "Outgoing Calls", need = "prepareCallHierarchy", icon = { icon = "󰃷", color = "orange" } },
  { "]]", function() Snacks.words.jump(vim.v.count1) end, "Reference (word)", need = "documentHighlight" },
  { "[[", function() Snacks.words.jump(-vim.v.count1) end, "Reference (word)", need = "documentHighlight" },
  -- A global K also keeps Neovim from mapping K in each buffer a hover server attaches to (runtime lua/vim/lsp.lua)
  { "K", function() vim.lsp.buf.hover() end, "Hover", need = "hover" },
  { "<leader>lr", function() vim.lsp.buf.rename() end, "LSP Rename", need = "rename" },
  { "<leader>cs", "<cmd>Trouble symbols toggle focus=false<cr>", "Symbols (Trouble)", need = "documentSymbol" },
  {
    "<leader>cl",
    "<cmd>Trouble lsp toggle focus=false win.position=right<cr>",
    "LSP Definitions / references / ... (Trouble)",
    need = { "definition", "references", "implementation", "typeDefinition", "declaration", "prepareCallHierarchy" },
  },
  { "<leader>lf", format, "Format buffer", need = "formatter", icon = purple("󱍔") },
  { "<leader>lf", format, "Format selection", mode = "x", need = "range formatter", icon = purple("󱍔") },
  { "<leader>Tf", toggle = formatting.on_save, label = "Format on Save", need = "formatter" },
  { "<leader>xX", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", "Buffer Diagnostics (Trouble)", need = "diagnostics" },
  { "<leader>sd", function() Snacks.picker.diagnostics_buffer() end, "Diagnostics (Buffer)", need = "diagnostics", icon = { icon = "", color = "orange" } },
  { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, "Workspace symbols", need = "workspace/symbol", icon = purple("󱔁") },
  -- Neovim's gr* default is vim.lsp.buf.references; the picker instead (D49: no gr{char} where no server can act)
  { "grr", function() Snacks.picker.lsp_references() end, "References", need = "references", echo = true, icon = purple("") },
})

-- Neovim's own gr* keys are rows in keys/neovim.lua

-- Linked editing: renaming a tag renames its pair, where the server supports it (html, and tsc in JSX/TSX)
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("core.lsp.linked_editing", { clear = true }),
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/linkedEditingRange", ev.buf) then
      vim.lsp.linked_editing_range.enable(true, { client_id = client.id })
    end
  end,
})
