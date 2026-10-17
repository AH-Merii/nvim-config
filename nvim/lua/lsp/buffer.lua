-- What servers give a buffer: the LSP keys and toggles, which act where an attached client supports their method
-- (lua/keys/), linked editing, progress messages, colour marks and code lenses. lsp/init.lua starts the servers.
local keys = require("keys")

-- Loaded here, at startup, so their plans are dropped on attach, detach and ToolsChanged before any other handler
-- reads them (the statusline's)
local formatting, linting = require("format"), require("linting")

-- A formatter the filetype's language names, installed or not, or an attached client that formats (a range, for a
-- selection)
keys.need("formatter", function(buf) return formatting.has(buf) end)
keys.need("range formatter", function(buf) return formatting.has(buf, true) end)

local function format() formatting.buffer() end

local key = keys.feature("lsp")
local PURPLE = "purple"
---@param icon string
local function purple(icon) return { icon = icon, color = PURPLE } end

key({
  { "<leader>l", group = "LSP", mode = { "n", "x" }, icon = purple("󱍔") },
  { "<leader>c", group = "LSP (Trouble)", icon = purple("󰙎") },
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
  { "<leader>sS", function() Snacks.picker.lsp_workspace_symbols() end, "Workspace symbols", need = "workspace/symbol", icon = purple("󱔁") },
  -- Neovim's gr* default is vim.lsp.buf.references; the picker instead (D49: no gr{char} where no server can act)
  { "grr", function() Snacks.picker.lsp_references() end, "References", need = "references", echo = true, icon = purple("") },
})

-- Neovim's own gr* keys are rows in keys/neovim.lua

-- Its toggles, once snacks is loaded: a press flips one, says so, and its label in the popup follows it
require("features").at_very_lazy(function()
  local hide_show = { enabled = "Hide ", disabled = "Show " }
  require("keys").feature("lsp")({
    { "<leader>Th", toggle = Snacks.toggle.inlay_hints({ wk_desc = hide_show }), need = "inlayHint" },
    {
      "<leader>Tc",
      toggle = Snacks.toggle.new({
        name = "Code Lens",
        get = function() return vim.lsp.codelens.is_enabled({ bufnr = 0 }) end,
        set = function(state) vim.lsp.codelens.enable(state, { bufnr = 0 }) end,
        wk_desc = hide_show,
      }),
      need = "codeLens",
    },
    {
      "<leader>Te",
      toggle = Snacks.toggle.new({
        name = "Type Errors",
        get = function()
          local client = vim.lsp.get_clients({ bufnr = 0, name = "pyrefly" })[1]
          return client ~= nil and require("lsp.pyrefly").type_errors(client)
        end,
        set = function(state)
          for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0, name = "pyrefly" })) do
            require("lsp.pyrefly").type_errors(client, state)
          end
        end,
        wk_desc = hide_show,
      }),
      need = "client:pyrefly",
    },
  })
end)

local autocmd = vim.api.nvim_create_autocmd
local group = vim.api.nvim_create_augroup("lsp.buffer", { clear = true })

-- Linked editing: renaming a tag renames its pair, where the server supports it (html, and tsc in JSX/TSX)
autocmd("LspAttach", {
  group = group,
  callback = function(ev)
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client and client:supports_method("textDocument/linkedEditingRange", ev.buf) then
      vim.lsp.linked_editing_range.enable(true, { client_id = client.id })
    end
  end,
})

-- LSP progress as progress-messages, so vim.ui.progress_status() (in the statusline) counts it (:h LspProgress).
-- Silent: the Progress event still fires but no message is drawn, so the statusline is the one place it shows.
autocmd("LspProgress", {
  group = group,
  callback = function(ev)
    local value = ev.data.params.value
    if type(value) ~= "table" or not value.kind then
      return
    end
    local opts = {
      id = "lsp." .. ev.data.client_id .. "." .. tostring(ev.data.params.token),
      kind = "progress",
      source = "vim.lsp",
      title = value.title,
      status = value.kind ~= "end" and "running" or "success",
      percent = value.percentage,
    }
    vim._with({ silent = true }, function() vim.api.nvim_echo({ { value.message or "done" } }, false, opts) end)
  end,
})

-- Language servers' colors (vim.lsp.document_color, on by default, redrawn on edits only), drawn as a palette
-- symbol at the line's end in the color instead of the built-in's background
local color_ns = vim.api.nvim_create_namespace("config.document_color")
local drawn = {} ---@type table<integer, integer> buffer -> the version its marks are for
vim.lsp.document_color.enable(true, nil, {
  style = function(buf, range, hex)
    -- called for each color once per buffer version, after the built-in clears its own marks
    local version = vim.lsp.util.buf_versions[buf]
    if drawn[buf] ~= version then
      vim.api.nvim_buf_clear_namespace(buf, color_ns, 0, -1)
      drawn[buf] = version
    end
    local hl = "LspDocumentColorSymbol_" .. hex:sub(2)
    vim.api.nvim_set_hl(0, hl, { fg = hex, default = true })
    vim.api.nvim_buf_set_extmark(buf, color_ns, range.start_row, range.start_col, {
      virt_text = { { " \u{E22B}", hl } },
      virt_text_pos = "eol",
      strict = false,
    })
  end,
})
-- the built-in clears only its own marks when a server goes
autocmd("LspDetach", {
  group = group,
  callback = function(ev)
    vim.api.nvim_buf_clear_namespace(ev.buf, color_ns, 0, -1)
    drawn[ev.buf] = nil
  end,
})

-- Code lenses from every server that has them, drawn as lines above their line (vim.lsp.codelens, off per buffer
-- by default); <leader>Tc turns them off in a buffer
vim.lsp.codelens.enable(true)
