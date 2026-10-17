-- pyrefly's type errors, on or off for one client: its on_init (lang/python.lua) and the <leader>Te toggle
-- (lsp/buffer.lua) both go through M.type_errors
local M = {}

-- A pyrefly.toml or [tool.pyrefly] governs the files under it, where typeCheckingMode does nothing
---@param dir? string
local function pyrefly_configured(dir)
  while dir do
    if vim.uv.fs_stat(vim.fs.joinpath(dir, "pyrefly.toml")) then
      return true
    end
    local pyproject = vim.fs.joinpath(dir, "pyproject.toml")
    if vim.uv.fs_stat(pyproject) then
      return vim.iter(io.lines(pyproject)):any(function(line) return line:match("^%s*%[tool%.pyrefly[%].]") ~= nil end)
    end
    local parent = vim.fs.dirname(dir)
    dir = parent ~= dir and parent or nil
  end
  return false
end

--- Whether pyrefly type-checks this client's files; with `on`, turns checking on or off first.
---@param client vim.lsp.Client
---@param on? boolean
---@return boolean
function M.type_errors(client, on)
  if on ~= nil then
    local pyrefly = { typeCheckingMode = on and "default" or "basic", disableTypeErrors = not on and pyrefly_configured(client.root_dir) }
    client.settings = vim.tbl_deep_extend("force", client.settings, { python = { pyrefly = pyrefly } })
    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
  end
  return vim.tbl_get(client.settings, "python", "pyrefly", "typeCheckingMode") == "default"
end

return M
