-- The answers to the project prompt and to "which copy" questions, per project config file, kept until the project's
-- configs change.

local M = {}

---@alias tools.Choice "use"|"installed"|"global"
--- use: use the project's pins and `mise install` them (trusts the config)
--- installed: use the project's pins that are already installed; no install, no trust
--- global: ignore the project config; .venv and node_modules still apply

M.file = vim.fs.joinpath(vim.fn.stdpath("state"), "tools", "projects.json")

---@alias tools.Prefer "env"|"mise" which copy of a tool wins when the project env and a mise pin differ

---@return table<string, { choice?: tools.Choice, hash: string, prefer?: table<string, tools.Prefer> }>
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

--- The remembered copy of tool to use in the project of configs, or nil if never answered or the configs changed since.
---@param configs string[]
---@param tool string catalog binary
---@return tools.Prefer?
function M.prefer(configs, tool)
  local saved = configs[1] and read()[configs[1]]
  return saved and saved.hash == M.hash(configs) and (saved.prefer or {})[tool] or nil
end

--- Changes the saved entry for configs; answers saved for an older version of the configs are dropped.
---@param configs string[]
---@param change fun(entry: { choice?: tools.Choice, hash: string, prefer?: table<string, tools.Prefer> })
local function update(configs, change)
  assert(configs[1], "tools.state: no project config")
  local data = read() -- re-read, another session may have written since
  local hash = M.hash(configs)
  local entry = data[configs[1]]
  entry = entry and entry.hash == hash and entry or { hash = hash }
  change(entry)
  data[configs[1]] = entry
  vim.fn.mkdir(vim.fs.dirname(M.file), "p")
  vim.fn.writefile({ vim.json.encode(data) }, M.file)
end

---@param configs string[]
---@param choice tools.Choice
function M.set(configs, choice)
  update(configs, function(entry) entry.choice = choice end)
end

---@param configs string[]
---@param tool string catalog binary
---@param prefer tools.Prefer
function M.set_prefer(configs, tool, prefer)
  update(configs, function(entry)
    entry.prefer = entry.prefer or {}
    entry.prefer[tool] = prefer
  end)
end

return M
