-- @desc     gopls and rust-analyzer are told in initialize that the client sends file renames (workspace.fileOperations), and still get blink's completion capabilities
-- @areas    lsp completion
-- @budget   15
-- @needs    gopls rust-analyzer

-- record the capabilities each server is sent in initialize, by binary name
local rpc = vim.lsp.rpc
local start, sent = rpc.start, {}
rpc.start = function(cmd, ...)
  local client = start(cmd, ...)
  local request = client.request
  client.request = function(method, params, ...)
    if method == "initialize" and type(cmd) == "table" then sent[vim.fs.basename(cmd[1])] = params.capabilities end
    return request(method, params, ...)
  end
  return client
end

-- first path in want whose value got lacks
local function missing(want, got, path)
  if type(want) ~= "table" or vim.islist(want) then return not vim.deep_equal(want, got) and path or nil end
  for k, v in pairs(want) do
    local sub
    if type(got) == "table" then sub = got[k] end
    local bad = missing(v, sub, path .. "." .. k)
    if bad then return bad end
  end
end

local okb, blink = pcall(require, "blink.cmp")
local blink_caps = okb and blink.get_lsp_capabilities() or nil
if not blink_caps then info("blink.cmp is not installed; its completion capabilities are not judged") end
local renames = { workspace = { fileOperations = { didRename = true, willRename = true } } }

for _, s in ipairs({ { "gopls", "main.go", "gopls" }, { "rust_analyzer", "rs/src/main.rs", "rust-analyzer" } }) do
  local name, file, bin = s[1], s[2], s[3]
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  local _, why = wait_attach(buf, { name }, 30000)
  local c = vim.lsp.get_clients({ bufnr = buf, name = name })[1]
  check(name .. ": attaches", c ~= nil, table.concat(why, "; "))
  if c then
    local caps = sent[bin]
    if not caps then
      info(name .. ": initialize was not captured; judging client.capabilities")
      caps = c.capabilities
    end
    local ops = vim.inspect(vim.tbl_get(caps or {}, "workspace", "fileOperations"), { newline = " ", indent = "" })
    check(name .. ": initialize carries didRename and willRename", missing(renames, caps, "") == nil, ops)
    if blink_caps then
      local lack = missing(blink_caps, caps, "")
      check(name .. ": initialize carries blink's completion capabilities", lack == nil, lack and ("lacks " .. lack))
    end
  end
end
