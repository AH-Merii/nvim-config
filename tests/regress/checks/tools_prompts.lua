-- @desc     with a UI: a project mise config that pins tools asks once with three choices (two when it is untrusted), one that pins none never asks, a missing tool is offered once and only on files it runs on (in a project also for the project only), no prompt shows a command, and library code, git files and install_tools = "off" never ask; nothing installs
-- @areas    tools ui
-- @budget   40
-- @needs    jactionlint yaml-language-server
-- The UI is stubbed (nvim_list_uis) and every prompt is declined, so nothing installs. Which tools are offered
-- depends on the suite's mise: jactionlint and yaml-language-server are there, zizmor, yamllint and prettierd are not.
local tools = require("tools")
-- The Dockerfile and COMMIT_EDITMSG buffers below would start parser installs (a download and a C build) that
-- outlive the check when the build is slow; parsers are not what this check is about
require("nvim-treesitter").install = function() return { await = function() end } end
vim.api.nvim_list_uis = function() return { { width = 120, height = 40 } } end
local prompts = {}
vim.ui.select = function(items, opts, on_choice)
  local texts = vim.tbl_map(function(i) return opts.format_item and opts.format_item(i) or i end, items)
  table.insert(prompts, { kind = opts.kind, prompt = opts.prompt, items = texts })
  -- "Not now"; the project prompt is dismissed
  local decline = opts.kind == "tools.install" and vim.iter(ipairs(texts)):find(function(_, t) return vim.startswith(t, "Not now") end) or nil
  vim.schedule(function() on_choice(decline and items[decline], decline) end)
end
local ran = {}
local system = vim.system
vim.system = function(cmd, ...)
  table.insert(ran, table.concat(cmd, " "))
  return system(cmd, ...)
end
local function write(rel, lines)
  local path = FIX .. "/" .. rel
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
  return path
end
--- Opens rel and returns the prompts it raised once they settle.
local function open(rel, lines)
  local n = #prompts
  vim.cmd.edit(write(rel, lines or { "" }))
  wait_until(function() return #prompts > n end, 2000)
  vim.wait(300) -- a second prompt follows the first one's answer
  return vim.list_slice(prompts, n + 1)
end
local function show(list)
  return vim.inspect(vim.tbl_map(function(p) return p.prompt end, list))
end

local got = open("proj/a.lua", { "return 1" }) -- proj/mise.toml written below, before it opens
check("no project config: no project prompt", not vim.iter(got):any(function(p) return p.kind == "tools.project" end), show(got))

write("pinned/mise.toml", { "[tools]", 'stylua = "latest"' })
got = open("pinned/a.lua", { "return 1" })
local first = got[1]
check(
  "a project mise config asks first, three choices, Use + install says it trusts",
  first and first.kind == "tools.project" and #first.items == 3 and first.items[1]:find("trusts") ~= nil,
  vim.inspect(first)
)
got = open("pinned/b.lua", { "return 2" })
check("dismissed, it is not asked again this session", #got == 0, show(got))

write("untrusted/mise.toml", { "[env]", 'FOO = "1"', "[tools]", 'stylua = "latest"' })
got = open("untrusted/a.lua", { "return 1" })
check(
  "an untrusted config with [env] says so and offers two choices",
  got[1] and got[1].kind == "tools.project" and #got[1].items == 2 and got[1].prompt:find("Trust", 1, true) ~= nil,
  vim.inspect(got[1])
)

write("notools/mise.toml", { "[tools]" })
got = open("notools/a.lua", { "return 1" })
check("a project config that pins no tools is not asked about", not vim.iter(got):any(function(p) return p.kind == "tools.project" end), show(got))

got = open("y/a.yaml", { "a: 1" })
local plain = vim.iter(got):find(function(p) return p.kind == "tools.install" end)
check(
  "plain YAML offers its missing tools, not jactionlint or zizmor",
  plain ~= nil and plain.prompt:find("yamllint") ~= nil and not plain.prompt:find("jactionlint") and not plain.prompt:find("zizmor"),
  plain and plain.prompt
)
got = open(".github/workflows/new.yml", { "on: push", "jobs: {}" })
local wf = vim.iter(got):find(function(p) return p.kind == "tools.install" end)
check(
  "a workflow file offers only zizmor: jactionlint is installed, the YAML tools were declined",
  wf ~= nil and wf.prompt:find("zizmor") ~= nil and not wf.prompt:find("yamllint") and not wf.prompt:find("jactionlint"),
  wf and wf.prompt
)
got = open("y2/b.yaml", { "b: 1" })
check("declined tools are not offered again on another file", #got == 0, show(got))

for _, rel in ipairs({
  "venv/lib/python3.12/site-packages/pkg/Dockerfile",
  "web/node_modules/pkg/Dockerfile",
  ".git/COMMIT_EDITMSG",
}) do
  got = open(rel, { "FROM scratch" })
  check("no prompt for " .. rel, #got == 0, show(got))
end
vim.g.install_tools = "off"
got = open("off/Dockerfile", { "FROM scratch" })
check('no prompt with vim.g.install_tools = "off"', #got == 0, show(got))
vim.g.install_tools = nil
got = open("on/Dockerfile", { "FROM scratch" })
check("control: a Dockerfile elsewhere does prompt", #got > 0 and got[1].prompt:find("hadolint") ~= nil, show(got))
check(
  "in a project (the fixture is a git repo), a missing tool is also offered for the project only",
  got[1] ~= nil and vim.list_contains(got[1].items, "Install it globally with mise") and vim.list_contains(got[1].items, "Install it for this project only"),
  got[1] and vim.inspect(got[1].items)
)

-- The prompts say what happens in words; the commands behind them are not the user's concern
local commands = {}
for _, p in ipairs(prompts) do
  for _, text in ipairs({ p.prompt, unpack(p.items) }) do
    if text:find("mise use", 1, true) or text:find("mise install", 1, true) or text:find("mise trust", 1, true) or text:find("rustup component", 1, true) then
      table.insert(commands, text)
    end
  end
end
check("no prompt names a command", #prompts > 0 and #commands == 0, vim.inspect(commands))

local installs = vim.tbl_filter(function(c) return c:find(" use ") or c:find(" install") or c:find(" trust") or c:find("component add") end, ran)
check("nothing installed or trusted", #installs == 0, vim.inspect(installs))
