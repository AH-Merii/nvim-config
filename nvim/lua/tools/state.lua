-- The answers to the project prompt and to "which copy" questions, per project config file, kept until the project's
-- configs change; and the tools the user said not to ask about again in a project, per project root.

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
---@param hash? string the configs' hash to look up the answer for, default their hash now
---@return tools.Choice?
function M.get(configs, hash)
  local saved = configs[1] and read()[configs[1]]
  return saved and saved.hash == (hash or M.hash(configs)) and saved.choice or nil
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

-- Tools not to offer again in a project ("Not for this project"): root -> catalog binary -> the date it was said
M.declined_file = vim.fs.joinpath(vim.fn.stdpath("state"), "tools", "declined.json")

---@return table<string, table<string, string>>
local function read_declined()
  local ok, data = pcall(function() return vim.json.decode(table.concat(vim.fn.readfile(M.declined_file), "\n")) end)
  return ok and type(data) == "table" and data or {}
end

--- The tools the user said not to offer again in root's project: catalog binary -> the date it was said.
---@param root string
---@return table<string, string>
function M.declined(root) return read_declined()[root] or {} end

--- Remembers not to offer tools again in root's project.
---@param root string
---@param names string[] catalog binaries
function M.decline(root, names)
  local data = read_declined() -- re-read, another session may have written since
  data[root] = data[root] or {}
  for _, name in ipairs(names) do
    data[root][name] = os.date("!%Y-%m-%d")
  end
  vim.fn.mkdir(vim.fs.dirname(M.declined_file), "p")
  vim.fn.writefile({ vim.json.encode(data) }, M.declined_file)
end

return M
