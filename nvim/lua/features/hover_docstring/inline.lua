-- The inline rewrites of the docstring clean-up (features/hover_docstring/init.lua), run on each prose line
-- blocks.lua writes, never on code: FINDINGS §1.10, §1.14 and §1.15.
local M = {}

--- The index of the closing bracket for the `[` at i, skipping code spans; nil if none
---@param s string
---@param i integer
---@param open string
---@param close string
local function matching(s, i, open, close)
  local depth, j = 0, i
  while j <= #s do
    local c = s:sub(j, j)
    if c == "\\" then
      j = j + 1
    elseif c == "`" then
      -- a code span, to its closing run
      local run = s:match("^`+", j)
      local e = s:find(run, j + #run, true)
      if not e then
        return nil
      end
      j = e + #run - 1
    elseif c == open then
      depth = depth + 1
    elseif c == close then
      depth = depth - 1
      if depth == 0 then
        return j
      end
    end
    j = j + 1
  end
end

--- The inline rewrites of a prose line: reST links (§1.15), brackets that aren't links escaped (§1.10), dunders in
--- code spans (§1.14). Code spans, links, autolinks and URLs are left as they are
---@param s string
---@return string
function M.rewrite(s)
  -- §1.15: a reST link, `text <url>`_ or __, which markdown reads as a code span with the URL in it
  s = s:gsub("`([^`<]-)%s*<(%a[%w+.-]*://[^>]+)>`__?", function(text, url) return text == "" and url or ("[" .. text .. "](" .. url .. ")") end)
  if not s:find("[%[%]_]") then
    return s
  end
  local out, i = {}, 1
  while i <= #s do
    local c = s:sub(i, i)
    local keep ---@type integer? the last index of a span kept as it is
    if c == "\\" then
      -- an escape already there
      keep = i + 1
    elseif c == "`" then
      local run = s:match("^`+", i)
      local e = s:find(run, i + #run, true)
      keep = e and e + #run - 1 or i + #run - 1
    elseif c == "[" then
      -- §1.10: a link, a reference link, a doc-builder ref ([`X`]) or a callout marker is kept whole; any other
      -- bracket is a shortcut link to treesitter, whose brackets the highlights query conceals, so it is escaped
      local e = matching(s, i, "[", "]")
      if e then
        local after, inner = s:sub(e + 1, e + 1), s:sub(i + 1, e - 1)
        if after == "(" then
          keep = matching(s, e + 1, "(", ")")
        elseif after == "[" then
          keep = s:find("]", e + 2, true)
        elseif inner:match("^`[^`]+`$") or inner:match("^!%u+$") then
          keep = e
        end
      end
      if not keep then
        table.insert(out, "\\[")
        i = i + 1
      end
    elseif c == "]" then
      table.insert(out, "\\]")
      i = i + 1
    elseif c == "<" then
      -- an autolink
      keep = s:match("^<%a[%w+.-]*:[^%s>]*()>", i) or i
    elseif c == "h" and s:match("^https?://", i) and not s:sub(i - 1, i - 1):match("[%w_]") then
      -- a bare URL, to the next space
      keep = (s:find("[%s]", i) or #s + 1) - 1
    elseif c == "_" and s:sub(i, i + 1) == "__" and not s:sub(i - 1, i - 1):match("[%w_]") then
      -- §1.14: a __dunder__ in prose, which markdown reads as bold, goes in a code span
      local name, e = s:match("^(__%a[%w_]-__)()", i)
      if name and not s:sub(e, e):match("[%w_]") then
        table.insert(out, "`" .. name .. "`")
        i = e
      else
        table.insert(out, c)
        i = i + 1
      end
    else
      local e = s:find("[%[%]`\\<h_]", i + 1) or #s + 1
      table.insert(out, s:sub(i, e - 1))
      i = e
    end
    if keep then
      table.insert(out, s:sub(i, keep))
      i = keep + 1
    end
  end
  return table.concat(out)
end

return M
