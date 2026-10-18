-- @desc     in each fixture buffer (LSP, no LSP, outside git, a repo with a GitHub remote) every which-key leaf whose keys are a keymap in some context has a keymap here too, and no which-key group is shown empty
-- @areas    which-key keys lsp git treesitter
-- @budget   60
-- @args     main.lua
-- @needs    lua-language-server
-- A leaf never mapped in any visited context labels a native
-- command (]s, za, <C-W>...); those are listed as INFO, not failed.

local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end
-- async vim.system calls whose on_exit has not run yet (the remote checks behind gitbrowse and PR review)
local inflight = 0
local real_system = vim.system
vim.system = function(cmd, opts, on_exit)
  -- a language server runs under vim.system with stdin open and lives as long as the check
  if not on_exit or (opts and opts.stdin == true) then return real_system(cmd, opts, on_exit) end
  inflight = inflight + 1
  local ok, obj = pcall(real_system, cmd, opts, function(...)
    local okc, err = pcall(on_exit, ...)
    inflight = inflight - 1
    if not okc then error(err, 0) end
  end)
  if not ok then
    inflight = inflight - 1
    error(obj, 0)
  end
  return obj
end
local function settle()
  for _ = 1, 5 do
    wait_until(function() return inflight == 0 end, 5000)
    flush()
    if inflight == 0 then return end
  end
end

-- which-key schedules loading its spec when set up after VimEnter
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded, not loaded and "which-key.config never reached loaded" or nil) then return end
local Buf = require("which-key.buf")
local SKIP = { ["'"] = true, ["`"] = true, ['"'] = true }

local NOGIT = vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/nogit"
vim.fn.mkdir(NOGIT, "p")
vim.fn.writefile({ "plain text" }, NOGIT .. "/plain.txt")
-- a repo with a GitHub remote, so remote-gated maps are mapped in some context and their labels get judged
local GH = FIX .. "/.nvr-gh"
vim.system({ "git", "init", "-q", GH }):wait()
vim.system({ "git", "-C", GH, "remote", "add", "origin", "git@github.com:x/y.git" }):wait()
vim.fn.writefile({ "x" }, GH .. "/file.txt")

local function nodes(buf, mode)
  local out = {}
  local function walk(node)
    for _, child in ipairs(node:children()) do
      if not child:is_plugin() and not SKIP[child.path[1]] then
        out[#out + 1] = child
        walk(child)
      end
    end
  end
  walk(Buf.get({ buf = buf, mode = mode, update = true }).tree.root)
  return out
end

local files = {
  { "main.lua" }, { "app.py" }, { "index.ts" }, { "notes.md" }, { "pyproject.toml" }, { "app.conf" }, { "main.go" },
  { NOGIT .. "/plain.txt", NOGIT },
  { GH .. "/file.txt", GH },
}
local mapped, seen, clients = {}, {}, 0
for _, f in ipairs(files) do
  vim.cmd.edit(f[1])
  local buf = vim.api.nvim_get_current_buf()
  if f[2] then vim.cmd.lcd(f[2]) end
  local missing, why = wait_attach(buf, (lsp_expected(buf)), 15000)
  if #missing > 0 then info(f[1] .. ": servers missing: " .. table.concat(why, "; ")) end
  clients = clients + #vim.lsp.get_clients({ bufnr = buf })
  if vim.fs.root(vim.api.nvim_buf_get_name(buf), ".git") then
    wait_until(function() return vim.b[buf].gitsigns_status_dict ~= nil end, 5000)
  end
  settle()
  local per = {}
  for _, mode in ipairs({ "n", "x" }) do
    per[mode] = nodes(buf, mode)
    for _, node in ipairs(per[mode]) do
      if node.keymap then mapped[mode .. node.keys] = true end
    end
  end
  seen[#seen + 1] = { name = vim.fn.fnamemodify(f[1], ":t"), per = per }
end
check("some buffer has an LSP client, so LSP-gated labels are judged", clients > 0, clients .. " client attachments")

local native = {}
for _, s in ipairs(seen) do
  local ghosts, empty, leaves = {}, {}, 0
  for mode, list in pairs(s.per) do
    for _, node in ipairs(list) do
      if node:is_group() or (node.mapping and node.mapping.group) then
        if #node:children() == 0 then empty[#empty + 1] = mode .. ":" .. node.keys end
      else
        leaves = leaves + 1
        if not node.keymap then
          if mapped[mode .. node.keys] then
            ghosts[#ghosts + 1] = ("%s:%s %q"):format(mode, node.keys, type(node.desc) == "string" and node.desc or "")
          else
            native[mode .. ":" .. node.keys] = true
          end
        end
      end
    end
  end
  table.sort(ghosts)
  check(s.name .. ": no which-key label without its keymap", #ghosts == 0, leaves .. " visible leaves" .. (#ghosts > 0 and (", ghosts: " .. table.concat(ghosts, " ")) or ""))
  check(s.name .. ": no empty which-key group", #empty == 0, #empty > 0 and ("empty: " .. table.concat(empty, " ")) or nil)
end
local nat = vim.tbl_keys(native)
table.sort(nat)
info("native-command labels (no keymap in any context): " .. table.concat(nat, " "))
vim.cmd.cd(FIX)
vim.system = real_system
