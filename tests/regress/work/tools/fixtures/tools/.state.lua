-- --cmd for the install_*.sh checks: NVR_INSTALL_TOOLS sets vim.g.install_tools as options.lua would;
-- records notifications and file-buffer BufEnters; NVR_TOOLS_STATE() returns JSON for --remote-expr.
if (vim.env.NVR_INSTALL_TOOLS or "") ~= "" then vim.g.install_tools = vim.env.NVR_INSTALL_TOOLS end
local notes, bufenters = {}, 0
local notify = vim.notify
vim.notify = function(msg, ...)
  table.insert(notes, tostring(msg))
  return notify(msg, ...)
end
vim.api.nvim_create_autocmd("BufEnter", { callback = function(ev)
  if vim.bo[ev.buf].buftype == "" and vim.api.nvim_buf_get_name(ev.buf) ~= "" then bufenters = bufenters + 1 end
end })

function NVR_TOOLS_STATE()
  local ok, reg = pcall(require, "mason-registry")
  local bufs, installing = {}, {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) then
      local diags = {}
      for _, d in ipairs(vim.diagnostic.get(b)) do
        local ns = vim.diagnostic.get_namespace(d.namespace).name
        diags[ns] = (diags[ns] or 0) + 1
      end
      local clients = vim.lsp.get_clients({ bufnr = b })
      table.insert(bufs, {
        name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t"), ft = vim.bo[b].filetype, bt = vim.bo[b].buftype,
        mod = vim.bo[b].modified, diags = diags,
        clients = vim.tbl_map(function(c) return c.name end, clients),
        bins = vim.tbl_map(function(c) return type(c.config.cmd) == "table" and vim.fn.exepath(c.config.cmd[1]) or "(cmd function)" end, clients),
      })
    end
  end
  for _, p in ipairs(ok and reg.get_all_packages() or {}) do
    if p:is_installing() then table.insert(installing, p.name) end
  end
  local all = vim.list_extend({}, notes)
  local okn, hist = pcall(function() return Snacks.notifier.get_history() end)
  for _, h in ipairs(okn and hist or {}) do table.insert(all, tostring(h.msg)) end
  return vim.json.encode({
    installed = ok and reg.get_installed_package_names() or {}, installing = installing, bufs = bufs,
    notes = all, bufenters = bufenters, path_head = vim.split(vim.env.PATH, ":")[1],
  })
end

-- install_host.sh: the binary each language server was spawned from, keyed by its rpc client
local spawned = setmetatable({}, { __mode = "k" })
local rpc_start = vim.lsp.rpc.start
vim.lsp.rpc.start = function(cmd, ...)
  local client = rpc_start(cmd, ...)
  if type(client) == "table" and type(cmd) == "table" then spawned[client] = vim.fn.exepath(cmd[1]) end
  return client
end

local roots = {} -- "<buf>:<server>" -> { at = hrtime, dir = string|false|nil }

-- whether server's root_dir accepts buf; a root_dir function declines by never calling on_dir
local function root_ok(buf, name, c)
  if type(c.root_dir) == "function" then
    local key = buf .. ":" .. name
    if not roots[key] then
      local r = { at = vim.uv.hrtime() }
      roots[key] = r
      if not pcall(c.root_dir, buf, function(dir) r.dir = dir or false end) then r.dir = false end
    end
    local r = roots[key]
    return r.dir ~= nil or (vim.uv.hrtime() - r.at) < 3e9
  elseif c.workspace_required and c.root_markers then
    return vim.fs.root(buf, c.root_markers) ~= nil
  end
  return true
end

-- Per file buffer: (a) servers Mason installed for its filetype and whether they attached, (b) where
-- attached Mason servers were spawned from, (c) formatters and linters whose command a Mason package
-- provides (registry bin names) and whether that package is installed and the command on PATH.
function NVR_TOOLS_HOST()
  local registry = require("mason-registry")
  local maps = require("mason-lspconfig").get_mappings()
  local mason_dir = vim.fs.normalize(vim.fn.stdpath("data")) .. "/mason/"
  local providers, installing = {}, {}
  for _, pkg in ipairs(registry.get_all_packages()) do
    for bin in pairs(pkg.spec.bin or {}) do
      providers[bin] = providers[bin] or {}
      table.insert(providers[bin], pkg.name)
    end
    if pkg:is_installing() then table.insert(installing, pkg.name) end
  end
  local installed = registry.get_installed_package_names()
  local done = #installing == 0
  local bufs = {}
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" and vim.api.nvim_buf_get_name(b) ~= "" then
      local ft = vim.bo[b].filetype
      local e = { name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":t"), ft = ft,
        attached = {}, expected = {}, missing = {}, bad_bins = {}, tools = {}, tools_bad = {} }
      for _, c in ipairs(vim.lsp.get_clients({ bufnr = b })) do
        table.insert(e.attached, c.name)
        local pkg = maps.lspconfig_to_package[c.name]
        if pkg and vim.list_contains(installed, pkg) then
          local bin = spawned[c.rpc] or "(not spawned from a command)"
          if not vim.startswith(vim.fs.normalize(bin), mason_dir) then table.insert(e.bad_bins, c.name .. "=" .. bin) end
        end
      end
      for _, pkg in ipairs(installed) do
        local name = maps.package_to_lspconfig[pkg]
        local c = name and vim.lsp.config[name]
        if c and (c.filetypes == nil or vim.list_contains(c.filetypes, ft)) and root_ok(b, name, c) then
          table.insert(e.expected, name)
          if not vim.list_contains(e.attached, name) then table.insert(e.missing, name) end
        end
      end
      local function tool(kind, name, cmd)
        local bin = type(cmd) == "string" and vim.fs.basename(cmd) or nil
        local pkgs = bin and providers[bin]
        if not pkgs then return end
        local t = { kind = kind, name = name, bin = bin, packages = pkgs,
          installed = vim.iter(pkgs):any(function(p) return vim.list_contains(installed, p) end),
          on_path = vim.fn.executable(cmd) == 1 }
        table.insert(e.tools, t)
        if not (t.installed and t.on_path) then table.insert(e.tools_bad, name .. " (" .. table.concat(pkgs, "|") .. ")") end
      end
      local conform = require("conform")
      for _, f in ipairs(conform.list_formatters_for_buffer(b)) do
        tool("formatter", f, conform.get_formatter_info(f, b).command)
      end
      local lint, seen = require("lint"), {}
      for _, x in ipairs({ ft, unpack(vim.split(ft, ".", { plain = true })) }) do
        for _, l in ipairs(lint.linters_by_ft[x] or {}) do
          if not seen[l] then
            seen[l] = true
            local ok, cmd = pcall(function()
              local linter = lint.linters[l]
              linter = type(linter) == "function" and linter() or linter
              return type(linter.cmd) == "function" and linter.cmd() or linter.cmd
            end)
            tool("linter", l, ok and cmd or nil)
          end
        end
      end
      done = done and #e.missing == 0 and #e.tools_bad == 0
      table.insert(bufs, e)
    end
  end
  return vim.json.encode({ installed = installed, installing = installing, done = done, bufs = bufs })
end
