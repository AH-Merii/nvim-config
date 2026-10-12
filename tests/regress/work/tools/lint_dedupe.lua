-- @desc     a finding that a linter and a language server both report shows once, also after a re-lint, and still shows where the server does not run (biome outside a biome project, a disabled server)
-- @areas    lint lsp
-- @budget   150
-- @fixture  lintdup
-- @needs    biome ruff tflint rust-analyzer
local lint = require("lint")

-- names of the namespaces reporting a diagnostic whose code or message contains `pat`
local function sources(buf, pat)
  local seen = {}
  for _, d in ipairs(vim.diagnostic.get(buf)) do
    if tostring(d.code or ""):find(pat, 1, true) or d.message:find(pat, 1, true) then
      seen[vim.diagnostic.get_namespace(d.namespace).name] = true
    end
  end
  local names = vim.tbl_keys(seen)
  table.sort(names)
  return names
end

local function settled(buf, pat)
  return #sources(buf, pat) > 0 and #lint.get_running(buf) == 0
end

local function once(file, pat, label)
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  -- judge once the buffer's servers are up: a slow server (biome's daemon) leaves only the linter otherwise
  wait_attach(buf, vim.tbl_filter(vim.lsp.is_enabled, (lsp_expected(buf))), 20000)
  wait_until(function() return settled(buf, pat) end, 30000)
  -- a second source would show up while a server finishes attaching; stop early if it does
  wait_until(function() return #sources(buf, pat) > 1 end, 3000)
  local first = sources(buf, pat)
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
  wait_until(function() return settled(buf, pat) end, 30000)
  wait_until(function() return #sources(buf, pat) > 1 end, 3000)
  local after = sources(buf, pat)
  check(label .. ": reported once on open", #first == 1, "sources: " .. table.concat(first, ","))
  check(label .. ": reported once after a re-lint", #after == 1, "sources: " .. table.concat(after, ","))
end

once("index.ts", "noDebugger", "biome outside a biome project")
once("bp/index.ts", "noDebugger", "biome project")
once("app.py", "F401", "ruff")
once("main.tf", "required_version", "tflint")
vim.cmd.cd("clip") -- cargo clippy runs in the cwd
once("src/main.rs", "against true", "clippy")
do
  local miss, why = wait_attach(0, { "rust_analyzer" }, 20000)
  info("clippy case: rust_analyzer " .. (#miss == 0 and "attached" or ("not attached: " .. table.concat(why, "; ")))
    .. "; sources: " .. table.concat(sources(0, "against true"), ","))
end
vim.cmd.cd("..")

-- with the server off, the linter still reports; wipe and reopen so the buffer is new
for _, case in ipairs({ { "ruff", "app.py", "F401" }, { "tflint", "main.tf", "required_version" } }) do
  vim.lsp.enable(case[1], false)
  for _, client in ipairs(vim.lsp.get_clients({ name = case[1] })) do
    client:stop(true)
  end
  vim.cmd("silent! bwipeout! " .. vim.fn.fnameescape(case[2]))
  wait_until(function() return #vim.lsp.get_clients({ name = case[1] }) == 0 end, 5000)
  once(case[2], case[3], case[1] .. " with its server disabled")
end
