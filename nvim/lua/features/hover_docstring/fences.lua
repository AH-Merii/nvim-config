-- Step one of the docstring clean-up (features/hover_docstring/init.lua): the docstring's lines become items, every
-- fence resolved first, so no later rule rewrites what is inside one (FINDINGS R2). pyrefly's own fences are told from
-- an author's by what pyrefly emits (crates/pyrefly_python/src/docstring.rs at 1.4.0): a doctest fence is exactly
-- "```python" before a prompt, a `::` block exactly "```" after the line it took a colon from.
local M = {}

local ENTITY = "&nbsp;"

---@class hover_docstring.Item
---@field kind "text"|"blank"|"code"
---@field n? integer indent in `&nbsp;`s; nil for pyrefly's doctest fences, which keep no indent
---@field s? string a text line after its indent
---@field info? string a fence's info string
---@field from? "doctest"|"literal"|"author"
---@field lines? string[] a fence's lines

--- The leading `&nbsp;`s of line and the rest
---@param line string
---@return integer, string
local function split_indent(line)
  local n, i = 0, 1
  while line:sub(i, i + 5) == ENTITY do
    n, i = n + 1, i + 6
  end
  return n, line:sub(i)
end

--- A doctest prompt as pyrefly tells one (docstring.rs, is_doctest_prompt)
---@param s string?
local function is_prompt(s)
  if not s then
    return false
  end
  return (s:sub(1, 3) == ">>>" and s:sub(4, 4) ~= ">") or (s:sub(1, 3) == "..." and s:sub(4, 4) ~= ".")
end

--- An opening fence's marker run and info string
---@param s string
---@return string?, string?
local function opener(s)
  local run, info = s:match("^(```+)%s*([^`]*)$")
  if not run then
    run, info = s:match("^(~~~+)%s*(.*)$")
  end
  return run, info and vim.trim(info)
end

---@param s string
---@param run string
local function closes(s, run)
  local r = s:match(run:sub(1, 1) == "`" and "^(`+)%s*$" or "^(~+)%s*$")
  return r ~= nil and #r >= #run
end

local function is_fence(s) return s:match("^%s*```") ~= nil or s:match("^%s*~~~") ~= nil end

--- Adds a doctest's output to its fence: `&nbsp;` back to spaces, dedented by the output's smallest indent (§1.3)
---@param into string[]
---@param out string[]
local function add_output(into, out)
  local min = math.huge
  local split = {}
  for k, line in ipairs(out) do
    local n, s = split_indent(line)
    split[k] = { n, s }
    min = math.min(min, n)
  end
  for _, p in ipairs(split) do
    table.insert(into, string.rep(" ", p[1] - min) .. p[2])
  end
end

--- pyrefly's doctest fence opening at L[i]: its prompts, then the output pyrefly left after the closer, up to the next
--- blank line (doctest's rule), and the next doctest right after it in the same fence. Returns the index after it
---@param L string[]
---@param i integer
---@param code hover_docstring.Item
---@return integer
local function read_doctest(L, i, code)
  i = i + 1
  while true do
    while i <= #L and L[i] ~= "```" do
      table.insert(code.lines, L[i])
      i = i + 1
    end
    i = i + 1
    local last = code.lines[#code.lines]
    -- a blank line before the closer: prose follows, not output
    if i > #L or last == nil or last == "" then
      return i
    end
    local out = {}
    while i <= #L and L[i] ~= "" and not is_fence(L[i]) do
      table.insert(out, L[i])
      i = i + 1
    end
    add_output(code.lines, out)
    if not (L[i] == "```python" and is_prompt(L[i + 1])) then
      return i
    end
    i = i + 1
  end
end

--- An author's fence (or pyrefly's `::` block) whose body starts at L[i], opened with run at indent: its lines with
--- `&nbsp;` back to spaces (§1.6, §1.7), and pyrefly's own doctest fences inside it dropped (§1.8). Returns the index
--- after its closer, nil when it never closes
---@param L string[]
---@param i integer
---@param code hover_docstring.Item
---@param run string
---@param indent integer
---@return integer?
local function read_fence(L, i, code, run, indent)
  local inner = false
  while i <= #L do
    local line = L[i]
    if inner then
      if line == "```" then
        inner = false
      else
        table.insert(code.lines, line)
      end
    elseif line == "```python" and is_prompt(L[i + 1]) then
      inner = true
    else
      local n, s = split_indent(line)
      if n <= indent and closes(s, run) then
        return i + 1
      end
      table.insert(code.lines, string.rep(" ", math.max(0, n - indent)) .. s)
    end
    i = i + 1
  end
end

--- The docstring's lines as items, fences resolved; nil when a fence never closes
---@param L string[]
---@return hover_docstring.Item[]?
local function to_items(L)
  local items = {} ---@type hover_docstring.Item[]
  local i = 1
  while i <= #L do
    local line = L[i]
    local n, s = split_indent(line)
    local run, info = opener(s)
    if n == 0 and line == "```python" and is_prompt(L[i + 1]) then
      local code = { kind = "code", info = "python", from = "doctest", lines = {} }
      i = read_doctest(L, i, code)
      table.insert(items, code)
    elseif run then
      -- pyrefly's `::` block: a bare fence after the line it took a colon from. Its indent is one past that line's,
      -- so it stays in the line's section
      local prev
      for k = #items, 1, -1 do
        if items[k].kind ~= "blank" then
          prev = items[k]
          break
        end
      end
      local literal = n == 0 and s == "```" and prev and prev.kind == "text" and prev.s:match(":$")
      local code = {
        kind = "code",
        info = (info:gsub("%s*{.*}$", "")),
        n = literal and prev.n + 1 or n,
        from = literal and "literal" or "author",
        lines = {},
      }
      i = read_fence(L, i + 1, code, run, n)
      if not i then
        return nil
      end
      table.insert(items, code)
    elseif s == "" then
      table.insert(items, { kind = "blank" })
      i = i + 1
    else
      table.insert(items, { kind = "text", n = n, s = s })
      i = i + 1
    end
  end
  return items
end

M.split_indent, M.opener, M.closes = split_indent, opener, closes

--- The docstring's lines as items, fences resolved; nil when a fence never closes (FINDINGS R5)
M.items = to_items

return M
