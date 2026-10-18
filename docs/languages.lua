-- Renders docs/languages.md, the per-language tool tables, from the language files (nvim/lua/lang/) and the tool
-- catalog (nvim/lua/tools/catalog.lua). `mise run docs` runs this file to rewrite it:
--   nvim --clean --headless -l docs/languages.lua
-- Required as a module (tests/unit/languages_doc_test.lua) it only returns M: M.render() and M.path.
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../nvim/lua/?.lua", here .. "/../nvim/lua/?/init.lua", package.path }, ";")

local catalog = require("tools.catalog")

local M = {}

--- Where the rendered doc lives.
M.path = vim.fs.joinpath(vim.fs.dirname(here), "docs", "languages.md")

---@param s string
local function cell(s) return (s:gsub("|", "\\|")) end

---@param name string
local function code(name) return "`" .. cell(name) .. "`" end

---@param names string[]
---@param fmt? fun(name: string): string
local function list(names, fmt)
  if #names == 0 then
    return "none"
  end
  return table.concat(vim.tbl_map(fmt or code, names), ", ")
end

---@param set table<string, any>
local function sorted(set)
  local keys = vim.tbl_keys(set)
  table.sort(keys)
  return keys
end

--- "server `a`" or "servers `a`, `b`"
---@param word string singular
---@param names string[]
local function labelled(word, names) return word .. (#names > 1 and "s " or " ") .. list(names) end

---@param lines string[]
---@param header string[]
---@param rows string[][]
local function table_lines(lines, header, rows)
  lines[#lines + 1] = "| " .. table.concat(header, " | ") .. " |"
  lines[#lines + 1] = "|" .. string.rep("---|", #header)
  for _, row in ipairs(rows) do
    lines[#lines + 1] = "| " .. table.concat(row, " | ") .. " |"
  end
end

---@param a lang.Answer
local function linters(a)
  return list(a.linters, function(name)
    local server = a.covered_by[name]
    return code(name) .. (server and (" (covered by " .. code(server) .. ")") or "")
  end)
end

---@param lang string
local function lang_link(lang) return ("[%s](../nvim/lua/lang/%s.lua)"):format(lang, lang) end

---@param list_ string[]
---@param item string
local function has(list_, item) return vim.list_contains(list_, item) end

--- The markdown of docs/languages.md.
---@param registry? { of: fun(ft: string): lang.Answer?, views: fun(): lang.Views, filetypes: fun(): string[] } default the language files' (lang)
---@return string
function M.render(registry)
  registry = registry or require("lang")
  local views = registry.views()
  local fts = registry.filetypes()

  -- Base filetypes, per language, grouped where they get the same tools
  local by_lang = {} ---@type table<string, { fts: string[], answer: lang.Answer }[]>
  for _, ft in ipairs(fts) do
    local a = registry.of(ft) --[[@as lang.Answer]]
    if not views.variants[ft] then
      local key = table.concat({ table.concat(a.servers, ","), table.concat(a.formatters, ","), linters(a) }, "|")
      local groups = by_lang[a.lang] or {}
      by_lang[a.lang] = groups
      local group = vim.iter(groups):find(function(g) return g.key == key end)
      if group then
        table.insert(group.fts, ft)
      else
        groups[#groups + 1] = { key = key, fts = { ft }, answer = a }
      end
    end
  end
  local lang_rows = {}
  for _, lang in ipairs(sorted(by_lang)) do
    for _, g in ipairs(by_lang[lang]) do
      local a = g.answer
      lang_rows[#lang_rows + 1] = { lang_link(lang), list(g.fts), list(a.servers), list(a.formatters), linters(a) }
    end
  end

  -- Variants: the files that get each, and what it has that its base lacks
  local rules = {} ---@type table<string, string[]>
  for _, kind in ipairs({ "filename", "pattern" }) do
    local by = views.filetypes[kind] or {}
    for _, key in ipairs(sorted(by)) do
      local target = by[key]
      local ft = type(target) == "table" and target[1] or target --[[@as string]]
      rules[ft] = rules[ft] or {}
      table.insert(rules[ft], kind == "filename" and code(key) or ("pattern " .. code(key)))
    end
  end
  local variant_rows = {}
  for _, ft in ipairs(sorted(views.variants)) do
    local v = views.variants[ft]
    local a = registry.of(ft) --[[@as lang.Answer]]
    local base = registry.of(v.base) or { servers = {}, formatters = {}, linters = {} }
    local own = {}
    local servers = vim.tbl_filter(function(s) return not has(base.servers, s) end, a.servers)
    if #servers > 0 then
      own[#own + 1] = labelled("server", servers)
    end
    if not vim.deep_equal(a.formatters, base.formatters) then
      own[#own + 1] = labelled("formatter", a.formatters) .. (#base.formatters > 0 and (" instead of " .. list(base.formatters)) or "")
    end
    local lints = vim.tbl_filter(function(l) return not has(base.linters, l) end, a.linters)
    if #lints > 0 then
      own[#own + 1] = labelled("linter", lints)
    end
    local files = rules[ft] and table.concat(rules[ft], ", ") or "none set here"
    if v.example then
      files = files .. " (e.g. " .. code(v.example) .. ")"
    end
    variant_rows[#variant_rows + 1] = { code(ft), lang_link(v.lang), files, #own > 0 and table.concat(own, "; ") or "none", cell(v.about) }
  end

  -- Binaries: what each language's tools run, with the catalog's facts about installing it
  local langs_of = {} ---@type table<string, table<string, true>>
  local roles_of = {} ---@type table<string, table<string, true>>
  for _, ft in ipairs(fts) do
    local a = registry.of(ft) --[[@as lang.Answer]]
    local names, roles = catalog.needed(a)
    for _, bin in ipairs(names) do
      langs_of[bin] = langs_of[bin] or {}
      langs_of[bin][a.lang] = true
      roles_of[bin] = roles_of[bin] or {}
      for _, role in ipairs(roles[bin]) do
        roles_of[bin][role] = true
      end
    end
  end
  local bin_rows = {}
  for _, bin in ipairs(sorted(langs_of)) do
    local e = catalog.tools[bin]
    local install = e.spec and code(e.spec) or e.component and ("rustup component " .. code(e.component)) or "the system's"
    if e.min then
      install = install .. (", version %s or later"):format(e.min)
    end
    local provides = {}
    for _, role in ipairs({ { "server", sorted(e.servers or {}) }, { "formatter", e.formatters or {} }, { "linter", e.linters or {} } }) do
      if #role[2] > 0 then
        provides[#provides + 1] = labelled(role[1], role[2])
      end
    end
    for _, role in ipairs(sorted(roles_of[bin])) do
      if role:find("^used by ") then
        provides[#provides + 1] = role
      end
    end
    if e.requires then
      provides[#provides + 1] = "calls " .. list(e.requires)
    end
    if e.run then
      provides[#provides + 1] = "runs as " .. code(e.run)
    end
    bin_rows[#bin_rows + 1] = {
      code(bin),
      install,
      e.project and list(e.project) or "none",
      e.runtime or "none",
      table.concat(provides, "; "),
      list(sorted(langs_of[bin]), function(l) return l end),
    }
  end

  local lines = {
    "# Languages",
    "",
    "<!-- Generated by docs/languages.lua; edit nvim/lua/lang/ or nvim/lua/tools/catalog.lua, then run `mise run docs`. -->",
    "",
    "Generated from the language files (`nvim/lua/lang/`) and the tool catalog (`nvim/lua/tools/catalog.lua`) by",
    "`mise run docs`: don't edit it by hand. Why each tool was chosen is in",
    "[mise-tooling-decisions.md](mise-tooling-decisions.md).",
    "",
    "## Tools by language",
    "",
    "Servers are language servers; formatters run through conform, in the order listed; linters run through nvim-lint.",
    "A linter covered by a server is skipped while that server is attached to the buffer.",
    "",
  }
  table_lines(lines, { "Language", "Filetypes", "Servers", "Formatters", "Linters" }, lang_rows)
  vim.list_extend(lines, {
    "",
    "## File-scoped tools (variants)",
    "",
    "A variant is a dotted filetype that some files of its base filetype get. It has its base's servers and linters plus",
    "its own, and its own formatters if it names any, else its base's. Patterns are Lua patterns matched against the",
    "file's full path.",
    "",
  })
  table_lines(lines, { "Filetype", "Language", "Files", "Its own tools", "About" }, variant_rows)
  vim.list_extend(lines, {
    "",
    "## Binaries",
    "",
    "The binary behind each tool. Project copy: the dirs under a project that may hold the project's own copy, which",
    'is used before mise\'s; CONTRIBUTING.md ("Tools from mise") has the whole order.',
    "",
  })
  table_lines(lines, { "Binary", "Install", "Project copy", "Runtime", "Provides", "Languages" }, bin_rows)
  return table.concat(lines, "\n") .. "\n"
end

-- Run as a script (nvim -l docs/languages.lua): write the file
if arg and arg[0] and vim.fs.abspath(arg[0]) == vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)) then
  local f = assert(io.open(M.path, "w"))
  f:write(M.render())
  f:close()
  print("wrote " .. vim.fs.relpath(vim.fs.dirname(here), M.path))
end

return M
