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

-- grN: a rename whose edits also fill the quickfix list; the rename handler below reads and clears this
local rename_to_quickfix = false
local function rename_quickfix()
  rename_to_quickfix = true
  -- vim.lsp.buf.rename asks for the name once the server allows the rename; a cancelled prompt renames nothing
  local input = vim.ui.input
  vim.ui.input = function(opts, on_confirm)
    vim.ui.input = input
    return input(opts, function(name)
      if not name or name == "" then
        rename_to_quickfix = false
      end
      on_confirm(name)
    end)
  end
  vim.lsp.buf.rename()
end

--- "a", "a and b", "a, b and c"
---@param names string[]
local function join(names) return #names <= 1 and (names[1] or "") or table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names] end

--- Why K does not hover in buf, where no attached server supports hover (D165 in docs/hover-decisions.md). In a buffer
--- whose language names servers, Vim's K would run 'keywordprg' (pydoc in Python, $VIMRUNTIME/ftplugin/python.vim),
--- which those servers stand in for, so K says what each server is doing instead: not installed, starting, not
--- running, or attached without hover. Nil elsewhere, where K stays Vim's K: a filetype whose language names no
--- servers, one no language declares, and a buffer vim.lsp never attaches servers to. A lookup, run on the press: the
--- language's cached answer, the buffer's cached facts (ui.facts) and its clients.
---@param buf integer
---@return string?
local function no_hover(buf)
  -- vim.lsp's enable handler attaches only to file and help buffers ($VIMRUNTIME/lua/vim/lsp.lua, lsp_enable_callback)
  local buftype = vim.bo[buf].buftype
  local found = (buftype == "" or buftype == "help") and require("lang").of(vim.bo[buf].filetype)
  if not found or #found.servers == 0 then
    return nil
  end
  local tools = require("tools")
  local facts = require("ui.facts").get(buf)
  local missing, starting, stopped, attached = {}, {}, {}, {}
  for _, name in ipairs(found.servers) do
    local bin = tools.catalog.binary("server", name)
    -- an uninitialized client is attached already, but get_clients leaves it out unless asked ($VIMRUNTIME/lua/vim/lsp.lua)
    local live = vim.tbl_filter(function(client) return not client:is_stopped() end, vim.lsp.get_clients({ bufnr = buf, name = name, _uninitialized = true }))
    if vim.iter(live):any(function(client) return client.initialized end) then
      table.insert(attached, name)
    elseif #live > 0 then
      table.insert(starting, name)
    elseif vim.list_contains(facts.missing, bin) then
      table.insert(missing, name)
    elseif bin and not tools.get(bin, facts.root) then
      -- still being looked up: once found, its root_dir starts it
      table.insert(starting, name)
    else
      table.insert(stopped, name)
    end
  end
  local function verb(list, one, more) return #list == 1 and one or more end
  local parts = {}
  if #starting > 0 then
    table.insert(parts, ("%s %s starting"):format(join(starting), verb(starting, "is", "are")))
  end
  if #missing > 0 then
    table.insert(parts, ("%s %s not installed (:Tools install)"):format(join(missing), verb(missing, "is", "are")))
  end
  if #stopped > 0 then
    table.insert(parts, ("%s %s not running (:Tools restart)"):format(join(stopped), verb(stopped, "is", "are")))
  end
  if #attached > 0 then
    table.insert(parts, ("%s %s no hover"):format(join(attached), verb(attached, "has", "have")))
  end
  return table.concat(parts, ", ")
end

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
  -- A global K also keeps Neovim from mapping K in each buffer a hover server attaches to (runtime lua/vim/lsp.lua).
  -- Where none can hover it says why, in a buffer whose language names servers; elsewhere it is Vim's K (D165)
  { "K", function() vim.lsp.buf.hover() end, "Hover", need = "hover", echo = no_hover },
  { "<leader>lr", function() vim.lsp.buf.rename() end, "LSP Rename", need = "rename" },
  { "grN", rename_quickfix, "Rename, edits to quickfix", need = "rename", echo = true },
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

-- A rename as a progress-message while the server works on it (:h LspRequest), so the statusline shows it running
autocmd("LspRequest", {
  group = group,
  callback = function(ev)
    local request = ev.data.request
    if request.method ~= "textDocument/rename" then
      return
    end
    local running = request.type == "pending"
    vim._with(
      { silent = true },
      function()
        vim.api.nvim_echo({ { running and "renaming" or "done" } }, false, {
          id = "lsp.rename." .. ev.data.client_id .. "." .. ev.data.request_id,
          kind = "progress",
          source = "vim.lsp",
          title = "Rename",
          status = running and "running" or "success",
        })
      end
    )
  end,
})

-- After a rename, which files it edited: they are left modified, not written (:wa saves them). A server that has not
-- yet indexed the project (pyrefly a few seconds after it starts) edits only the files it has read, without saying so.
local apply_rename = vim.lsp.handlers["textDocument/rename"]
vim.lsp.handlers["textDocument/rename"] = function(err, result, ctx, config)
  apply_rename(err, result, ctx, config)
  local to_quickfix = rename_to_quickfix
  rename_to_quickfix = false
  if err or not result then
    return
  end
  local files, edits = {}, {} ---@type table<string, true>, { uri: string, range: lsp.Range }[]
  for uri, changes in pairs(result.changes or {}) do
    files[uri] = true
    for _, edit in ipairs(changes) do
      edits[#edits + 1] = { uri = uri, range = edit.range }
    end
  end
  for _, change in ipairs(result.documentChanges or {}) do
    if change.textDocument then
      files[change.textDocument.uri] = true
      for _, edit in ipairs(change.edits) do
        edits[#edits + 1] = { uri = change.textDocument.uri, range = edit.range }
      end
    end
  end
  if to_quickfix then
    -- the edits' start positions, in the text as renamed; the line's text from its buffer, which the rename loaded
    local items = vim.tbl_map(function(edit)
      local buf = vim.uri_to_bufnr(edit.uri)
      local lnum = edit.range.start.line
      return {
        bufnr = buf,
        lnum = lnum + 1,
        col = edit.range.start.character + 1,
        text = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1],
      }
    end, edits)
    table.sort(items, function(a, b)
      if a.bufnr ~= b.bufnr then
        return a.bufnr < b.bufnr
      end
      return a.lnum < b.lnum or a.lnum == b.lnum and a.col < b.col
    end)
    vim.fn.setqflist({}, " ", { title = "Rename", items = items })
    vim.cmd("botright copen")
  end
  local names = vim.tbl_map(function(uri) return vim.fn.fnamemodify(vim.uri_to_fname(uri), ":~:.") end, vim.tbl_keys(files))
  vim.notify(
    ("Renamed %d occurrences in %d files (unsaved, :wa writes them):\n%s"):format(#edits, #names, table.concat(names, "\n")),
    vim.log.levels.INFO,
    { title = "Rename" }
  )
end

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

-- Inlay hints from every server that has them (vim.lsp.inlay_hint, off per buffer by default); a server that has none
-- is never asked. Which hints a server sends is its own setting, in its language file (D162 in
-- docs/inlay-hints-decisions.md); <leader>Th turns them off in a buffer
vim.lsp.inlay_hint.enable(true)
