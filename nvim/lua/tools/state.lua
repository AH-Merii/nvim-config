-- The answer to the project prompt, per project config file, kept until the project's configs change.

local M = {}

---@alias tools.Choice "use"|"installed"|"global"
--- use: use the project's pins and `mise install` them (trusts the config)
--- installed: use the project's pins that are already installed; no install, no trust
--- global: ignore the project config; .venv and node_modules still apply

M.file = vim.fs.joinpath(vim.fn.stdpath("state"), "tools", "projects.json")

---@return table<string, { choice: tools.Choice, hash: string }>
local function read()
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(M.file), "\n")) end)
  return ok and type(data) == "table" and data or {}
end

--- Hash of the configs' contents, so an edit to any of them asks again.
---@param configs string[]
function M.hash(configs)
  local parts = {}
  for _, path in ipairs(configs) do
    local ok, lines = pcall(vim.fn.readfile, path, "b")
    table.insert(parts, path .. "\0" .. (ok and table.concat(lines, "\n") or ""))
  end
  return vim.fn.sha256(table.concat(parts, "\0"))
end

--- The remembered choice for configs (nearest first), or nil if never answered or the configs changed since.
---@param configs string[]
---@return tools.Choice?
function M.get(configs)
  local saved = configs[1] and read()[configs[1]]
  return saved and saved.hash == M.hash(configs) and saved.choice or nil
end

---@param configs string[]
---@param choice tools.Choice
function M.set(configs, choice)
  assert(configs[1], "tools.state: no project config")
  local data = read() -- re-read, another session may have written since
  data[configs[1]] = { choice = choice, hash = M.hash(configs) }
  vim.fn.mkdir(vim.fs.dirname(M.file), "p")
  vim.fn.writefile({ vim.json.encode(data) }, M.file)
end

return M
