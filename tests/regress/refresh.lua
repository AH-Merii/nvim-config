-- suite.sh --refresh: sync data/ to the config under test. Lazy to the lockfile, Mason to every check's
-- @needs (plus any ensure_installed list the config has; it never uninstalls), parsers to the config's list.
-- NVR_REFRESH_DRY=1 (suite.sh --refresh-dry-run): only print the Mason keep, install and remove sets.
local failed = false
local dry = vim.env.NVR_REFRESH_DRY == "1"
local suite = vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))
local function say(fmt, ...) io.stdout:write(string.format(fmt, ...), "\n") end
local function fail(fmt, ...) failed = true; say("FAIL " .. fmt, ...) end

local function lazy_sync()
  local lazy = require("lazy")
  for _, op in ipairs({ "install", "restore", "clean" }) do
    local ok, err = pcall(lazy[op], { wait = true, show = false })
    if not ok then fail("lazy %s: %s", op, err) end
  end
  local missing = {}
  for _, p in ipairs(require("lazy").plugins()) do
    if not p._.installed then table.insert(missing, p.name) end
  end
  if #missing > 0 then fail("lazy plugins not installed: %s", table.concat(missing, " ")) end
  say("lazy: %d plugins at the lockfile", #require("lazy").plugins())
end

local function plugin_opts(name)
  local p = require("lazy.core.config").plugins[name]
  return p and require("lazy.core.plugin").values(p, "opts", false) or {}
end

-- @needs of every check in the suite, not only the selected ones; same parse as lib.sh's header()
local function suite_needs()
  local needs, files = {}, {}
  for _, dir in ipairs({ "checks", "selftest", "work/*" }) do
    for _, f in ipairs(vim.fn.glob(suite .. "/" .. dir .. "/*", false, true)) do
      if f:match("%.lua$") or f:match("%.sh$") then table.insert(files, f) end
    end
  end
  for _, f in ipairs(files) do
    for _, line in ipairs(vim.fn.readfile(f)) do
      local list = line:match("^%-%- @needs +(.*)$") or line:match("^# @needs +(.*)$")
      if list then
        for name in list:gmatch("%S+") do needs[name] = true end
        break
      end
    end
  end
  return needs, #files
end

local function mason_sync()
  require("lazy").load({ plugins = { "mason.nvim", "mason-lspconfig.nvim", "mason-tool-installer.nvim" } })
  local registry = require("mason-registry")
  if not dry then -- a dry run reads the registry already in data/; a refresh can download it
    local done = false
    registry.refresh(function() done = true end)
    vim.wait(120000, function() return done end, 50)
  end
  local want = {}
  for _, t in ipairs(plugin_opts("mason-tool-installer.nvim").ensure_installed or {}) do
    want[type(t) == "table" and t[1] or t] = true
  end
  local map = require("mason-lspconfig").get_mappings().lspconfig_to_package
  for _, s in ipairs(plugin_opts("mason-lspconfig.nvim").ensure_installed or {}) do
    want[map[s] or s] = true
  end
  local needs, nfiles = suite_needs()
  for n in pairs(needs) do want[n] = true end
  if next(want) == nil then
    return fail("mason: keep-list is empty: no @needs in %d checks under %s and no ensure_installed in the config", nfiles, suite)
  end

  local keep, install, unlisted = vim.tbl_keys(want), {}, {}
  table.sort(keep)
  for _, name in ipairs(keep) do
    local ok, pkg = pcall(registry.get_package, name)
    if not ok then
      fail("mason: no package %s", name)
    elseif not pkg:is_installed() then
      table.insert(install, pkg)
    end
  end
  for _, name in ipairs(registry.get_installed_package_names()) do
    if not want[name] then table.insert(unlisted, name) end
  end
  table.sort(unlisted)
  say("mason: keep (%d): %s", #keep, table.concat(keep, " "))
  say("mason: install (%d): %s", #install, table.concat(vim.tbl_map(function(p) return p.name end, install), " "))
  say("mason: remove (0): refresh never uninstalls")
  if #unlisted > 0 then
    say("mason: installed, in no @needs, left alone (%d): %s", #unlisted, table.concat(unlisted, " "))
  end
  if dry then return end

  local pending = #install
  for _, pkg in ipairs(install) do
    say("mason: installing %s", pkg.name)
    pkg:install({}, function(success, err)
      pending = pending - 1
      if not success then fail("mason: install %s: %s", pkg.name, vim.inspect(err)) end
    end)
  end
  if not vim.wait(900000, function() return pending == 0 end, 100) then fail("mason: timed out") end
  say("mason: %d packages wanted, %d installed", vim.tbl_count(want), #registry.get_installed_package_names())
end

local function parsers_sync()
  local cfg = vim.fn.stdpath("config") .. "/lua/plugins/nvim-treesitter.lua"
  local src = table.concat(vim.fn.readfile(cfg), "\n")
  local block = src:match("local ensure_installed%s*=%s*(%b{})")
  if not block then return fail("parsers: no ensure_installed list in %s", cfg) end
  local list = {}
  for lang in block:gmatch('"([%w_]+)"') do table.insert(list, lang) end
  local ts = require("nvim-treesitter")
  local ok, err = pcall(function() ts.install(list, { summary = true }):wait(900000) end)
  if not ok then fail("parsers install: %s", err) end
  ok, err = pcall(function() ts.update(nil, { summary = true }):wait(900000) end)
  if not ok then fail("parsers update: %s", err) end
  local missing = vim.tbl_filter(function(l) return not vim.list_contains(ts.get_installed(), l) end, list)
  if #missing > 0 then fail("parsers missing: %s", table.concat(missing, " ")) end
  say("parsers: %d ensured, %d installed", #list, #ts.get_installed())
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      if not vim.g.did_very_lazy then
        vim.g.did_very_lazy = true
        vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
      end
      for _, step in ipairs(dry and { mason_sync } or { lazy_sync, mason_sync, parsers_sync }) do
        local ok, err = xpcall(step, debug.traceback)
        if not ok then fail("%s", err) end
      end
      say("REFRESH%s %s", dry and " DRY-RUN" or "", failed and "FAIL" or "OK")
      vim.cmd(failed and "cquit 1" or "qa!")
    end)
  end,
})
