-- @desc     every after/lsp/<name>.lua extends a server nvim-lspconfig defines, and its fields reach vim.lsp.config
-- @areas    lsp
-- @budget   10
local function applied(want, got)
  if type(want) ~= "table" then return type(want) == "function" or want == got end
  if type(got) ~= "table" then return false end
  if vim.islist(want) then return vim.deep_equal(want, got) end
  for k, v in pairs(want) do
    if not applied(v, got[k]) then return false end
  end
  return true
end
local files = vim.fn.glob(vim.fn.stdpath("config") .. "/after/lsp/*.lua", false, true)
info(#files .. " after/lsp files")
for _, f in ipairs(files) do
  local name = vim.fn.fnamemodify(f, ":t:r")
  local base = vim.tbl_filter(function(p) return not p:find("/after/lsp/", 1, true) end, vim.api.nvim_get_runtime_file("lsp/" .. name .. ".lua", true))
  check(name .. ": extends a server lspconfig defines", #base > 0)
  local ok, want = pcall(dofile, f)
  check(name .. ": its fields are applied", ok and type(want) == "table" and applied(want, vim.lsp.config[name]), not ok and want or nil)
end
