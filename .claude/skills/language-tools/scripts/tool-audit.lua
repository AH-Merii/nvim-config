-- Headless audit of this config's tool wiring. scripts/check.sh runs it; to run it by hand, from a scratch dir:
--   FT="yaml yaml.github-actions" FILES=".github/workflows/ci.yml" <repo>/tests/regress/nv.sh nightly --headless -c 'luafile <this file>'
-- FT: filetypes to report (servers, formatters, linters, catalog binaries). FILES: paths to report the filetype of.
-- BASE_CATALOG, BASE_LANG: the base commit's lua/tools/catalog.lua and lua/lang/ dir; with them it also prints the
-- binaries and sub-filetypes (variants) the change added or removed ("new", "newft", "removed" lines).
-- Exits 1 when a check fails; each FAIL line names the file to fix.
require("lazy").load({ plugins = { "conform.nvim", "nvim-lint", "nvim-lspconfig" } })
local catalog, lang = require("tools.catalog"), require("lang")
local conform, lint = require("conform"), require("lint")
local enabled = require("core.lsp_servers").servers
local subfts = lang.views().variants
local none = { servers = {}, formatters = {}, linters = {}, tools = {} }
--- What applies to ft (lang.of), or empty lists for a filetype no language knows.
local function of(ft) return lang.of(ft) or none end

local failures = 0
local function out(fmt, ...) io.stdout:write(fmt:format(...) .. "\n") end
local function check(ok, fmt, ...)
  if not ok then
    failures = failures + 1
    out("FAIL " .. fmt, ...)
  end
  return ok
end

-- The language files load, and none declares what another already did (lua/lang/init.lua skips it)
for _, problem in ipairs(lang.problems()) do
  check(false, "lua/lang/: %s", problem)
end

-- Servers: the languages and the catalog name the same servers, and nvim-lspconfig defines each
for _, name in ipairs(enabled) do
  check(catalog.binary("server", name) ~= nil, "server %s is named in lua/lang/ but no catalog entry has servers.%s", name, name)
  check(vim.lsp.config[name] ~= nil, "server %s has no nvim-lspconfig config (lsp/%s.lua): wrong name?", name, name)
end
for _, name in ipairs(catalog.servers()) do
  check(vim.list_contains(enabled, name), "catalog server %s is named by no language's servers in lua/lang/", name)
end

-- conform and nvim-lint set these in their config(); empty means that config raised an error
check(next(conform.formatters_by_ft) ~= nil, "conform's formatters_by_ft is empty: lua/plugins/conform.lua config() raised an error")
check(next(lint.linters_by_ft) ~= nil, "nvim-lint's linters_by_ft is empty: lua/plugins/nvim-lint.lua config() raised an error")

-- The plugins' built-in definitions, by command. Read as text: loading some of them runs the tool.
local function builtins(glob, field)
  local names, by_cmd = {}, {}
  for _, f in ipairs(vim.api.nvim_get_runtime_file(glob, true)) do
    local name = vim.fn.fnamemodify(f, ":t:r")
    names[name] = f
    local cmd = table.concat(vim.fn.readfile(f), "\n"):match(field .. "%s*=%s*[\"']([^\"']+)[\"']")
    if cmd then
      by_cmd[cmd] = by_cmd[cmd] or {}
      table.insert(by_cmd[cmd], name)
    end
  end
  return names, by_cmd
end
local builtin_fmt, fmt_by_cmd = builtins("lua/conform/formatters/*.lua", "command")
local builtin_lint, lint_by_cmd = builtins("lua/lint/linters/*.lua", "cmd")

-- Formatters: every formatters_by_ft value (from lua/lang/) is a plain list of names in the catalog. A name conform does not ship
-- must not run a command one of conform's built-ins already runs: use the built-in's name and args instead.
for ft, names in pairs(conform.formatters_by_ft) do
  if check(type(names) == "table", "formatters_by_ft[%q] is a %s; a language's formatters must be a list of names", ft, type(names)) then
    for _, name in ipairs(names) do
      check(type(name) == "string", "formatters_by_ft[%q] holds a nested list; a language's formatters must be plain names", ft)
      if type(name) == "string" then
        local bin = catalog.binary("formatter", name)
        check(bin ~= nil, "formatter %s (formatters_by_ft[%q]) is in no catalog entry's formatters", name, ft)
        check(builtin_fmt[name] ~= nil or conform.get_formatter_config(name) ~= nil,
          "formatter %s is not a conform formatter (conform.nvim/lua/conform/formatters/%s.lua)", name, name)
        local def = conform.formatters[name]
        local cmd = type(def) == "table" and type(def.command) == "string" and vim.fs.basename(def.command) or bin
        local dup = not builtin_fmt[name] and cmd and fmt_by_cmd[cmd]
        check(not dup, "formatter %s is a definition of the config's own, but conform's built-in %s already runs %s: use that name in lua/lang/ and the catalog, and delete opts.formatters.%s (lua/plugins/conform.lua)",
          name, table.concat(dup or {}, "/"), cmd or "", name)
        check(not (builtin_fmt[name] and type(def) == "table" and def.inherit == false),
          "opts.formatters.%s replaces conform's built-in definition (inherit = false): override only what differs, e.g. prepend_args", name)
      end
    end
  end
end

-- Linters: every name has a catalog entry and a definition. A definition of the config's own (lint.linters.<name> =
-- {...}) must not replace or duplicate one nvim-lint ships.
for ft, names in pairs(lint.linters_by_ft) do
  for _, name in ipairs(names) do
    check(catalog.binary("linter", name) ~= nil, "linter %s (linters_by_ft[%q]) is in no catalog entry's linters", name, ft)
    check(lint.linters[name] ~= nil, "linter %s has no nvim-lint definition (built in or lint.linters.%s in nvim-lint.lua)", name, name)
  end
end
for name, def in pairs(lint.linters) do -- pairs sees raw keys only: the config's own definitions
  check(not builtin_lint[name], "lint.linters.%s in nvim-lint.lua replaces nvim-lint's built-in %s: delete it and use the built-in (%s)",
    name, name, builtin_lint[name] or "")
  local cmd = type(def) == "table" and type(def.cmd) == "string" and vim.fs.basename(def.cmd) or catalog.binary("linter", name)
  local dup = cmd and lint_by_cmd[cmd]
  check(not dup, "lint.linters.%s runs %s, which nvim-lint's built-in %s already runs: use that name instead of a definition of your own",
    name, cmd or "", table.concat(dup or {}, "/"))
end

-- Catalog: every entry has a role, or another entry requires it
local required = {}
for _, entry in pairs(catalog.tools) do
  for _, r in ipairs(entry.requires or {}) do
    required[r] = true
  end
end
for bin, entry in pairs(catalog.tools) do
  local roles = next(entry.servers or {}) or next(entry.formatters or {}) or next(entry.linters or {})
  check(roles ~= nil or required[bin], "catalog entry %s has no servers, formatters or linters and nothing requires it", bin)
end

-- Sub-filetypes: lua/lang/init.lua gives each variant its base's servers and linters; a variant declared under
-- another name than base.part, or a base no language declares, would lose them
for sub, variant in pairs(subfts) do
  local s, b = of(sub), of(variant.base)
  for _, server in ipairs(b.servers) do
    check(vim.list_contains(s.servers, server), "sub-filetype %s loses %s's server %s (lua/lang/%s.lua)", sub, variant.base, server, variant.lang)
  end
  for _, linter in ipairs(b.linters) do
    check(vim.list_contains(s.linters, linter), "sub-filetype %s loses %s's linter %s (lua/lang/%s.lua)", sub, variant.base, linter, variant.lang)
  end
end

-- What the change added or removed, compared with the base commit's files
local function load_base(path)
  local chunk = path and path ~= "" and loadfile(path)
  local ok, mod = pcall(chunk or error)
  return ok and type(mod) == "table" and mod or nil
end
local base_catalog = load_base(vim.env.BASE_CATALOG)
-- The base commit's variants: each language file there is data, read on its own
local base_fts = {}
for name in vim.fn.isdirectory(vim.env.BASE_LANG or "") == 1 and vim.fs.dir(vim.env.BASE_LANG) or function() end do
  local spec = name ~= "init.lua" and name:match("%.lua$") and load_base(vim.env.BASE_LANG .. "/" .. name)
  for sub in pairs(spec and spec.variants or {}) do
    base_fts[sub] = true
  end
end
local report = vim.split(vim.env.FT or "", "%s+", { trimempty = true }) -- filetypes to print an "ft" line for
if base_catalog then
  local ft_list = lang.filetypes()

  local bins = vim.tbl_keys(catalog.tools)
  table.sort(bins)
  for _, bin in ipairs(bins) do
    if not base_catalog.tools[bin] then
      local e, roles, where = catalog.tools[bin], {}, {}
      for name in pairs(e.servers or {}) do table.insert(roles, "server " .. name) end
      for _, name in ipairs(e.formatters or {}) do table.insert(roles, "formatter " .. name) end
      for _, name in ipairs(e.linters or {}) do table.insert(roles, "linter " .. name) end
      for _, ft in ipairs(ft_list) do
        if vim.list_contains(of(ft).tools, bin) then
          table.insert(where, ft)
          if not vim.list_contains(report, ft) then table.insert(report, ft) end
        end
      end
      out("new\t%s\t%s\t%s\t%s", bin, e.spec or "", table.concat(roles, ", "), table.concat(where, " "))
    end
  end
  for bin in pairs(base_catalog.tools) do
    if not catalog.tools[bin] then out("removed\t%s", bin) end
  end
  for sub, variant in pairs(subfts) do
    if not base_fts[sub] then
      out("newft\t%s\t%s\t%s", sub, variant.about, table.concat(of(sub).tools, ", "))
    end
  end
end

for _, path in ipairs(vim.split(vim.env.FILES or "", "%s+", { trimempty = true })) do
  out("file %s -> filetype %s", path, tostring(vim.filetype.match({ filename = vim.fs.abspath(path) })))
end
for _, ft in ipairs(report) do
  local f = of(ft)
  out("ft %s: servers={%s} formatters={%s} linters={%s} tools={%s}", ft, table.concat(f.servers, ","), table.concat(f.formatters, ","),
    table.concat(f.linters, ","), table.concat(f.tools, ","))
end

out(failures == 0 and "AUDIT OK" or ("AUDIT FAILED: %d problem(s)"):format(failures))
vim.cmd(failures == 0 and "qa!" or "cquit 1")
