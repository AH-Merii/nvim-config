-- docs/languages.md, generated from the language files: the committed file is current, and what the generator renders
-- holds every language's tools: nvim --clean --headless -l tests/unit/languages_doc_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local lang = require("lang")
local doc = dofile(here .. "/../../docs/languages.lua")

--- The table row whose first cell is first and second cell contains second, or nil.
---@param md string
---@param first string
---@param second string
local function row(md, first, second)
  for line in vim.gsplit(md, "\n") do
    local cells = vim.split(line, " | ", { plain = true })
    if line:sub(1, 2) == "| " and vim.trim(cells[1]:sub(3)) == first and (cells[2] or ""):find(second, 1, true) then
      return line
    end
  end
end

h.case("the committed docs/languages.md is what the generator renders from nvim/lua/lang/", function()
  local f = io.open(doc.path)
  h.ok(f, "docs/languages.md is missing: run `mise run docs`")
  local committed = f:read("*a")
  f:close()
  local rendered = doc.render()
  if committed ~= rendered then
    local want, got = vim.split(rendered, "\n"), vim.split(committed, "\n")
    local i = 1
    while want[i] == got[i] do
      i = i + 1
    end
    error(
      (
        "docs/languages.md is out of date with nvim/lua/lang/ or the tool catalog: run `mise run docs`, then commit it.\n"
        .. "    first difference, line %d\n    file:      %s\n    generated: %s"
      ):format(i, got[i] or "(end)", want[i] or "(end)")
    )
  end
end)

h.case("the render names every filetype and every server, formatter and linter a language uses", function()
  local md = doc.render()
  local fts = lang.filetypes()
  h.ok(vim.list_contains(fts, "python") and vim.list_contains(fts, "yaml.github-actions"), "the languages include python and yaml.github-actions")
  h.ok(row(md, "[python](../nvim/lua/lang/python.lua)", "`python`"), "a python row:\n" .. md)
  local missing = {}
  for _, ft in ipairs(fts) do
    local a = lang.of(ft) --[[@as lang.Answer]]
    for _, name in ipairs(vim.list_extend({ ft }, vim.list_extend(vim.list_extend(vim.list_extend({}, a.servers), a.formatters), a.linters))) do
      if not md:find("`" .. name .. "`", 1, true) then
        missing[#missing + 1] = ft .. ": " .. name
      end
    end
  end
  h.eq(missing, {}, "names the render lacks")
end)

-- A fixture language: a variant's row names what it adds over its base, and a covered linter names its server
local fixture = lang._from({
  alpha = {
    filetypes = { "alpha" },
    servers = { aserver = {} },
    formatters = { "afmt" },
    linters = { alint = { covered_by = "aserver" } },
    variants = {
      ["alpha.own"] = {
        about = "own files",
        match = { filename = { "own.alpha" } },
        example = "sub/own.alpha",
        formatters = { "ofmt" },
        linters = { olint = {} },
      },
      ["alpha.same"] = { about = "nothing of its own" },
    },
  },
})

h.case("a covered linter's cell names the server that covers it", function()
  local line = row(doc.render(fixture), "[alpha](../nvim/lua/lang/alpha.lua)", "`alpha`")
  h.ok(line and line:find("`alint` (covered by `aserver`)", 1, true), "alpha's row: " .. tostring(line))
end)

h.case("a variant's row lists the files that get it and only the tools its base lacks", function()
  local md = doc.render(fixture)
  local own = row(md, "`alpha.own`", "alpha")
  h.ok(own, "an alpha.own row:\n" .. md)
  h.ok(own:find("`own.alpha`", 1, true), "alpha.own's files: " .. own)
  h.ok(own:find("formatter `ofmt` instead of `afmt`", 1, true), "alpha.own's formatter replaces its base's: " .. own)
  h.ok(own:find("linter `olint`", 1, true), "alpha.own's own linter: " .. own)
  h.ok(not own:find("alint", 1, true) and not own:find("aserver", 1, true), "alpha.own's row repeats its base's tools: " .. own)
  local same = row(md, "`alpha.same`", "alpha")
  h.ok(same and same:find("| none set here | none |", 1, true), "alpha.same has no files or tools of its own: " .. tostring(same))
end)

h.finish()
