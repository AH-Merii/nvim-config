-- @desc     a finding that a linter and a language server both report shows once, also after a re-lint and when the server attaches after the linter reported, and still shows where the server does not run (biome outside a biome project, a disabled server)
-- @areas    lint lsp
-- @budget   150
-- @fixture  lintdup
-- @needs    biome ruff tflint rust-analyzer cargo-clippy
-- @allow-leak biome biome's daemon (biome __run_server) runs in its own session, which the server-group sweep can't reach (docs/rearchitecture-decisions.md, "Server children at quit", Known limits)
local lint = require("lint")

-- the lints nvim-lint was asked for, per buffer: a re-lint shows here even when it runs no linter
local asked = {}
local try_lint = lint.try_lint
lint.try_lint = function(...)
  local buf = vim.api.nvim_get_current_buf()
  asked[buf] = (asked[buf] or 0) + 1
  return try_lint(...)
end

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

-- Both sources of the finding have had their say: no lint runs on buf, the finding shows, and where the server that
-- reports it too runs (or is still starting) its report is in. A finding the linter reported before the server
-- attached is gone or still showing then, and so is one from a run that ended after the server attached
local function decided(buf, pat, linter, server)
  local from = sources(buf, pat)
  if #lint.get_running(buf) > 0 or #from == 0 then
    return false
  end
  for _, client in ipairs(vim.lsp.get_clients({ name = server, _uninitialized = true })) do
    if not client.initialized then
      return false
    end
  end
  if not vim.lsp.get_clients({ bufnr = buf, name = server })[1] then
    return true
  end
  local linter_ns = vim.diagnostic.get_namespace(lint.get_namespace(linter)).name
  return vim.iter(from):any(function(name) return name ~= linter_ns end)
end

-- the linter, and the server that reports the same findings
local function once(file, pat, label, linter, server)
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  -- judge once the buffer's servers are up: a slow server (biome's daemon) leaves only the linter otherwise
  wait_attach(buf, vim.tbl_filter(vim.lsp.is_enabled, (lsp_expected(buf))), 20000)
  wait_until(function() return decided(buf, pat, linter, server) end, 30000)
  local first = sources(buf, pat)
  -- leaving insert mode lints a buffer that changed since its last lint: a change that keeps the text, then the event
  local n = asked[buf] or 0
  vim.api.nvim_buf_set_lines(buf, 0, 1, false, vim.api.nvim_buf_get_lines(buf, 0, 1, false))
  vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
  local relinted = wait_until(function() return (asked[buf] or 0) > n end, 5000)
  wait_until(function() return decided(buf, pat, linter, server) end, 30000)
  local after = sources(buf, pat)
  check(label .. ": reported once on open", #first == 1, "sources: " .. table.concat(first, ","))
  check(
    label .. ": reported once after a re-lint",
    relinted and #after == 1,
    relinted and ("sources: " .. table.concat(after, ",")) or "leaving insert mode after a change linted nothing"
  )
end

once("index.ts", "noDebugger", "biome outside a biome project", "biomejs", "biome")
once("bp/index.ts", "noDebugger", "biome project", "biomejs", "biome")
once("app.py", "F401", "ruff", "ruff", "ruff")
once("main.tf", "required_version", "tflint", "tflint", "tflint")
vim.cmd.cd("clip") -- cargo clippy runs in the cwd
once("src/main.rs", "against true", "clippy", "clippy", "rust_analyzer")
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
  once(case[2], case[3], case[1] .. " with its server disabled", case[1], case[1])
end

-- a server that starts after its linter reported, as a slow one does: once it attaches, the finding shows once
do
  local buf = vim.fn.bufnr("app.py")
  vim.lsp.enable("ruff")
  local miss, why = wait_attach(buf, { "ruff" }, 20000)
  wait_until(function() return decided(buf, "F401", "ruff", "ruff") end, 30000)
  local from = sources(buf, "F401")
  check(
    "ruff attaching after its linter reported: reported once",
    #miss == 0 and #from == 1,
    #miss == 0 and ("sources: " .. table.concat(from, ",")) or table.concat(why, "; ")
  )
end
