-- @desc     every enabled server covering a fixture file's filetype attaches to it, whether its cmd is a table or a function; every catalog server is enabled with a cmd; no root_dir declines because its tool failed; a buffer's clients share one position encoding
-- @areas    lsp tools
-- @budget   60
-- @args     main.lua
-- @needs    lua-language-server pyrefly ruff tsc marksman tombi clangd rust-analyzer gopls bash-language-server yaml-language-server
local files = { "main.lua", "app.py", "index.ts", "notes.md", "pyproject.toml", "hello.c", "rs/src/main.rs",
  "main.go", "script.sh", ".github/workflows/ci.yml" }

-- Calls root_dir again, recording the tools it runs and the executables it finds missing.
-- Returns true if it accepted, false on a plain decline, or nil and why its tool failed.
local function probe_root(c, buf)
  local tools, root = {}, nil
  local system, executable = vim.system, vim.fn.executable
  vim.system = function(cmd, opts, on_exit)
    if type(opts) == "function" then opts, on_exit = nil, opts end
    local t = { cmd = table.concat(cmd, " ") }
    table.insert(tools, t)
    local ok, obj = pcall(system, cmd, opts, function(res)
      t.res = res
      if on_exit then on_exit(res) end
    end)
    if not ok then
      t.res = { code = -1, stderr = tostring(obj) }
      error(obj, 0)
    end
    return obj
  end
  vim.fn.executable = function(bin)
    local r = executable(bin)
    if r ~= 1 then table.insert(tools, { cmd = bin, res = { code = -1, stderr = "not executable" } }) end
    return r
  end
  local okr, err = pcall(c.root_dir, buf, function(dir) root = dir or false end)
  vim.system, vim.fn.executable = system, executable
  if not okr then return nil, "root_dir raised: " .. tostring(err) end
  wait_until(function()
    return root ~= nil or vim.iter(tools):all(function(t) return t.res ~= nil end)
  end, 20000)
  -- a tool's callback may schedule on_dir rather than call it
  if root == nil then wait_until(function() return root ~= nil end, 200) end
  if root ~= nil then return true end
  local why = {}
  for _, t in ipairs(tools) do
    if not t.res then
      table.insert(why, t.cmd .. " still running after 20s")
    elseif t.res.code ~= 0 then
      table.insert(why, string.format("%s failed (%d): %s", t.cmd, t.res.code, (t.res.stderr or ""):match("[^\n]*%S[^\n]*") or ""))
    end
  end
  if #why > 0 then return nil, table.concat(why, "; ") end
  return false
end

-- Rechecks the servers lsp_expected left out whose root_dir function declined. A plain decline is
-- valid (biome without a biome.json); one after its tool failed is not; a late accept is expected.
local function recheck_declines(buf, want)
  local ft, late, failed = vim.bo[buf].filetype, {}, {}
  local seen = {}
  for _, f in ipairs(vim.api.nvim_get_runtime_file("lsp/*.lua", true)) do
    local name = vim.fn.fnamemodify(f, ":t:r")
    local c = not seen[name] and vim.lsp.config[name]
    seen[name] = true
    if c and vim.lsp.is_enabled(name) and type(c.root_dir) == "function"
      and (c.filetypes == nil or vim.list_contains(c.filetypes, ft)) and not vim.list_contains(want, name) then
      local accepted, why = probe_root(c, buf)
      local runnable = type(c.cmd) == "function" or (type(c.cmd) == "table" and vim.fn.executable(c.cmd[1]) == 1)
      if accepted and runnable then table.insert(late, name) end
      if why then failed[name] = why end
      if accepted == false then info(vim.fn.bufname(buf) .. ": " .. name .. " root_dir declined, no tool failed") end
    end
  end
  return late, failed
end

local total = 0
local function verify(buf, label)
  local want, notes = lsp_expected(buf)
  local late, failed = recheck_declines(buf, want)
  for n, why in pairs(failed) do check(label .. ": " .. n .. " root_dir tools succeed", false, why) end
  for _, n in ipairs(late) do notes[n] = "root_dir accepted only after lsp_expected stopped waiting" end
  vim.list_extend(want, late)
  total = total + #want
  local missing, why = wait_attach(buf, want, 15000)
  for n, note in pairs(notes) do table.insert(why, n .. ": " .. note) end
  check(label .. ": expected servers attach", #missing == 0,
    "want " .. table.concat(want, ",") .. (#why > 0 and ("; " .. table.concat(why, "; ")) or ""))
  local encodings = {}
  for _, cl in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
    encodings[cl.offset_encoding] = (encodings[cl.offset_encoding] or "") .. cl.name .. " "
  end
  check(label .. ": attached clients share one position encoding", vim.tbl_count(encodings) <= 1, vim.inspect(encodings))
end
-- a file given on the command line is opened before lazy and VeryLazy run
verify(vim.api.nvim_get_current_buf(), "startup arg " .. vim.fn.argv(0))
for _, f in ipairs(files) do
  vim.cmd.edit(f)
  verify(vim.api.nvim_get_current_buf(), f)
end
check("some server was expected at all", total > 0, total .. " expected attachments")
-- lsp_expected only expects enabled servers with a config: a catalog server left out of vim.lsp.enable, or
-- with no config (nvim-lspconfig not loaded), would never be expected anywhere
local bad = vim.tbl_filter(function(n)
  local c = vim.lsp.config[n]
  return not (vim.lsp.is_enabled(n) and c and c.cmd)
end, require("tools.catalog").servers())
check("every catalog server is enabled and has a config with a cmd", #bad == 0, table.concat(bad, ","))
