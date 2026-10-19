-- The languages: one data file per language next to this one (python.lua, go.lua, ...) holds its filetypes,
-- servers and their settings, formatters, linters, variants and buffer options. Only how to install a binary stays in
-- tools/catalog.lua: a language names a server, formatter or linter, and the catalog gives its binary.
--
-- This module turns the files into one answer per filetype (M.of) and into the tables each plugin wants (M.views), so
-- conform, nvim-lint, vim.lsp.config and nvim-treesitter get explicit tables, and every reader, nvim-lint's runs
-- included, asks M.of. A mistake in a file, such as two languages declaring one filetype, skips that declaration and is
-- reported once (M.problems), rather than stopping init.lua. The variant rule: a variant (a dotted filetype, yaml.github-actions) gets its base's
-- servers and linters plus its own, and its own formatters if it names any, else its base's.

---@class lang.Spec
---@field filetypes string[] where everything below applies, unless an item names its own filetypes
---@field servers? table<string, lang.Server> nvim-lspconfig's name -> fields merged over nvim-lspconfig's config
---@field formatters? lang.Formatters conform names, run in order
---@field linters? table<string, lang.Linter> nvim-lint names
---@field variants? table<string, lang.Variant> dotted filetype -> what it adds to its base, the first part
---@field options? table<string, any> buffer options set on FileType
---@field keys? lang.Keys buffer-local key rows (keys.language), e.g. labels for the runtime ftplugin's maps

---@class lang.Keys: keys.Row[]
---@field filetypes? string[] where they apply instead of the language's filetypes; a dotted filetype gets its parts'

---@class lang.Server: vim.lsp.Config
---@field filetypes? string[] where it attaches instead of the language's filetypes; their variants get it too

---@class lang.Formatters: string[]
---@field filetypes? string[] where they run instead of the language's filetypes

---@class lang.Linter
---@field covered_by? string a server that reports the same findings; the linter is skipped while that server is attached
---@field filetypes? string[] where it runs instead of the language's filetypes

---@class lang.Variant
---@field about string which files get it, and why
---@field match? { filename?: string[], pattern?: table<string, { priority?: number }> } rules for vim.filetype.add
---@field example? string a path the match rules give this filetype; required with match
---@field servers? string[] servers it adds to its base's, configured where a language's servers name them
---@field formatters? string[] used instead of its base's
---@field linters? table<string, lang.Linter> added to its base's

---@class lang.Answer
---@field lang string the language file that declares the filetype
---@field base? string a variant's base filetype
---@field servers string[] sorted
---@field formatters string[] in the order they run
---@field linters string[] its base's, then its own
---@field covered_by table<string, string> linter -> the server that covers it
---@field tools string[] catalog binaries of the servers, formatters and linters, in that order
---@field options? table<string, any>

---@class lang.Views
---@field conform table<string, string[]> conform's formatters_by_ft
---@field lint table<string, string[]> nvim-lint's linters_by_ft
---@field lsp table<string, vim.lsp.Config> server -> the fields for vim.lsp.config, filetypes included
---@field filetypes vim.filetype.add.filetypes the variants' match rules
---@field covered_by table<string, string> linter -> the server that covers it
---@field variants table<string, { lang: string, base: string, about: string, example?: string }>
---@field keys table<string, keys.Row[]> filetype -> its language's key rows, for keys.language

---@class lang.Registry
---@field of fun(ft: string): lang.Answer?
---@field views fun(): lang.Views
---@field filetypes fun(): string[]
---@field problems string[] what was skipped because it conflicts with an earlier declaration, one message each
---@field setup fun()

local catalog = require("tools.catalog")

local M = {}

local dir = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))

-- Plain loops rather than vim.list_contains and vim.tbl_keys, which validate their arguments: this runs at startup

---@param list any[]
---@param item any
local function add(list, item)
  for _, x in ipairs(list) do
    if x == item then
      return
    end
  end
  list[#list + 1] = item
end

---@param set table<string, any>
local function sorted(set)
  local list = {}
  for k in pairs(set) do
    list[#list + 1] = k
  end
  table.sort(list)
  return list
end

---@param answer { servers: table<string, true>, formatters: string[], linters: string[], covered_by: table<string, string> }
local function finish(answer)
  answer.servers = sorted(answer.servers)
  local tools = {}
  for _, role in ipairs({ { "server", answer.servers }, { "formatter", answer.formatters }, { "linter", answer.linters } }) do
    for _, name in ipairs(role[2]) do
      add(tools, catalog.binary(role[1], name) or name)
    end
  end
  answer.tools = tools
  return answer
end

--- A registry over specs, language name -> its spec. Languages and their variants are read in name order; a
--- declaration that conflicts with an earlier one is skipped, and problems says so.
---@param specs table<string, lang.Spec>
---@param problems? string[] earlier problems, e.g. language files that did not load
---@return lang.Registry
function M._from(specs, problems)
  problems = problems or {}
  local reported = {} ---@type table<string, true>
  local function problem(msg, ...)
    msg = msg:format(...)
    if not reported[msg] then
      reported[msg] = true
      problems[#problems + 1] = msg
    end
  end

  local names = sorted(specs)
  local owner = {} ---@type table<string, string> filetype -> language
  local raw = {} ---@type table<string, table> filetype -> its answer before finish
  local configs = {} ---@type table<string, { lang: string, config: lang.Server }>
  local views = { conform = {}, lint = {}, lsp = {}, filetypes = { filename = {}, pattern = {} }, covered_by = {}, variants = {}, keys = {} } ---@type lang.Views

  --- The answer being built for ft, or nil when another language declared ft first.
  ---@param lang string
  ---@param ft string
  local function entry(lang, ft)
    if owner[ft] and owner[ft] ~= lang then
      problem("lang.%s: filetype %s is already declared by lang.%s; lang.%s's declarations for it are skipped", lang, ft, owner[ft], lang)
      return nil
    end
    owner[ft] = lang
    raw[ft] = raw[ft] or { lang = lang, servers = {}, formatters = {}, linters = {}, covered_by = {}, options = specs[lang].options }
    return raw[ft]
  end

  ---@param linters table<string, lang.Linter>
  ---@param lang string
  local function covering(linters, lang)
    for _, name in ipairs(sorted(linters)) do
      local server = linters[name].covered_by
      if server and views.covered_by[name] and views.covered_by[name] ~= server then
        problem("lang.%s: linter %s is covered by %s here and by %s earlier; %s is kept", lang, name, server, views.covered_by[name], views.covered_by[name])
      elseif server then
        views.covered_by[name] = server
      end
    end
  end

  -- Base filetypes
  for _, lang in ipairs(names) do
    local spec = specs[lang]
    for _, ft in ipairs(spec.filetypes) do
      entry(lang, ft)
    end
    for _, name in ipairs(sorted(spec.servers or {})) do
      local config = spec.servers[name]
      if configs[name] then
        problem("lang.%s: server %s is already configured by lang.%s; this one is skipped", lang, name, configs[name].lang)
      else
        configs[name] = { lang = lang, config = config }
        for _, ft in ipairs(config.filetypes or spec.filetypes) do
          local e = entry(lang, ft)
          if e then
            e.servers[name] = true
          end
        end
      end
    end
    local formatters = spec.formatters or {}
    for _, ft in ipairs(formatters.filetypes or spec.filetypes) do
      local e = entry(lang, ft)
      if e then
        e.formatters = { unpack(formatters) }
      end
    end
    for name, linter in pairs(spec.linters or {}) do
      for _, ft in ipairs(linter.filetypes or spec.filetypes) do
        local e = entry(lang, ft)
        if e then
          e.linters[name] = true
        end
      end
    end
    covering(spec.linters or {}, lang)
    local rows = spec.keys or {}
    for _, ft in ipairs(rows.filetypes or (#rows > 0 and spec.filetypes) or {}) do
      if entry(lang, ft) then
        views.keys[ft] = { unpack(rows) }
      end
    end
  end

  -- A base's linters run first, in name order, then a variant's own
  for _, answer in pairs(raw) do
    answer.linters = sorted(answer.linters)
  end

  -- Variants, once every base is known
  local rule_owner = {} ---@type table<string, string> "filename x" or "pattern x" -> the variant it gives
  for _, lang in ipairs(names) do
    local variants = specs[lang].variants or {}
    for _, ft in ipairs(sorted(variants)) do
      local variant = variants[ft]
      local base = ft:match("^([^.]+)%.")
      if not base then
        problem("lang.%s: variant %s has no base filetype before a dot; it is skipped", lang, ft)
      elseif raw[ft] then
        problem("lang.%s: variant %s is already declared by lang.%s; this one is skipped", lang, ft, raw[ft].lang)
      else
        local from = raw[base] or { servers = {}, formatters = {}, linters = {} }
        local answer = {
          lang = lang,
          base = base,
          servers = {},
          formatters = { unpack(variant.formatters or from.formatters) },
          linters = { unpack(from.linters) },
          covered_by = {},
          options = from.options,
        }
        for name in pairs(from.servers) do
          answer.servers[name] = true
        end
        for _, name in ipairs(variant.servers or {}) do
          if configs[name] then
            answer.servers[name] = true
          else
            problem("lang.%s: variant %s names server %s, which no language's servers configure; it is skipped", lang, ft, name)
          end
        end
        for _, name in ipairs(sorted(variant.linters or {})) do
          add(answer.linters, name)
        end
        covering(variant.linters or {}, lang)
        raw[ft] = answer
        owner[ft] = lang
        views.variants[ft] = { lang = lang, base = base, about = variant.about, example = variant.example }
        local match = variant.match or {}
        local rules = {} ---@type { [1]: "filename"|"pattern", [2]: string, [3]: any }[]
        for _, name in ipairs(match.filename or {}) do
          rules[#rules + 1] = { "filename", name, ft }
        end
        for _, pattern in ipairs(sorted(match.pattern or {})) do
          local opts = match.pattern[pattern]
          rules[#rules + 1] = { "pattern", pattern, next(opts) and { ft, opts } or ft }
        end
        for _, rule in ipairs(rules) do
          local key = rule[1] .. " " .. rule[2]
          if rule_owner[key] then
            problem("lang.%s: variant %s's %s is already %s's; this rule is skipped", lang, ft, key, rule_owner[key])
          else
            rule_owner[key] = ft
            views.filetypes[rule[1]][rule[2]] = rule[3]
          end
        end
      end
    end
  end

  local answers = {} ---@type table<string, lang.Answer>
  for ft, answer in pairs(raw) do
    for _, name in ipairs(answer.linters) do
      answer.covered_by[name] = views.covered_by[name]
    end
    answers[ft] = finish(answer)
    if #answer.formatters > 0 then
      views.conform[ft] = answer.formatters
    end
    if #answer.linters > 0 then
      views.lint[ft] = answer.linters
    end
  end

  -- Each server's config, with every filetype whose answer names it
  for ft, answer in pairs(answers) do
    for _, name in ipairs(answer.servers) do
      views.lsp[name] = views.lsp[name] or vim.tbl_extend("force", configs[name].config, { filetypes = {} })
      add(views.lsp[name].filetypes, ft)
    end
  end
  for _, config in pairs(views.lsp) do
    table.sort(config.filetypes)
  end

  local R = { problems = problems } ---@type lang.Registry
  local fallbacks = {} ---@type table<string, lang.Answer|false> undeclared filetype -> R.of's answer

  --- A dotted filetype no language declares gets what the plugins' own rules for it gave before lang/: no servers
  --- (a server attaches only to the filetypes it lists), the formatters of its last part that has any (conform's
  --- rule), every part's linters (nvim-lint's), and every part's options, later parts last (Neovim sources each
  --- part's ftplugin in order). Nil when no part is declared.
  ---@param ft string
  local function fallback(ft)
    local parts = vim.split(ft, ".", { plain = true })
    local first, formatters, linters, covered_by, options = nil, {}, {}, {}, nil
    for _, part in ipairs(parts) do
      local a = answers[part]
      if a then
        first = first or part
        if #a.formatters > 0 then
          formatters = a.formatters
        end
        for _, name in ipairs(a.linters) do
          add(linters, name)
          covered_by[name] = a.covered_by[name]
        end
        if a.options then
          options = vim.tbl_extend("force", options or {}, a.options)
        end
      end
    end
    return first
        and finish({
          lang = answers[first].lang,
          base = first,
          servers = {},
          formatters = formatters,
          linters = linters,
          covered_by = covered_by,
          options = options,
        })
      or false
  end

  --- What applies to a filetype: its language, servers, formatters and linters, and the catalog binaries behind them.
  --- Nil for a filetype no language knows. Callers must not modify it.
  function R.of(ft)
    if answers[ft] then
      return answers[ft]
    end
    local cached = fallbacks[ft]
    if cached == nil then
      cached = ft:find(".", 1, true) and fallback(ft) or false
      fallbacks[ft] = cached
    end
    return cached or nil
  end

  --- The tables each plugin wants. Callers must not modify them.
  function R.views() return views end

  --- Every filetype a language declares, variants included, sorted.
  function R.filetypes() return sorted(answers) end

  --- Adds the variants' filetype rules, sets each language's buffer options on FileType, after the runtime's ftplugins
  --- and after/ftplugin, whose autocmd Neovim makes before init.lua runs, and reports any problems once.
  function R.setup()
    vim.filetype.add(views.filetypes)
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("lang", { clear = true }),
      callback = function(ev)
        local answer = R.of(ev.match)
        for name, value in pairs(answer and answer.options or {}) do
          vim.bo[ev.buf][name] = value
        end
      end,
    })
    if #problems > 0 then
      local msg = "lua/lang/ has problems; what they name is skipped:\n- " .. table.concat(problems, "\n- ")
      -- held until the startup phases are done, so it is a toast (lua/app/init.lua)
      require("app").report(msg, "lang")
    end
  end

  return R
end

local registry ---@type lang.Registry?
local specs, load_problems ---@type table<string, lang.Spec>, string[]

--- A registry over specs; should building fail, every filetype goes without tools rather than Neovim without its config.
local function build()
  local problems = vim.list_extend({}, load_problems)
  local ok, built = pcall(M._from, specs, problems)
  if not ok then
    problems[#problems + 1] = "lang: " .. tostring(built)
    built = M._from({}, problems)
  end
  registry = built
  return built
end

--- The registry over the language files next to this one. A file that does not load is skipped and reported.
---@return lang.Registry
local function languages()
  if registry then
    return registry
  end
  specs, load_problems = {}, {}
  for file, kind in vim.fs.dir(dir) do
    local name = file:match("^(.+)%.lua$")
    if kind == "file" and name and name ~= "init" then
      local ok, spec = pcall(require, "lang." .. name)
      if ok and type(spec) == "table" and type(spec.filetypes) == "table" then
        specs[name] = spec
      else
        load_problems[#load_problems + 1] = ("lang.%s does not load: %s"):format(name, ok and "it returns no filetypes" or spec)
      end
    end
  end
  return build()
end

--- What applies to a filetype; see lang.Registry. A dotted filetype no language declares gets its parts' formatters,
--- linters and options as conform, nvim-lint and Neovim's ftplugins combine them, and no servers.
---@param ft string
---@return lang.Answer?
function M.of(ft) return languages().of(ft) end

--- The tables each plugin wants, built from every language file. Callers must not modify them.
---@return lang.Views
function M.views() return languages().views() end

--- Every filetype a language declares, variants included, sorted.
---@return string[]
function M.filetypes() return languages().filetypes() end

--- What the language files declare that was skipped, one message each.
---@return string[]
function M.problems() return languages().problems end

--- Adds the variants' filetype rules and the buffer options, and reports the problems once.
function M.setup() languages().setup() end

--- For tests: declares language name as spec, or removes it with nil, and rebuilds what M.of and M.views answer. The
--- plugins' tables built from the views at startup keep what they had.
---@param name string
---@param spec? lang.Spec
function M._declare(name, spec)
  languages()
  specs[name] = spec
  build()
end

return M
