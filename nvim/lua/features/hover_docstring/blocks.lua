-- Step two of the docstring clean-up (features/hover_docstring/init.lua): the items written out as markdown by indent.
-- Each container (a section, an entry, a callout) writes its body one level in, with its own prefix; anything no rule
-- places keeps its indent as U+00A0 (FINDINGS §1.1), which markdown neither strips nor reads as code (R1).
local inline = require("features.hover_docstring.inline").rewrite

local M = {}

local NBSP = "\194\160"

-- Google section headers (§1.4), lower-cased; true for the ones whose items are entries (`name (type): desc`)
local GOOGLE = {
  args = true,
  arguments = true,
  parameters = true,
  params = true,
  ["keyword args"] = true,
  ["keyword arguments"] = true,
  ["other parameters"] = true,
  returns = true,
  ["return"] = true,
  yields = true,
  ["yield"] = true,
  raises = true,
  attributes = true,
  ["important attributes"] = true,
  example = false,
  examples = false,
  note = false,
  notes = false,
  warning = false,
  warnings = false,
  ["see also"] = false,
  references = false,
  todo = false,
}
-- NumPy section titles (§1.9), underlined with dashes; true for the ones whose items are `name : type` entries
local NUMPY = {
  parameters = true,
  ["other parameters"] = true,
  returns = true,
  yields = true,
  receives = true,
  raises = true,
  warns = true,
  attributes = true,
  methods = true,
  warnings = false,
  ["see also"] = false,
  notes = false,
  references = false,
  examples = false,
}
-- reST directives that become callouts (§1.5): the callout type, and a title made from the argument
local CALLOUT = {
  note = { "NOTE" },
  tip = { "TIP" },
  hint = { "HINT" },
  important = { "IMPORTANT" },
  warning = { "WARNING" },
  caution = { "CAUTION" },
  danger = { "DANGER" },
  attention = { "ATTENTION" },
  error = { "ERROR" },
  seealso = { "NOTE", "See also" },
  deprecated = { "WARNING", "Deprecated since" },
  versionadded = { "NOTE", "New in" },
  versionchanged = { "NOTE", "Changed in" },
}
-- Callout types render-markdown draws (render-markdown.nvim lua/render-markdown/settings.lua, callout); MkDocs
-- admonitions of any other type become NOTE (§1.13)
local TYPES = {}
for _, t in ipairs({
  "note",
  "tip",
  "important",
  "warning",
  "caution",
  "abstract",
  "summary",
  "tldr",
  "info",
  "todo",
  "hint",
  "success",
  "check",
  "done",
  "question",
  "help",
  "faq",
  "attention",
  "failure",
  "fail",
  "missing",
  "danger",
  "error",
  "bug",
  "example",
  "quote",
  "cite",
}) do
  TYPES[t] = true
end

--- Output lines with a pending gap: a blank line goes before the next text line
---@class hover_docstring.Out
---@field lines string[]
---@field gap boolean

---@param o hover_docstring.Out
---@param line string
---@param raw? boolean a fence's line: kept even when blank
local function emit(o, line, raw)
  local last = o.lines[#o.lines]
  if line == "" and not raw then
    if last ~= nil and last ~= "" then
      table.insert(o.lines, "")
    end
    return
  end
  -- a line after a quote would be read as its lazy continuation (CommonMark 0.31.2, 5.1): a blank line goes between
  local after_quote = not raw and last and last:match("^%s*>") and not line:match("^%s*>")
  if (o.gap or after_quote) and last ~= nil and last ~= "" then
    table.insert(o.lines, "")
  end
  o.gap = false
  table.insert(o.lines, line)
end

--- Lines with blanks dropped from both ends
---@param lines string[]
local function trim(lines)
  while lines[1] == "" do
    table.remove(lines, 1)
  end
  while lines[#lines] == "" do
    table.remove(lines)
  end
  return lines
end

--- Emits lines inside a container: "> " for a callout (">" on a blank line), "  " for a list item's body
---@param o hover_docstring.Out
---@param lines string[]
---@param prefix string
local function emit_in(o, lines, prefix)
  local blank = prefix:match("^>") and ">" or ""
  for _, l in ipairs(trim(lines)) do
    emit(o, l == "" and blank or prefix .. l, true)
  end
end

--- The end of the body under the item at i: the last item deeper than base, and the first deeper indent. pyrefly's
--- doctest fences keep no indent, so one belongs to a body only when deeper text follows it
---@param items hover_docstring.Item[]
---@param i integer
---@param b integer
---@param base integer
---@return integer?, integer?
local function body(items, i, b, base)
  local last, first
  for k = i + 1, b do
    local it = items[k]
    if it.kind == "text" or (it.kind == "code" and it.n) then
      if it.n <= base then
        break
      end
      last, first = k, first or it.n
    end
  end
  return last, first
end

local function is_numpy_header(items, i)
  local it, under = items[i], items[i + 1]
  return it.kind == "text" and NUMPY[it.s:lower()] ~= nil and under and under.kind == "text" and under.n == it.n and under.s:match("^%-%-%-+$") ~= nil
end

local function is_google_header(it)
  local name = it.s:match("^([%a ]+):$")
  return name and GOOGLE[name:lower()] ~= nil
end

local NAME = "%**[%a_][%w_%.]*"

--- An entry of a Google section: `- `name` (type): desc` (§1.4)
---@param s string
local function google_entry(s)
  if s:match("^[-*+] ") then
    return "- " .. s:sub(3)
  end
  local name, typ, desc = s:match("^(" .. NAME .. ")%s*(%b())%s*:%s*(.*)$")
  if name then
    return ("- `%s` %s:%s"):format(name, typ, desc == "" and "" or " " .. desc)
  end
  name, desc = s:match("^(" .. NAME .. ")%s*:%s*(.*)$")
  if name and not desc:match("^//") then
    return ("- `%s`:%s"):format(name, desc == "" and "" or " " .. desc)
  end
  return "- " .. s, false
end

--- An entry of a NumPy section: `- **name** : type` (§1.9); nil for a line that names nothing
---@param s string
local function numpy_entry(s)
  ---@param text string
  local function names(text)
    for name in vim.gsplit(text, ",%s*") do
      if not name:match("^" .. NAME .. "$") then
        return false
      end
    end
    return true
  end
  local left, right = s:match("^(.-)%s*:%s+(.*)$")
  if left and names(left) then
    return ("- **%s** : %s"):format(left, right)
  end
  if names(s) then
    return ("- **%s**"):format(s)
  end
end

local render

--- The raw lines of items a..b, indented relative to base (a directive's code or math body)
local function raw(items, a, b, base)
  local lines = {}
  for k = a, b do
    local it = items[k]
    if it.kind == "text" then
      table.insert(lines, string.rep(" ", math.max(0, it.n - base)) .. it.s)
    elseif it.kind == "blank" then
      table.insert(lines, "")
    else
      vim.list_extend(lines, it.lines)
    end
  end
  return trim(lines)
end

--- A list-table's rows as `- a: b` lines
---@param lines string[]
local function list_table(lines)
  local rows = {} ---@type string[][]
  for _, l in ipairs(lines) do
    local first = l:match("^%s*%* %- (.*)$")
    local cell = l:match("^%s*%- (.*)$")
    if l:match("^%s*:[%w-]+:") then
      -- an option such as :header-rows:
    elseif first then
      table.insert(rows, { first })
    elseif cell and #rows > 0 then
      table.insert(rows[#rows], cell)
    elseif l:match("%S") and #rows > 0 then
      local row = rows[#rows]
      row[#row] = row[#row] .. " " .. vim.trim(l)
    end
  end
  local out = {}
  for _, row in ipairs(rows) do
    local rest = { unpack(row, 2) }
    table.insert(out, inline("- " .. row[1] .. (#rest > 0 and ": " .. table.concat(rest, " · ") or "")))
  end
  return out
end

--- A callout: a gap, the marker line, its body quoted, a gap
local function callout(o, marker, lines)
  o.gap = true
  emit(o, marker)
  emit_in(o, lines, "> ")
  o.gap = true
end

--- A reST directive at items[i] (§1.5). Returns the index after it
---@param o hover_docstring.Out
---@param items hover_docstring.Item[]
---@param i integer
---@param b integer
---@param name string
---@param arg string
local function directive(o, items, i, b, name, arg)
  local it = items[i]
  -- the body: pyrefly's fence right after a directive with no argument, else the lines deeper than it, with its
  -- options (:noindex:) left out
  local j = i + 1
  while j <= b and items[j].kind == "blank" do
    j = j + 1
  end
  local code = arg == "" and items[j] and items[j].kind == "code" and items[j].from == "literal" and items[j] or nil
  local start, last, first, after = i, nil, nil, i + 1
  if code then
    after = j + 1
  else
    while
      start + 1 <= b
      and (items[start + 1].kind == "blank" or (items[start + 1].kind == "text" and items[start + 1].n > it.n and items[start + 1].s:match("^:[%w-]+:")))
    do
      start = start + 1
    end
    last, first = body(items, start, b, it.n)
    after = (last or start) + 1
  end
  --- the body as prose lines
  local function prose()
    if code then
      local lines = {}
      for _, l in ipairs(code.lines) do
        local sp, rest = l:match("^( *)(.*)$")
        table.insert(lines, rest == "" and "" or (NBSP:rep(#sp) .. inline(rest)))
      end
      return lines
    end
    return last and render(items, start + 1, last, first) or {}
  end
  local function code_lines()
    if code then
      return trim(vim.list_slice(code.lines))
    end
    return last and raw(items, start + 1, last, first) or {}
  end

  local kind = CALLOUT[name]
  if kind then
    local title = kind[2]
    local lines = prose()
    if title and arg ~= "" then
      title = title .. " " .. arg
    elseif arg ~= "" then
      table.insert(lines, 1, inline(arg))
    end
    callout(o, "> [!" .. kind[1] .. "]" .. (title and " " .. title or ""), lines)
  elseif name == "math" or name == "code-block" or name == "code" or name == "sourcecode" then
    local lines = code_lines()
    if name == "math" and arg ~= "" then
      table.insert(lines, 1, arg)
    end
    emit(o, "```" .. (name == "math" and "latex" or arg), true)
    for _, l in ipairs(lines) do
      emit(o, l, true)
    end
    emit(o, "```", true)
  elseif name == "list-table" then
    if arg ~= "" then
      emit(o, "**" .. inline(arg) .. "**")
    end
    o.gap = true
    for _, l in ipairs(list_table(code_lines())) do
      emit(o, l)
    end
    o.gap = true
  elseif name:match("^py:") or ({ method = 1, ["function"] = 1, class = 1, attribute = 1, data = 1 })[name] then
    emit(o, "`" .. arg .. "`")
    o.gap = true
    for _, l in ipairs(prose()) do
      emit(o, l)
    end
  else
    local label = name:gsub("%-", " "):gsub("^%l", string.upper)
    emit(o, "**" .. label .. ":**" .. (arg ~= "" and " " .. inline(arg) or ""))
    if code then
      emit(o, "```", true)
      for _, l in ipairs(code.lines) do
        emit(o, l, true)
      end
      emit(o, "```", true)
    else
      for _, l in ipairs(prose()) do
        emit(o, l)
      end
    end
  end
  return after
end

--- Writes items a..b of a container whose own lines are at indent base. mode "google" or "numpy" makes its lines
--- at base entries of that section kind
---@param items hover_docstring.Item[]
---@param a integer
---@param b integer
---@param base integer
---@param mode? "google"|"numpy"
---@return string[]
function render(items, a, b, base, mode)
  local o = { lines = {}, gap = false } ---@type hover_docstring.Out
  local i = a
  -- whether the last thing written is an entry with no blank line after it
  local open = false
  while i <= b do
    local it = items[i]
    local was_open = open
    open = false
    if it.kind == "blank" then
      emit(o, "")
      i = i + 1
    elseif it.kind == "code" then
      emit(o, "```" .. it.info, true)
      for _, l in ipairs(it.lines) do
        emit(o, l, true)
      end
      emit(o, "```", true)
      i = i + 1
    else
      local s, rel = it.s, math.max(0, it.n - base)
      local dname, darg = s:match("^%.%. ([%a][%w-]*)%s*::?%s*(.-)%s*$")
      local mk, mtype, mtitle = s:match("^([!?][!?][!?]%+?)%s+([%w-]+)%s*(.-)%s*$")
      local gh, ghrest = s:match("^%[!(%u+)%]%s*(.-)%s*$")
      local tip = (s == "<Tip>" and "") or (s == "<Tip warning={true}>" and "warning") or nil
      if rel == 0 and not mode and is_google_header(it) then
        -- §1.4: `**Args:**`, then the section's lines one level in, entries for the sections that hold them
        local name = s:sub(1, -2)
        o.gap = true
        emit(o, "**" .. name .. ":**")
        local last, first = body(items, i, b, it.n)
        if last then
          for _, l in ipairs(trim(render(items, i + 1, last, first, GOOGLE[name:lower()] and "google" or nil))) do
            emit(o, l, true)
          end
          o.gap = true
        end
        i = (last or i) + 1
      elseif rel == 0 and mode ~= "numpy" and is_numpy_header(items, i) then
        -- §1.9: `**Parameters**`, the underline dropped; an entries section runs to the next header
        o.gap = true
        emit(o, "**" .. s .. "**")
        i = i + 2
        if NUMPY[s:lower()] then
          local k = i
          while k <= b and not (items[k].kind == "text" and items[k].n <= it.n and (is_numpy_header(items, k) or is_google_header(items[k]))) do
            k = k + 1
          end
          for _, l in ipairs(trim(render(items, i, k - 1, it.n, "numpy"))) do
            emit(o, l, true)
          end
          o.gap = true
          i = k
        end
      elseif dname and mk == nil then
        i = directive(o, items, i, b, dname:lower(), darg)
      elseif mk and (mk:sub(1, 3) == "!!!" or mk:sub(1, 3) == "???") then
        -- §1.13: an MkDocs admonition, its body the lines deeper than it
        local t = mtype:lower()
        local title = mtitle:match('^"(.*)"$') or mtitle
        local last, first = body(items, i, b, it.n)
        local lines = last and render(items, i + 1, last, first) or {}
        callout(o, "> [!" .. (TYPES[t] and t:upper() or "NOTE") .. "]" .. (title ~= "" and " " .. title or ""), lines)
        i = (last or i) + 1
      elseif gh then
        -- §1.11: a GitHub callout whose `>` pyrefly dropped, quoted to the next blank line
        local lines, k = {}, i + 1
        while k <= b and items[k].kind == "text" do
          table.insert(lines, inline(items[k].s))
          k = k + 1
        end
        callout(o, "> [!" .. gh .. "]" .. (ghrest ~= "" and " " .. ghrest or ""), lines)
        i = k
      elseif s:match("^>") then
        -- a quote pyrefly kept, being indented: its lines as they are, at this level
        o.gap = true
        while i <= b and items[i].kind == "text" and items[i].s:match("^>") do
          emit(o, inline(items[i].s))
          i = i + 1
        end
        o.gap = true
      elseif tip then
        -- §1.12: Hugging Face's <Tip>, to its </Tip>
        local k = i + 1
        while k <= b and not (items[k].kind == "text" and items[k].s == "</Tip>") do
          k = k + 1
        end
        if k > b then
          emit(o, (rel > 0 and NBSP:rep(rel) or "") .. inline(s))
          i = i + 1
        else
          local min = math.huge
          for x = i + 1, k - 1 do
            if items[x].kind == "text" then
              min = math.min(min, items[x].n)
            end
          end
          callout(o, tip == "" and "> [!TIP]" or "> [!WARNING]", render(items, i + 1, k - 1, min == math.huge and 0 or min))
          i = k + 1
        end
      elseif rel == 0 and mode then
        -- an entry, its body two spaces in: a list item's continuation
        local entry, named = nil, false
        if mode == "google" then
          entry, named = google_entry(s)
          named = named ~= false
        else
          entry = numpy_entry(s)
          named = entry ~= nil
        end
        -- a line that names nothing right under an entry is a wrapped line of it, at the entry's own indent
        local wrapped = not named and was_open
        local last, first = body(items, i, b, it.n)
        emit(o, wrapped and "  " .. inline(s) or inline(entry or s))
        if last then
          emit_in(o, render(items, i + 1, last, first), (entry or wrapped) and "  " or "")
        end
        open = entry ~= nil or wrapped
        i = (last or i) + 1
      else
        -- §1.1: indent nothing above places keeps its width as U+00A0
        emit(o, NBSP:rep(rel) .. inline(s))
        i = i + 1
      end
    end
  end
  return trim(o.lines)
end

--- The docstring's items as markdown lines
---@param items hover_docstring.Item[]
---@return string[]
function M.write(items) return render(items, 1, #items, 0) end

return M
