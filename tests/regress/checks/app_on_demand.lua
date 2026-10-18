-- @desc     an on-demand plugin (github-pr-reviewer) is not loaded at VeryLazy and none of its global maps exist; the first use of one of its commands loads it and runs the plugin's own command with the range given; a deferred plugin's command used before VeryLazy (:Trouble) runs trouble's own with its arguments
-- @areas    startup git keys
-- @budget   20
-- @args     main.lua
-- github-pr-reviewer's setup maps <C-h>, <C-l> and <C-e> globally, which is why it is on demand (features/git.lua).
local NAME = "github-pr-reviewer.nvim"
local plugins = require("app.plugins")
local function entry()
  for _, p in ipairs(plugins.list()) do
    if p.name == NAME then return p end
  end
end
if not check("precondition: " .. NAME .. " is on demand", (entry() or {}).phase == "on_demand", vim.inspect(entry())) then
  return
end

-- The harness has fired VeryLazy by now
check(NAME .. " is not loaded after VeryLazy", entry().loaded == false)
local theirs = {}
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if (m.desc or ""):find("PR review mode", 1, true) then table.insert(theirs, m.lhs) end
end
check("none of its global maps exist before it loads", #theirs == 0, table.concat(theirs, " "))

-- :PRSuggestChange with a range asks which kind of suggestion (vim.ui.select) once it holds the range's lines
local asked
vim.ui.select = function(_, opts, on_choice)
  local sel = require("github-pr-reviewer")._visual_selection or {}
  asked = { prompt = opts.prompt, from = sel.start_line, to = sel.end_line }
  on_choice(nil)
end
local ok, err = pcall(vim.cmd, "2,3PRSuggestChange")
check("the first :PRSuggestChange runs without error", ok, err)
check("the first :PRSuggestChange loads " .. NAME, entry().loaded == true)
check(
  "the plugin's own :PRSuggestChange runs, with the range 2,3",
  asked ~= nil and asked.prompt == "Suggest code change:" and asked.from == 2 and asked.to == 3,
  vim.inspect(asked)
)

-- A deferred plugin's command used before VeryLazy, as `nvim +cmd` does: a headless nvim with no harness never gets
-- VeryLazy, so :Trouble is still the stub there. Its arguments must reach trouble's own command: without them,
-- trouble asks for a mode (vim.ui.select) instead of opening the quickfix list
local out, probe = vim.fn.tempname(), vim.fn.tempname() .. ".lua"
vim.fn.writefile({
  "vim.wait(200)",
  "local ok, open = pcall(function() return require('trouble').is_open({ mode = 'qflist' }) end)",
  "vim.fn.writefile({ vim.json.encode({ very_lazy = vim.g.did_very_lazy == true, open = ok and open,",
  "  asked = _G.NVR_ASKED or false, errmsg = vim.v.errmsg }) }, vim.env.NVR_OUT)",
}, probe)
local child = vim.system({
  vim.env.NV, vim.env.V, "--headless",
  "-c", "lua vim.ui.select = function(_, opts) _G.NVR_ASKED = opts.prompt or true end",
  "-c", [[call setqflist([{"filename": "main.lua", "lnum": 1, "text": "item"}])]],
  "-c", "Trouble qflist open",
  "-c", "luafile " .. probe,
  "-c", "qa!",
  "main.lua",
}, { stdin = false, env = { NVR_OUT = out } }):wait(15000)
local r = vim.fn.filereadable(out) == 1 and vim.json.decode(table.concat(vim.fn.readfile(out), "\n")) or nil
os.remove(out)
os.remove(probe)
if check("the child reported", r ~= nil, "exit " .. tostring(child.code)) then
  check("precondition: the child never got VeryLazy", r.very_lazy == false)
  check(":Trouble qflist open before VeryLazy opens the quickfix list in trouble, its arguments passed on",
    r.open == true and r.asked == false and r.errmsg == "", vim.inspect(r))
end
