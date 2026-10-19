-- suite.sh --refresh: sync data/ to the config under test. Plugins to the lockfile (vim.pack clones what is missing),
-- the suite's mise and rustup to every check's @needs (it never uninstalls), parsers to what the languages need.
-- NVR_REFRESH_DRY=1 (suite.sh --refresh-dry-run): only print the tools wanted and which of them do not resolve.
-- NVR_REFRESH_STEPS picks the steps, in order (default: all four): plugins, tools (the suite's mise and rustup installs),
-- resolve (every need resolves through the config's resolver), parsers. The test image runs tools alone on a stub
-- config, so a config change doesn't reinstall them (tests/image/Dockerfile).
local failed = false
local dry = vim.env.NVR_REFRESH_DRY == "1"
local suite = vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2)))
-- from a new line: vim.pack's and nvim-treesitter's progress messages end without one
local function say(fmt, ...) io.stdout:write("\n", string.format(fmt, ...), "\n") end
local function fail(fmt, ...) failed = true; say("FAIL " .. fmt, ...) end

-- vim.pack installed what the lockfile has and data/ lacked when the config started (lua/app/plugins.lua). This puts
-- every plugin at the lockfile's revision, deletes what the config no longer names (and lazy.nvim's old checkouts),
-- and waits for blink's prebuilt fuzzy library, which its setup downloads.
local function plugins_sync()
  local list = require("app.plugins").list()
  local names = vim.tbl_map(function(p) return p.name end, list)
  local ok, err = pcall(vim.pack.update, names, { target = "lockfile", force = true })
  if not ok then fail("plugins: update to the lockfile: %s", err) end
  local extra = {}
  for _, p in ipairs(vim.pack.get(nil, { info = false })) do
    if not vim.list_contains(names, p.spec.name) then table.insert(extra, p.spec.name) end
  end
  if #extra > 0 then
    ok, err = pcall(vim.pack.del, extra)
    if not ok then fail("plugins: delete %s: %s", table.concat(extra, " "), err) end
    say("plugins: deleted %s", table.concat(extra, " "))
  end
  local old = vim.fs.joinpath(vim.fn.stdpath("data"), "lazy")
  if vim.uv.fs_stat(old) then
    vim.fs.rm(old, { recursive = true, force = true })
    say("plugins: deleted lazy.nvim's checkouts in %s", old)
  end

  local lock = vim.json.decode(table.concat(vim.fn.readfile(vim.go.packlockfile), "\n")).plugins
  local wrong = {}
  for _, p in ipairs(vim.pack.get(names, { info = false })) do
    local want = (lock[p.spec.name] or {}).rev
    local have = vim.trim(vim.fn.system({ "git", "-C", p.path, "rev-parse", "HEAD" }))
    if have ~= want then table.insert(wrong, ("%s at %s, lockfile %s"):format(p.spec.name, have, tostring(want))) end
  end
  for _, p in ipairs(list) do
    if not vim.uv.fs_stat(p.path) then table.insert(wrong, p.name .. " not installed") end
  end
  if #wrong > 0 then fail("plugins: %s", table.concat(wrong, "; ")) end

  local blink = vim.pack.get({ "blink.cmp" }, { info = false })[1].path .. "/target/release"
  local tag = vim.trim(vim.fn.system({ "git", "-C", vim.fs.dirname(vim.fs.dirname(blink)), "describe", "--tags", "--exact-match" }))
  local function downloaded()
    return vim.uv.fs_stat(blink .. "/libblink_cmp_fuzzy.so") and vim.trim(table.concat(vim.fn.readfile(blink .. "/version"), "")) == tag
  end
  if not vim.wait(180000, function() return pcall(downloaded) and downloaded() end, 200) then
    fail("plugins: blink's fuzzy library for %s not in %s after 3 minutes", tag, blink)
  end
  say("plugins: %d at the lockfile, blink's fuzzy library %s", #list - #wrong, tag)
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

-- Runs cmd with the sandbox env plus env, waiting up to 15 minutes; returns the vim.system result.
local function run(cmd, env)
  local ok, res = pcall(function() return vim.system(cmd, { cwd = "/", env = env, text = true, stdin = false }):wait(900000) end)
  return ok and res or { code = -1, stdout = "", stderr = tostring(res) }
end
local function first_line(res) return vim.trim(res.stderr ~= "" and res.stderr or res.stdout):match("[^\n]*$") end

-- The keep-list: every @needs, plus the binaries they call; nil after a failure.
local function keep_list()
  local catalog = require("tools.catalog")
  local needs, nfiles = suite_needs()
  local keep = vim.tbl_keys(needs)
  if #keep == 0 then
    return fail("tools: keep-list is empty: no @needs in %d checks under %s", nfiles, suite)
  end
  -- a tool's runtime and the binaries it calls come along
  for _, name in ipairs(vim.list_slice(keep)) do
    for _, extra in ipairs((catalog.tools[name] or {}).requires or {}) do
      if not needs[extra] then needs[extra] = true; table.insert(keep, extra) end
    end
  end
  table.sort(keep)
  return keep
end

-- The suite's tools: every @needs is a catalog binary (lua/tools/catalog.lua). mise tools go into the suite's
-- own global config with `mise use -g` (MISE_* point into data/mise, see lib.sh mise_env), rustup components
-- into data/rustup. Needs only the catalog, not the rest of the config.
local function tools_sync()
  local catalog = require("tools.catalog")
  local keep = keep_list()
  if not keep then return end
  local specs, components, system = {}, {}, {}
  for _, name in ipairs(keep) do
    local entry = catalog.tools[name]
    if not entry then
      fail("tools: %s is in a check's @needs but not in the catalog", name)
    elseif entry.component then
      table.insert(components, entry.component)
    elseif entry.spec then
      table.insert(specs, entry.spec .. "@latest")
    else
      table.insert(system, name)
    end
    local runtime = entry and entry.runtime and entry.runtime ~= "rust" and catalog.runtimes[entry.runtime]
    if runtime and not vim.list_contains(specs, runtime.spec) then table.insert(specs, runtime.spec) end
  end
  table.sort(specs)
  say("tools: keep (%d): %s", #keep, table.concat(keep, " "))
  say("tools: mise use -g (%d): %s", #specs, table.concat(specs, " "))
  say("tools: rustup components (%d): %s", #components, table.concat(components, " "))
  if #system > 0 then say("tools: from the system PATH (%d): %s", #system, table.concat(system, " ")) end
  say("tools: mise data %s, global config %s", vim.env.MISE_DATA_DIR, vim.env.MISE_GLOBAL_CONFIG_FILE)
  if not (vim.env.MISE_DATA_DIR or ""):find(suite, 1, true) then
    return fail("tools: MISE_DATA_DIR %s is not the suite's own; refusing to install", tostring(vim.env.MISE_DATA_DIR))
  end

  if not dry and #specs > 0 then
    vim.fn.mkdir(vim.fs.dirname(vim.env.MISE_GLOBAL_CONFIG_FILE), "p")
    local res = run({ "mise", "use", "-g", unpack(specs) }, { MISE_YES = "1" })
    if res.code ~= 0 then fail("tools: mise use -g: %s", first_line(res)) end
  end
  if not dry and #components > 0 then
    -- a minimal stable toolchain in the suite's own RUSTUP_HOME; the user's ~/.rustup is never touched
    local home = suite .. "/data/rustup"
    local env = { RUSTUP_HOME = home, CARGO_HOME = home .. "/cargo" }
    local res = run({ "rustup", "toolchain", "install", "stable", "--profile", "minimal", "--no-self-update",
      "--component", table.concat(components, ",") }, env)
    if res.code ~= 0 then fail("tools: rustup toolchain install: %s", first_line(res)) end
    res = run({ "rustup", "default", "stable" }, env)
    if res.code ~= 0 then fail("tools: rustup default stable: %s", first_line(res)) end
    vim.env.RUSTUP_HOME = home
  end
end

-- Every need must now resolve through the config's own resolver, from the suite's mise or the system, never a
-- shim or a live dir.
local function tools_resolve()
  local keep = keep_list()
  if not keep then return end
  local tools = require("tools")
  tools.refresh()
  local root = vim.fn.getcwd()
  local results
  tools.resolve_all(keep, root, function(r) results = r end)
  if not vim.wait(60000, function() return results ~= nil end, 50) then return fail("tools: resolving timed out") end
  local missing = {}
  for _, name in ipairs(keep) do
    local r = results[name]
    if not r.path then table.insert(missing, ("%s (%s)"):format(name, r.reason or r.source)) end
  end
  if #missing > 0 then
    (dry and say or fail)("tools: missing (%d): %s", #missing, table.concat(missing, "; "))
  end
  say("tools: %d needed, %d resolve", #keep, #keep - #missing)
end

-- Every parser a declared filetype's buffers need (the config's parsers.needed), so no check downloads one. The config
-- itself installs parsers only with a UI (D120), never in a headless check.
local function parsers_sync()
  local parsers = require("parsers")
  local list = {}
  for _, ft in ipairs(require("lang").filetypes()) do
    for _, l in ipairs(parsers.needed(ft)) do
      if not vim.list_contains(list, l) then table.insert(list, l) end
    end
  end
  if #list == 0 then return fail("parsers: no declared filetype needs a parser (parsers.needed)") end
  table.sort(list)
  local ts = require("nvim-treesitter")
  local ok, err = pcall(function() ts.install(list, { summary = true }):wait(900000) end)
  if not ok then fail("parsers install: %s", err) end
  ok, err = pcall(function() ts.update(nil, { summary = true }):wait(900000) end)
  if not ok then fail("parsers update: %s", err) end
  local missing = vim.tbl_filter(function(l) return not vim.list_contains(ts.get_installed(), l) end, list)
  if #missing > 0 then fail("parsers missing: %s", table.concat(missing, " ")) end
  -- nvim-treesitter relinks a language's queries only when its revision changes (install.lua, needs_update), so a link
  -- into a plugin checkout that is gone (lazy.nvim's, a removed worktree's) stays, and that language loses its
  -- injections, folds and indents without an error (D147)
  local queries = require("nvim-treesitter.config").get_install_dir("queries")
  local dangling = {}
  for name, kind in vim.fs.dir(queries) do
    if kind == "link" and not vim.uv.fs_stat(vim.fs.joinpath(queries, name)) then table.insert(dangling, name) end
  end
  if #dangling > 0 then
    fail("parsers: query links point nowhere: %s (delete site/parser, site/parser-info and site/queries under %s, then refresh)", table.concat(dangling, " "), vim.fn.stdpath("data"))
  end
  say("parsers: %d needed (%s), %d installed", #list, table.concat(list, " "), #ts.get_installed())
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      if not vim.g.did_very_lazy then
        vim.g.did_very_lazy = true
        vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
      end
      local all = { plugins = plugins_sync, tools = tools_sync, resolve = tools_resolve, parsers = parsers_sync }
      local names = dry and "tools resolve" or vim.env.NVR_REFRESH_STEPS or "plugins tools resolve parsers"
      for name in names:gmatch("%S+") do
        local ok, err = true, nil
        if all[name] then ok, err = xpcall(all[name], debug.traceback) else fail("unknown refresh step %s", name) end
        if not ok then fail("%s", err) end
      end
      say("REFRESH%s %s", dry and " DRY-RUN" or "", failed and "FAIL" or "OK")
      vim.cmd(failed and "cquit 1" or "qa!")
    end)
  end,
})
