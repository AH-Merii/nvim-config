-- @desc     every analyzer named in the resolved gopls settings is one the installed gopls knows; gopls ignores unknown names without a warning
-- @areas    lsp
-- @budget   10

if vim.fn.executable("gopls") ~= 1 then
  check("gopls is on PATH", false, "gopls is enabled from PATH, outside Mason; put it on the suite's PATH")
  return
end
local api = vim.system({ "gopls", "api-json" }, { text = true }):wait(10000)
local okj, doc = pcall(vim.json.decode, api.stdout or "")
local known, count = {}, 0
for _, a in ipairs(okj and type(doc) == "table" and doc.Analyzers or {}) do
  known[a.Name] = true
  count = count + 1
end
if count == 0 then
  check("gopls api-json lists its analyzers", false, ("exit %s: %s"):format(api.code, (api.stderr or ""):sub(1, 200)))
  return
end

local analyses = vim.tbl_get(vim.lsp.config.gopls or {}, "settings", "gopls", "analyses") or {}
local names, unknown = vim.tbl_keys(analyses), {}
table.sort(names)
for _, name in ipairs(names) do
  if not known[name] then table.insert(unknown, name) end
end
info(("gopls knows %d analyzers; the config names %d"):format(count, #names))
check("every configured gopls analyzer is one gopls knows", #unknown == 0, "unknown: " .. table.concat(unknown, ", "))
