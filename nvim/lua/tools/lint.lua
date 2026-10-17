-- Which nvim-lint linters run on a buffer: those whose binary the resolver finds, except a linter whose findings a
-- language server also reports while that server is attached. Shared by nvim-lint's spec and the statusline.

local tools = require("tools")

local M = {}

-- Linters whose findings a language server also reports, by server name (covered_by in lua/lang/); each runs only where
-- its server is not attached
M.covering_server = require("lang").views().covered_by

--- Whether linter name's server is attached to buf, so the linter is skipped there.
---@param name string
---@param buf integer
function M.covered(name, buf)
  local server = M.covering_server[name]
  return server ~= nil and #vim.lsp.get_clients({ bufnr = buf, name = server }) > 0
end

--- The binary the resolver looks up for a linter: its catalog binary, else its command when that is a bare name.
---@param name string
---@param linter? lint.Linter|fun(): lint.Linter
---@return string?
function M.binary(name, linter)
  local bin = tools.catalog.binary("linter", name)
  if bin then
    return bin
  end
  linter = linter or require("lint").linters[name]
  if type(linter) == "function" then
    linter = linter()
  end
  local cmd = type(linter) == "table" and linter.cmd
  return type(cmd) == "string" and not cmd:find("/") and cmd or nil
end

--- Whether linter name runs on buf now: not covered by an attached server, and its binary found in root. A binary
--- not resolved yet counts as missing; resolving it starts here, and ToolsChanged says when it is done.
---@param name string
---@param buf integer
---@param root string
---@param linter? lint.Linter|fun(): lint.Linter
function M.runs(name, buf, root, linter)
  local bin = M.binary(name, linter)
  return not M.covered(name, buf) and (not bin or (tools.resolve(bin, root) or {}).path ~= nil)
end

--- The linters that run on buf now, from nvim-lint's own lookup for its filetype (dotted filetypes get each part's).
---@param buf integer
---@return string[]
function M.to_run(buf)
  local ok, lint = pcall(require, "lint")
  if not ok then
    return {}
  end
  local root = tools.root(buf)
  return vim.tbl_filter(function(name) return M.runs(name, buf, root) end, lint._resolve_linter_by_ft(vim.bo[buf].filetype))
end

return M
