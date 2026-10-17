-- @desc     the tables the language files generate are what the plugins hold: every server a language names extends one nvim-lspconfig defines and its fields reach vim.lsp.config, and conform's and nvim-lint's tables are the languages' own
-- @areas    lsp format lint tools
-- @budget   10
local function applied(want, got)
  -- functions too: vim.lsp.config keeps the ones a language gives (on_init, handlers, commands)
  if type(want) ~= "table" then return want == got end
  if type(got) ~= "table" then return false end
  if vim.islist(want) then return vim.deep_equal(want, got) end
  for k, v in pairs(want) do
    if not applied(v, got[k]) then return false end
  end
  return true
end
local views = require("lang").views()
local names = vim.tbl_keys(views.lsp)
table.sort(names)
check("the languages name servers", #names > 0)
for _, name in ipairs(names) do
  check(name .. ": extends a server lspconfig defines", #vim.api.nvim_get_runtime_file("lsp/" .. name .. ".lua", true) > 0)
  check(name .. ": its fields are applied", applied(views.lsp[name], vim.lsp.config[name]), vim.lsp.config[name] and vim.lsp.config[name].filetypes)
end
check("conform's formatters_by_ft is the languages'", vim.deep_equal(require("conform").formatters_by_ft, views.conform))
check("nvim-lint's linters_by_ft is the languages'", vim.deep_equal(require("lint").linters_by_ft, views.lint))
