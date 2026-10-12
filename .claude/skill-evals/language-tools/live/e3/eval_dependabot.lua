-- @desc     eval e3: .github/dependabot.yml gets jactionlint findings (current args) and keeps yamlls; plain YAML with the same text gets no jactionlint findings
-- @areas    eval
-- @budget   60
local ns = require("lint").get_namespace("jactionlint")
-- "npmm" is not a package ecosystem: jactionlint --profile correctness reports dependabot-syntax on line 3
local bad = { "version: 2", "updates:", '  - package-ecosystem: "npmm"', '    directory: "/"', "    schedule:", '      interval: "weekly"' }
vim.fn.mkdir(".github", "p")
vim.fn.writefile(bad, ".github/dependabot.yml")
vim.fn.writefile(bad, "config.yml")

vim.cmd.edit(".github/dependabot.yml")
local buf = vim.api.nvim_get_current_buf()
local ft = vim.bo[buf].filetype
check(".github/dependabot.yml gets a yaml sub-filetype", ft:match("^yaml%.") ~= nil, ft)
wait_diagnostics(buf, function() return #vim.diagnostic.get(buf, { namespace = ns }) > 0 end, 15000)
local found = vim.iter(vim.diagnostic.get(buf, { namespace = ns })):any(function(d) return d.code == "dependabot-syntax" and d.lnum == 2 end)
check("jactionlint reports dependabot-syntax on line 3 of .github/dependabot.yml", found,
  vim.inspect(vim.tbl_map(function(d) return { d.lnum + 1, d.code } end, vim.diagnostic.get(buf, { namespace = ns }))))
local missing, why = wait_attach(buf, { "yamlls" }, 30000)
check("yamlls attaches to .github/dependabot.yml", #missing == 0, table.concat(why, "; "))

vim.cmd.edit("config.yml")
local pbuf = vim.api.nvim_get_current_buf()
check("config.yml stays yaml", vim.bo[pbuf].filetype == "yaml", vim.bo[pbuf].filetype)
wait_until(function() return #vim.diagnostic.get(pbuf, { namespace = ns }) > 0 end, 4000)
check("config.yml gets no jactionlint findings", #vim.diagnostic.get(pbuf, { namespace = ns }) == 0,
  vim.inspect(vim.tbl_map(function(d) return d.code end, vim.diagnostic.get(pbuf, { namespace = ns }))))
