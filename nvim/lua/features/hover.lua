-- Hover: render-markdown.nvim draws the markdown of the LSP floats (K's hover, signature help), and only of nofile
-- buffers, never of the markdown files you edit (docs/hover-decisions.md, D159). It loads with the first such float.
-- Its docstring clean-up for pyrefly's hover is features/hover_docstring/ (D166, docs/hover-docstrings-decisions.md).
local M = {}

-- The servers whose hover markdown is cleaned before Neovim draws it, and the clean-up for each: the module undoes
-- what pyrefly's own docstring formatter does (D166 in docs/hover-docstrings-decisions.md)
local CLEAN = { pyrefly = "features.hover_docstring" }

--- Cleans client's hover results before the handler that asked for them sees them: vim.lsp.buf.hover's (runtime
--- lua/vim/lsp/buf.lua, M.hover), which converts them with convert_input_to_markdown_lines and opens the float, or
--- any other. hover() takes no handler and no middleware, so the client's request method is wrapped, once per client
---@param client vim.lsp.Client
---@param module string
local function clean_hovers(client, module)
  if client._hover_cleaned then
    return
  end
  client._hover_cleaned = true
  local request = client.request
  ---@diagnostic disable-next-line: duplicate-set-field
  client.request = function(self, method, params, handler, bufnr)
    if method == "textDocument/hover" and handler then
      local inner = handler
      handler = function(err, result, ...)
        local contents = type(result) == "table" and result.contents
        if type(contents) == "table" and contents.kind == "markdown" and type(contents.value) == "string" then
          contents.value = require(module).clean(contents.value)
        end
        return inner(err, result, ...)
      end
    end
    return request(self, method, params, handler, bufnr)
  end
end

--- Whether render-markdown renders buf: a nofile buffer, as every float vim.lsp.util.open_floating_preview opens is
--- (runtime lua/vim/lsp/util.lua: nvim_create_buf(false, true), then filetype markdown). Exactly nofile, as for spell
--- and linting (features/editing.lua, linting/init.lua)
---@param buf integer
local function rendered(buf) return vim.bo[buf].buftype == "nofile" end

--- Sizes an LSP float to its text once render-markdown has first drawn it, placed again as Neovim places one
--- (vim.lsp.util.make_floating_popup_options). render-markdown's own fix takes the lines it conceals off the height but
--- not the virtual lines it adds, a table's borders and wrapped cells, so a float with a table was cut short
--- (lua/render-markdown/lib/compat.lua, fix_lsp_window)
---@param win integer
local function fit(win)
  -- Only before the float is focused: the cursor is still in the window it was placed from
  if not vim.api.nvim_win_is_valid(win) or vim.w[win].lsp_floating_bufnr == nil or vim.w[win].hover_fitted then
    return
  end
  local current = vim.api.nvim_get_current_win()
  if current == win then
    return
  end
  vim.w[win].hover_fitted = true
  -- Placed at the cursor, which Neovim reports as relative to the window the cursor was in
  local float = vim.api.nvim_win_get_config(win)
  local at_cursor = float.relative == "cursor" or (float.relative == "win" and float.win == current)
  local text = vim.api.nvim_win_text_height(win, {}).all
  if not at_cursor or text == vim.api.nvim_win_get_height(win) then
    return
  end
  local border = type(float.border) == "table" and #float.border > 0 and float.border or "none"
  local placed = vim.lsp.util.make_floating_popup_options(vim.api.nvim_win_get_width(win), text, { border = border })
  vim.api.nvim_win_set_config(win, { relative = "cursor", anchor = placed.anchor, row = placed.row, col = placed.col, height = placed.height })
end

M.plugins = {
  {
    src = "MeanderingProgrammer/render-markdown.nvim",
    -- No phase loads it: the first markdown float does (setup below), or a module of it required first (snacks'
    -- markdown previews require it, snacks/picker/util/markdown.lua)
    phase = "on_demand",
    init = function()
      -- Its plugin/ file passes this to setup(), then attaches the current buffer (plugin/render-markdown.lua:6-10),
      -- so it is set before it loads: a setup() call from this spec's setup would come after that attach. ignore keeps
      -- it from attaching to a buffer at all, so a markdown file gets none of its autocmds (lua/render-markdown/core/
      -- manager.lua, should_attach); the nofile defaults stay (overrides.buftype.nofile: every mode, no signs)
      vim.g.render_markdown_config = {
        ignore = function(buf) return not rendered(buf) end,
        on = { render = function(ctx) fit(ctx.win) end },
      }
    end,
  },
}

function M.setup()
  local group = vim.api.nvim_create_augroup("features.hover", { clear = true })
  -- The first markdown float loads render-markdown, which attaches the current buffer as it loads: the float, whose
  -- FileType this is. Its own FileType handler attaches the floats after it, so this one goes. A plugin that failed to
  -- install was reported at startup, and the floats stay as Neovim draws them
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "markdown",
    callback = function(ev)
      if not rendered(ev.buf) then
        return
      end
      pcall(require, "render-markdown")
      return true
    end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client and CLEAN[client.name] then
        clean_hovers(client, CLEAN[client.name])
      end
    end,
  })
end

return M
