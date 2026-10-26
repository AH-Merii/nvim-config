-- @desc     the missing-tool prompt's answers: Later asks again next session, Not for this project stays quiet in that project (next session too) and still asks in another, a global install isn't asked again, and an old offered.json entry no longer silences a tool
-- @areas    tools ui
-- @budget   40
-- The UI is stubbed (nvim_list_uis) and installs are stubbed, so nothing installs. hadolint is not in the suite's mise,
-- so a Dockerfile offers it. A new session is the prompts' module loaded again: what it kept in memory is gone, and
-- what it saved in the state dir stays.
require("nvim-treesitter").install = function() return { await = function() end } end
vim.api.nvim_list_uis = function() return { { width = 120, height = 40 } } end
local tools = require("tools")
local ux = require("tools.ux")

local function new_session()
  package.loaded["tools.ux"] = nil
  ux = require("tools.ux")
  ux.setup()
  tools.refresh()
end

local prompts = {}
local pick ---@type string? the start of the option to pick in a missing-tool prompt; nil dismisses it
vim.ui.select = function(items, opts, on_choice)
  local texts = vim.tbl_map(function(i) return opts.format_item and opts.format_item(i) or i end, items)
  table.insert(prompts, { kind = opts.kind, prompt = opts.prompt, items = texts })
  local i = opts.kind == "tools.install" and pick and vim.iter(ipairs(texts)):find(function(_, t) return vim.startswith(t, pick) end) or nil
  vim.schedule(function() on_choice(i and items[i], i) end)
end

-- A global install puts hadolint on the system PATH, as mise would put it in the global tools
local bin = FIX .. "/.bin"
local installed = {}
tools.apply = function(items, _, cb)
  vim.list_extend(installed, items)
  vim.fn.mkdir(bin, "p")
  vim.fn.writefile({ "#!/bin/sh", "echo 'Haskell Dockerfile Linter 2.12.0'" }, bin .. "/hadolint")
  vim.uv.fs_chmod(bin .. "/hadolint", tonumber("755", 8))
  vim.env.PATH = bin .. ":" .. vim.env.PATH
  tools.refresh(nil, "installed")
  vim.schedule(function() cb(true, {}, {}) end)
end

local function write(rel, lines)
  local path = FIX .. "/" .. rel
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  return path
end
--- Opens rel and returns the hadolint prompt it raised, once its check has nothing left to ask
local function open(rel)
  local n = #prompts
  vim.cmd.edit(write(rel, { "FROM scratch" }))
  local scheduled = false
  vim.schedule(function() scheduled = true end)
  if not wait_until(function() return scheduled and not ux.asking() end, 10000) then
    check("the prompts for " .. rel .. " are decided within 10s", false)
  end
  return vim.iter(vim.list_slice(prompts, n + 1)):find(function(p) return p.kind == "tools.install" and p.prompt:find("hadolint", 1, true) end)
end
local function items(p) return p and vim.inspect(p.items) end
-- Each project is a dir with a project marker, inside the fixture's git repo
for _, project in ipairs({ "old", "later", "quiet", "other", "global", "after" }) do
  write(project .. "/pyproject.toml", { "[project]" })
end

-- Migration: "Not now" used to save the tool in offered.json, which kept it from being asked in any project, ever
local offered = vim.fs.joinpath(vim.fn.stdpath("state"), "tools", "offered.json")
vim.fn.mkdir(vim.fs.dirname(offered), "p")
vim.fn.writefile({ vim.json.encode({ ["global:hadolint@latest"] = "2026-10-15" }) }, offered)
pick = "Later"
local got = open("old/Dockerfile")
check("a tool saved by the old Not now is asked about", got ~= nil)

-- Later silences the tool everywhere this session, so each answer below starts a session of its own
new_session()
got = open("later/Dockerfile")
check(
  "the prompt offers Later and Not for this project, besides the installs",
  got ~= nil
    and vim.iter(got.items):any(function(t) return vim.startswith(t, "Later") end)
    and vim.iter(got.items):any(function(t) return vim.startswith(t, "Not for this project") end)
    and vim.list_contains(got.items, "Install it globally with mise")
    and vim.list_contains(got.items, "Install it for this project only"),
  items(got)
)
check("Later: not asked again this session", open("later/sub/Dockerfile") == nil)
new_session()
check("Later: asked again next session", open("later/sub2/Dockerfile") ~= nil)

new_session()
pick = "Not for this project"
check("Not for this project: asked first", open("quiet/Dockerfile") ~= nil)
check("Not for this project: not asked again in that project", open("quiet/sub/Dockerfile") == nil)
check("Not for this project: still asked in another project", open("other/Dockerfile") ~= nil)
new_session()
check("Not for this project: not asked in that project next session", open("quiet/sub2/Dockerfile") == nil)

new_session()
pick = "Install it globally"
got = open("global/Dockerfile")
check("a global install installs the tool globally", got ~= nil and #installed == 1 and installed[1].install.kind == "global", vim.inspect(installed))
new_session()
check("a globally installed tool is not asked about next session", open("after/Dockerfile") == nil)
