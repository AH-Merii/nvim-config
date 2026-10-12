-- @desc     workflow YAML and pyproject.toml get their dotted sub-filetypes; every sub-filetype needs the tools set for it alone while its base filetype does not, and keeps its base's servers, linters and treesitter highlighting
-- @areas    tools lint format lsp treesitter
-- @budget   20
local tools = require("tools")

local cases = {
  { ".github/workflows/ci.yml", "yaml.github-actions" },
  { ".github/workflows/release.yaml", "yaml.github-actions" },
  { ".github/workflows/nested/x.yml", "yaml" }, -- GitHub only reads the top level
  { ".github/dependabot.yml", "yaml" },
  { "config.yml", "yaml" },
  { "pyproject.toml", "toml.pyproject" },
  { "sub/pyproject.toml", "toml.pyproject" },
  { "Cargo.toml", "toml" },
  { "other.toml", "toml" },
}
for _, c in ipairs(cases) do
  local ft = vim.filetype.match({ filename = FIX .. "/" .. c[1] })
  check(c[1] .. " is " .. c[2], ft == c[2], tostring(ft))
end

local function has(list, names)
  return vim.iter(names):all(function(n) return vim.list_contains(list, n) end)
end
local function none(list, names)
  return not vim.iter(names):any(function(n) return vim.list_contains(list, n) end)
end

-- Every sub-filetype: the tools set for it alone (by its full name or its extra part) are needed there and not in its
-- base filetype; it keeps the base's servers and linters, and the base's formatters unless it sets its own
local lint, conform, catalog = require("lint"), require("conform"), require("tools.catalog")
local subs = vim.tbl_keys(require("tools.filetypes").filetypes)
table.sort(subs)
check("sub-filetypes are defined", #subs > 0, vim.inspect(subs))
for _, ft in ipairs(subs) do
  local base, part = ft:match("^([^.]+)%.(.+)$")
  local own, own_formatters = {}, false
  for _, key in ipairs({ ft, part }) do
    for _, name in ipairs(lint.linters_by_ft[key] or {}) do
      table.insert(own, catalog.binary("linter", name) or name)
    end
    for _, name in ipairs(type(conform.formatters_by_ft[key]) == "table" and conform.formatters_by_ft[key] or {}) do
      own_formatters = true
      table.insert(own, catalog.binary("formatter", name) or name)
    end
  end
  local sub, plain = tools.for_filetype(ft), tools.for_filetype(base)
  if check(ft .. " has tools of its own", #own > 0, ft) then
    check(ft .. " needs its own tools", has(sub.tools, own), vim.inspect({ own = own, needs = sub.tools }))
    check(base .. " does not need " .. ft .. "'s own tools", none(plain.tools, own), vim.inspect({ own = own, needs = plain.tools }))
  end
  check(ft .. " keeps " .. base .. "'s servers and linters", #plain.servers > 0 and has(sub.servers, plain.servers) and has(sub.linters, plain.linters),
    vim.inspect({ sub.servers, plain.servers, sub.linters, plain.linters }))
  if not own_formatters then
    check(ft .. " keeps " .. base .. "'s formatters", #plain.formatters > 0 and vim.deep_equal(sub.formatters, plain.formatters),
      vim.inspect({ sub.formatters, plain.formatters }))
  end
end

-- treesitter parses the first part, so highlighting is unchanged
vim.fn.writefile({ "on: push" }, ".github/workflows/ci.yml")
for _, c in ipairs({ { ".github/workflows/ci.yml", "yaml" }, { "pyproject.toml", "toml" } }) do
  vim.cmd.edit(c[1])
  local buf = vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  check(c[1] .. " (" .. vim.bo[buf].filetype .. ") is highlighted with the " .. c[2] .. " parser",
    ok and parser ~= nil and parser:lang() == c[2] and vim.treesitter.highlighter.active[buf] ~= nil,
    ok and parser and parser:lang() or tostring(parser))
end
