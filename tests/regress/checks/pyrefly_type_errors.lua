-- @desc     pyrefly shows type errors where the project root has a pyproject.toml and hides them, not unknown names, where it has none, and <leader>Te flips them per client without restarting pyrefly
-- @areas    lsp keys
-- @budget   60
-- @fixture  projects
-- @needs    pyrefly ruff

-- a pyrefly publish for a uri that came after pyrefly last got its settings: the file was checked with them
local cfg_answered, settled, detached = {}, {}, 0
local cfg = vim.lsp.handlers["workspace/configuration"]
vim.lsp.handlers["workspace/configuration"] = function(err, params, ctx)
  local result = cfg(err, params, ctx)
  cfg_answered[ctx.client_id] = true
  return result
end
local pub = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, params, ctx)
  local result = pub(err, params, ctx)
  local c = vim.lsp.get_client_by_id(ctx.client_id)
  if c and c.name == "pyrefly" and cfg_answered[ctx.client_id] then settled[params.uri] = true end
  return result
end
vim.api.nvim_create_autocmd("LspDetach", {
  callback = function(ev)
    local c = vim.lsp.get_client_by_id(ev.data.client_id)
    if c and c.name == "pyrefly" then detached = detached + 1 end
  end,
})

local function type_errors(buf)
  return vim.tbl_filter(function(d) return d.code == "bad-argument-type" end, vim.diagnostic.get(buf))
end
local function describe(buf)
  return table.concat(vim.tbl_map(function(d) return tostring(d.source) .. ":" .. tostring(d.code) end, vim.diagnostic.get(buf)), ",")
end
local function open(dir)
  vim.cmd.edit(dir .. "/app.py")
  local buf = vim.api.nvim_get_current_buf()
  local missing, why = wait_attach(buf, { "pyrefly" }, 20000)
  if not check(dir .. ": pyrefly attaches", #missing == 0, vim.inspect(why)) then return nil end
  local client = vim.lsp.get_clients({ bufnr = buf, name = "pyrefly" })[1]
  check(dir .. ": <leader>Te is mapped", wait_until(function() return vim.fn.maparg("<leader>Te", "n", false, true).buffer == 1 end, 5000))
  return buf, client
end
local function flip(buf, client, want, label)
  feed("<leader>Te")
  local ok = wait_until(function() return (#type_errors(buf) > 0) == want end, 15000)
  check(label, ok, describe(buf))
  check(label .. ", same pyrefly client, not restarted", not client:is_stopped() and detached == 0
    and vim.lsp.get_clients({ bufnr = buf, name = "pyrefly" })[1] == client, "detached " .. detached)
end

-- with a pyproject.toml (no [tool.pyrefly]): errors show, the toggle hides them
local wbuf, wclient = open("withproj")
if not wbuf then return end
check("withproj: type error shown", wait_until(function() return #type_errors(wbuf) > 0 end, 15000), describe(wbuf))
flip(wbuf, wclient, false, "withproj: <leader>Te hides the type error")

-- without one: no errors once pyrefly has checked the file, the toggle shows them
local nbuf, nclient = open("noproj")
if not nbuf then return end
check("noproj: its own pyrefly client", nclient ~= wclient)
local uri = vim.uri_from_bufnr(nbuf)
check("noproj: pyrefly published after getting its settings", wait_until(function() return settled[uri] end, 15000))
check("noproj: no type error", #type_errors(nbuf) == 0, describe(nbuf))
check("noproj: unknown names still reported with type errors off", wait_until(function() return vim.iter(vim.diagnostic.get(nbuf)):any(function(d) return d.code == "unknown-name" end) end, 5000), describe(nbuf))
flip(nbuf, nclient, true, "noproj: <leader>Te shows the type error")

-- the state is per client: turning noproj on left withproj off
vim.cmd.buffer(wbuf)
check("withproj: still hidden after noproj was turned on", #type_errors(wbuf) == 0, describe(wbuf))
flip(wbuf, wclient, true, "withproj: <leader>Te shows it again")
