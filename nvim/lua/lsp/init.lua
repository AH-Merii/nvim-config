-- Enables the language servers and runs each from the binary the tool resolver finds for its root (project env,
-- accepted project mise config, global mise, system PATH). A server whose binary is missing is not started and
-- raises no error; it starts once ToolsChanged says the binary turned up (install, accepted project, refresh), and
-- restarts when one of those moves the binary of a running server.

local tools = require("tools")
local catalog = tools.catalog

local M = {}

-- The servers the language files name (lua/lang/), each with its settings; none is enabled just because its binary
-- happens to be installed
local configs = require("lang").views().lsp
M.servers = vim.tbl_keys(configs)
table.sort(M.servers)

-- Roots computed here instead of by the server's own root_dir; return nil to not attach
---@type table<string, fun(buf: integer): string?>
local roots = {
  -- tsc's own root_dir runs `tsc --version` on PATH and warns when it is not TS 7; the resolver checks that instead
  tsc = function(buf)
    local root = vim.fs.root(buf, { { "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "bun.lockb", "bun.lock" }, { ".git" } })
    local deno = vim.fs.root(buf, { "deno.json", "deno.jsonc" })
    local deno_lock = vim.fs.root(buf, { "deno.lock" })
    -- A Deno config or lock at least as close as the package manager's lock makes it a Deno file
    if (deno_lock and (not root or #deno_lock > #root)) or (deno and (not root or #deno >= #root)) then
      return nil
    end
    return root or vim.fn.getcwd()
  end,
}

local bins = {} ---@type table<string, string> server -> catalog binary
local wrapped = {} ---@type table<string, function> server -> the root_dir set by wire
local rootless = {} ---@type table<string, string> server -> resolver root of its client without a root_dir, which all such buffers share
local running = {} ---@type table<string, string> server .. "\0" .. root -> binary its client was started with
local processes = setmetatable({}, { __mode = "k" }) ---@type table<vim.lsp.rpc.PublicClient, true> every server process started
-- The process group of each server started here whose children may still run (vim.lsp.rpc.start runs a server
-- detached, vim/net/_transport.lua)
local groups = require("tools.proc").groups()

-- For the unit tests
M._groups, M._sweep = groups.leaders, function(pid) groups:kill(pid) end

local warned = false
--- vim.lsp.rpc.start(...), and the pid of the process it spawned, which its client does not expose: the one vim.system
--- call it makes is watched. Warns once when that stops holding, since the sweep then misses the server.
---@return vim.lsp.rpc.PublicClient rpc, integer? pid
local function rpc_start(...)
  local system, pid, calls = vim.system, nil, 0
  vim.system = function(...)
    local obj = system(...)
    pid, calls = obj.pid, calls + 1
    return obj
  end
  local ok, rpc = pcall(vim.lsp.rpc.start, ...)
  vim.system = system
  if not ok then
    error(rpc, 0)
  end
  if (calls ~= 1 or not pid) and not warned then
    warned = true
    local msg = "vim.lsp.rpc.start made %d vim.system calls, so a server's pid is unknown: its children can outlive it"
    vim.notify(msg:format(calls), vim.log.levels.WARN, { title = "LSP" })
  end
  return rpc, calls == 1 and pid or nil
end

---@param root string
local function norm(root) return vim.fs.normalize(vim.fs.abspath(root)) end

--- Config fields that run the server from its resolved binary, with cwd = root and the tool's env.
---@param name string
---@param bin string
---@param base vim.lsp.Config the merged config before this override
---@return vim.lsp.Config
local function wiring(name, bin, base)
  local original = type(base.root_dir) == "function" and base.root_dir or nil
  local markers = base.root_markers

  ---@param root? string
  ---@param buf integer
  ---@param on_dir fun(root?: string)
  local function found(root, buf, on_dir)
    -- The original root_dir may answer from a vim.system callback, where the resolver cannot run
    if vim.in_fast_event() then
      return vim.schedule(function() found(root, buf, on_dir) end)
    end
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    -- What vim.lsp.start falls back to when root_dir gives none
    root = root or (markers and vim.fs.root(buf, markers))
    if not root and base.workspace_required then
      return
    end
    -- Else the tools' project root: one process per project, run from that project's binary. Only files outside
    -- any project share a rootless client, and they all resolve the same binary.
    root = root or tools.project_root(buf)
    local at = root or tools.root(buf)
    tools.resolve(bin, at, function(result)
      -- vim.lsp.start runs whatever on_dir gives it, so check the buffer still wants this server: it may be gone, or
      -- have another filetype (a modeline right after FileType, :set ft while resolving); FileType started what applies
      vim.schedule(function()
        local filetypes = vim.lsp.config[name].filetypes
        if not vim.api.nvim_buf_is_loaded(buf) or (filetypes and not vim.list_contains(filetypes, vim.bo[buf].filetype)) then
          return
        end
        if result.path then
          if not root then
            rootless[name] = at
          end
          on_dir(root)
        end
      end)
    end)
  end

  return {
    ---@param dispatchers vim.lsp.rpc.Dispatchers
    ---@param config vim.lsp.ClientConfig
    cmd = function(dispatchers, config)
      local root = config.root_dir or rootless[name]
      -- Resolved before root_dir called on_dir; waits only when a refresh dropped it in between
      local result = root and tools.wait(bin, root)
      if not (result and result.path) then
        error(("%s: no %s binary for %s"):format(name, bin, root or "this buffer"))
      end
      running[name .. "\0" .. norm(root)] = result.path
      -- Once the server exits, its group goes too: a restart's or :LspStop's, not only the quit's. The client sees the
      -- exit only after the server's pipes close, so a child holding them waits for the quit
      local pid
      local on_exit = dispatchers.on_exit
      dispatchers = vim.tbl_extend("force", dispatchers, {
        on_exit = function(...)
          if pid then
            groups:kill(pid)
          end
          if on_exit then
            return on_exit(...)
          end
        end,
      })
      local rpc
      rpc, pid = rpc_start({ result.path, unpack(catalog.server_args(name) or {}) }, dispatchers, { cwd = root, env = result.env })
      processes[rpc] = true
      if pid then
        groups:add(pid)
      end
      return rpc
    end,
    -- Once root_dir is set root_markers is ignored, so it finds the root itself and then waits for the binary
    root_dir = function(buf, on_dir)
      if roots[name] then
        local root = roots[name](buf)
        return root and found(root, buf, on_dir)
      elseif not original then
        return found(nil, buf, on_dir)
      end
      -- Check the binary before the original root_dir, which may run its toolchain (cargo metadata, go env);
      -- that runs from Neovim's PATH, so it gets the tool's for the call, where the toolchain may be only in mise
      tools.resolve(bin, tools.root(buf), function(result)
        if not (result.path and vim.api.nvim_buf_is_valid(buf)) then
          return
        end
        local path = vim.env.PATH
        vim.env.PATH = result.env and result.env.PATH or path
        local ok, err = pcall(original, buf, function(root) found(root, buf, on_dir) end)
        vim.env.PATH = path
        if not ok then
          error(err, 0)
        end
      end)
    end,
  }
end

--- Wraps the server's current config, again if a plugin replaced root_dir since (lazydev does for lua_ls when it loads).
---@param name string
---@return vim.lsp.Config?
local function wire(name)
  local config = vim.lsp.config[name]
  if config and (not wrapped[name] or config.root_dir ~= wrapped[name]) then
    local fields = wiring(name, bins[name], config)
    wrapped[name] = fields.root_dir
    vim.lsp.config(name, fields)
    config = vim.lsp.config[name]
  end
  return config
end

--- Whether a client of server serves buf; one that is stopping does not count, vim.lsp.start won't reuse it either.
---@param name string
---@param buf integer
local function serving(name, buf)
  return vim.iter(vim.lsp.get_clients({ bufnr = buf, name = name })):any(function(client) return not client:is_stopped() end)
end

--- Starts server for buf if it applies, the way vim.lsp.enable does on FileType.
---@param name string
---@param buf integer
local function start(name, buf)
  local config = vim.deepcopy(wire(name))
  if not config or not vim.list_contains(config.filetypes or {}, vim.bo[buf].filetype) then
    return
  end
  config.root_dir(buf, function(root)
    config.root_dir = root
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) and not serving(name, buf) then
        vim.lsp.start(config, { bufnr = buf, reuse_client = config.reuse_client })
      end
    end)
  end)
end

--- The clients running on buf: attached and not stopping. `:LspStop` and a restart stop a client a while before it
--- detaches, and a stopping client answers nothing. The one definition of a running server, for the statusline's
--- facts and for skipping the linters a server covers.
---@param buf integer
---@param name? string only this server's clients
---@return vim.lsp.Client[]
function M.running(buf, name)
  return vim.tbl_filter(function(client) return not client:is_stopped() end, vim.lsp.get_clients({ bufnr = buf, name = name }))
end

--- Stops clients and starts their servers again, from the binaries resolved now, on the buffers they served.
---@param clients vim.lsp.Client[]
function M.restart(clients)
  local served = {} ---@type { [1]: string, [2]: integer }[] server, buffer
  for _, client in ipairs(clients) do
    for buf in pairs(client.attached_buffers) do
      table.insert(served, { client.name, buf })
    end
    client:stop()
  end
  -- Wait for the old processes to exit, so two servers never share a root's caches
  local deadline = vim.uv.now() + 3000
  local function again()
    local stopping = vim.tbl_filter(function(client) return vim.lsp.get_client_by_id(client.id) ~= nil end, clients)
    if #stopping > 0 and vim.uv.now() < deadline then
      return vim.defer_fn(again, 50)
    end
    for _, client in ipairs(stopping) do
      client:stop(true)
    end
    for _, item in ipairs(served) do
      if vim.api.nvim_buf_is_loaded(item[2]) and bins[item[1]] then
        start(item[1], item[2])
      end
    end
  end
  again()
end

function M.setup()
  for _, name in ipairs(M.servers) do
    local bin = catalog.binary("server", name)
    if not bin or not vim.lsp.config[name] then
      vim.notify(("%s: %s"):format(name, bin and "nvim-lspconfig has no config" or "not in the tool catalog"), vim.log.levels.WARN, { title = "LSP" })
    else
      bins[name] = bin
      -- Above nvim-lspconfig's lsp/<name>.lua, as after/lsp/<name>.lua would be
      vim.lsp.config(name, vim.deepcopy(configs[name]))
      wire(name)
    end
  end

  local group = vim.api.nvim_create_augroup("lsp", { clear = true })
  -- Made before vim.lsp.enable's own FileType autocmd so it runs first
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      for name in pairs(bins) do
        if vim.list_contains(vim.lsp.config[name].filetypes or {}, ev.match) then
          wire(name)
        end
      end
    end,
  })
  vim.lsp.enable(vim.tbl_keys(bins))

  -- vim.lsp's exit handler (made when vim.lsp loaded, so it runs before this one) sends shutdown to the initialized
  -- clients and waits up to their exit_timeout, 0 for the default exit_timeout = false; then Neovim exits and closes
  -- the pipes of every server still running. A server busy then (yamlls parsing a big file) runs on until it reads the
  -- EOF, and tflint dies of SIGPIPE without stopping its plugin child (tflint --act-as-bundled-plugin), which runs on,
  -- orphaned. So every server process started here gets one rule: one still initializing was sent no shutdown and is
  -- terminated at once; an initialized one with exit_timeout = false gets quit_grace ms to finish the shutdown (one
  -- with a number had it in vim.lsp's handler); then whatever still runs is terminated, as Client:stop force-stops,
  -- and given quit_wait ms to exit. A server can still exit without stopping its own children: tflint killed by that
  -- SIGTERM while it starts its plugin, before it handles the signal, leaves the plugin running. So last, what is left
  -- of every server's process group is killed, the servers vim.lsp's handler already saw exit included.
  local quit_grace, quit_wait = 100, 400
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      local graced = {} ---@type table<vim.lsp.rpc.PublicClient, true>
      for _, client in ipairs(vim.lsp.get_clients()) do
        graced[client.rpc] = processes[client.rpc] and client.exit_timeout == false or nil
      end
      local left = vim.tbl_filter(function(rpc) return not rpc.is_closing() end, vim.tbl_keys(processes))
      local function closed(rpcs)
        return vim.iter(rpcs):all(function(rpc) return rpc.is_closing() end)
      end
      for _, rpc in ipairs(left) do
        if not graced[rpc] then
          rpc.terminate()
        end
      end
      vim.wait(quit_grace, function() return closed(vim.tbl_keys(graced)) end, 5)
      for _, rpc in ipairs(left) do
        rpc.terminate()
      end
      vim.wait(quit_wait, function() return closed(left) end, 5)
      groups:kill_all()
    end,
  })

  -- A server can register watched files after its client was told to stop: pyrefly registers them again while a
  -- restart or the quit above stops it. Client:stop cancelled the client's watchers before
  -- ($VIMRUNTIME/lua/vim/lsp/client.lua, Client:stop) and nothing cancels the new ones, so their inotifywait outlives
  -- the client and Neovim. Such a registration is dropped.
  local watchfiles = vim.lsp._watchfiles
  local register = watchfiles.register
  watchfiles.register = function(reg, client_id)
    local client = vim.lsp.get_client_by_id(client_id)
    if client and client:is_stopped() then
      return
    end
    return register(reg, client_id)
  end

  -- A binary that turned up or moved after an install, an accepted project config or a refresh: start its servers,
  -- and restart the ones in that root running another binary. First resolutions ("resolved") need nothing, the
  -- root_dir waiting on them starts the server.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = tools.event,
    callback = function(ev)
      if ev.data.reason == "resolved" then
        return
      end
      for name, bin in pairs(bins) do
        if vim.list_contains(ev.data.tools, bin) then
          local path = (tools.get(bin, ev.data.root) or {}).path
          local moved = vim.tbl_filter(function(client)
            local root = client.root_dir or rootless[name]
            root = root and norm(root)
            return path ~= nil and root == ev.data.root and running[name .. "\0" .. root] ~= path
          end, vim.lsp.get_clients({ name = name }))
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" and not serving(name, buf) then
              start(name, buf)
            end
          end
          -- After the loop above, which leaves their buffers to the restart
          if #moved > 0 then
            M.restart(moved)
          end
        end
      end
    end,
  })
end

-- nvim-lspconfig, for its server configs (lsp/*.lua) only. It loads at startup, so it is on the runtimepath when the
-- servers phase (lua/app/) calls setup(), which enables them and runs each from the binary mise resolves
M.plugins = {
  { src = "neovim/nvim-lspconfig", phase = "startup" },
}

return M
