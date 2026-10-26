-- Cleans the docstring in pyrefly's hover markdown before Neovim draws it (docs/hover-docstrings-decisions.md, D166).
-- pyrefly rewrites a docstring itself (crates/pyrefly_python/src/docstring.rs at 1.4.0): each leading space becomes
-- `&nbsp;`, which render-markdown's conceallevel 3 hides; a doctest's fence closes before its output; a `::` block or
-- directive body goes in a bare fence; a leading `>` is dropped; every line ends in a hard break. This undoes those and
-- turns the docstring conventions (Google and NumPy sections, reST directives, MkDocs admonitions, GitHub callouts,
-- Hugging Face's <Tip>) into the markdown render-markdown draws. "FINDINGS §1.x" and "R<n>" in these files are the
-- rules and risks listed in docs/hover-docstrings-decisions.md (D166), from the hover corpus that was studied.
--
-- Two linear steps: fences.lua turns the lines into items, every fence resolved first, so nothing inside a fence is
-- rewritten; blocks.lua writes the items out by indent, each container (a section, an entry, a callout) writing its
-- body one level in, and runs inline.lua on each prose line. This file finds the docstring in the hover and gives the
-- input back when the output's fences don't balance or anything raises.
local fences = require("features.hover_docstring.fences")
local blocks = require("features.hover_docstring.blocks")

local M = {}

--- Whether every fence in lines closes, read through list and quote prefixes (FINDINGS R5)
---@param lines string[]
---@return boolean
function M.balanced(lines)
  local run ---@type string?
  for _, l in ipairs(lines) do
    local s = l:gsub("^[%s>]*", "")
    if run then
      if fences.closes(s, run) then
        run = nil
      end
    else
      run = fences.opener(s)
    end
  end
  return run == nil
end

--- pyrefly's hover markdown with its docstring cleaned; the input itself when it has no docstring, or when the
--- clean-up fails or leaves a fence open
---@param value string
---@return string
function M.clean(value)
  local ok, out = pcall(M._clean, value)
  return ok and out or value
end

---@param value string
---@return string
function M._clean(value)
  local L = vim.split(value, "\n", { plain = true })
  -- pyrefly's hover (pyrefly/lib/lsp/wasm/hover.rs at 1.4.0, HoverValue::format): the signature fence, maybe a
  -- `**Type source**` section, then `---` and the docstring, maybe `---` and `**Parameter `x`**`, then the
  -- `Go to` links
  if L[1] ~= "```python" then
    return value
  end
  local s = 2
  while s <= #L and L[s] ~= "```" do
    s = s + 1
  end
  while s <= #L and not (L[s] == "---" and L[s + 1] ~= "**Type source**") do
    s = s + 1
  end
  if s >= #L then
    return value
  end
  local e = #L
  if L[e]:match("^Go to %[") and L[e - 1] == "" then
    e = e - 2
  end
  for k = s + 1, e - 1 do
    if L[k] == "---" and L[k + 1] and L[k + 1]:match("^%*%*Parameter `") and L[k - 1] == "" then
      e = k - 2
      break
    end
  end
  local doc = {}
  for k = s + 1, e do
    local line = L[k]
    -- §1.2: pyrefly's hard break on every line
    table.insert(doc, line:sub(-2) == "  " and line:sub(1, -3) or line)
  end
  local items = fences.items(doc)
  if not items then
    return value
  end
  local cleaned = blocks.write(items)
  if not M.balanced(cleaned) then
    return value
  end
  local out = vim.list_slice(L, 1, s)
  vim.list_extend(out, cleaned)
  vim.list_extend(out, L, e + 1, #L)
  return table.concat(out, "\n")
end

return M
