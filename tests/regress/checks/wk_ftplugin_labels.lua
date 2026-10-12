-- @desc     every bracket map the runtime python, go, rust, php and markdown ftplugins set shows a which-key label, not its rhs, and is otherwise the ftplugin's own map; no label outlives its map or shows where the maps are off
-- @areas    which-key keys editing
-- @budget   40
-- @args     app.py
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded) then return end
local Buf, Util = require("which-key.buf"), require("which-key.util")
local MODES = { "n", "x", "o" }
local FTS = { "python", "go", "rust", "php", "markdown" }
local SAME = { "rhs", "noremap", "silent", "expr", "nowait", "script", "sid", "mode", "abbr" }

local function flush()
  local ran = false
  vim.schedule(function() ran = true end)
  wait_until(function() return ran end, 1000)
end

-- buffer-local maps on lhs starting with ] or [, without which-key's own triggers
local function brackets(buf, mode)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    if m.lhs:match("^[%[%]].") and not (m.desc or ""):find("which-key-trigger", 1, true) then out[m.lhs] = m end
  end
  return out
end

-- the label which-key shows for lhs, false for none (a node without one prints its rhs), and whether it shows a node
local function label(buf, mode, lhs)
  local m = Buf.get({ buf = buf, mode = mode, update = true })
  local node = m and m.tree.root:find(Util.keys(lhs, { norm = true }))
  if not node then return false, false end
  local d = node.desc
  if type(d) == "function" then d = d() end
  return type(d) == "string" and d ~= "" and d or false, true
end

local function scratch(ft)
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  if ft then vim.bo[buf].filetype = ft end
  flush()
  return buf
end

-- what the runtime ftplugin maps, sourced by hand with FileType ignored, so nothing of the config runs
local ref, all = {}, {}
for _, ft in ipairs(FTS) do
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  local ei = vim.o.eventignore
  vim.o.eventignore = "FileType"
  vim.bo[buf].filetype = ft
  vim.o.eventignore = ei
  for _, ext in ipairs({ "vim", "lua" }) do
    local f = ("%s/ftplugin/%s.%s"):format(vim.env.VIMRUNTIME, ft, ext)
    if vim.uv.fs_stat(f) then vim.cmd.source(f) end
  end
  ref[ft] = {}
  for _, mode in ipairs(MODES) do
    ref[ft][mode] = brackets(buf, mode)
    for lhs in pairs(ref[ft][mode]) do all[mode .. " " .. lhs] = { mode, lhs } end
  end
  vim.cmd("bwipeout!")
end

-- labels which-key shows for these keys in a buffer with no filetype maps
local base = {}
do
  local buf = scratch("text")
  for id, ml in pairs(all) do base[id] = label(buf, ml[1], ml[2]) end
  vim.cmd("bwipeout!")
end

---@return table<string, string|false> labels by "mode lhs"
local function judge(name, buf, ft)
  local seen, bare, changed, labels = 0, {}, {}, {}
  for _, mode in ipairs(MODES) do
    local now = brackets(buf, mode)
    for lhs, r in pairs(ref[ft][mode]) do
      local m = now[lhs]
      -- a map with another rhs replaced the ftplugin's, so it is not the ftplugin's to label
      if m and (m.rhs == r.rhs and (m.callback ~= nil) == (r.callback ~= nil)) then
        seen = seen + 1
        for _, k in ipairs(SAME) do
          if m[k] ~= r[k] then changed[#changed + 1] = ("%s:%s %s %s->%s"):format(mode, lhs, k, tostring(r[k]), tostring(m[k])) end
        end
        local l, shown = label(buf, mode, lhs)
        labels[mode .. " " .. lhs] = l
        if shown and not l then bare[#bare + 1] = mode .. ":" .. lhs end
      else
        info(("%s: %s:%s is not the ftplugin's map here"):format(name, mode, lhs))
      end
    end
  end
  table.sort(bare)
  check(name .. ": no ftplugin bracket map reaches which-key without a label", seen > 0 and #bare == 0,
    seen .. " maps" .. (#bare > 0 and (", rhs shown for: " .. table.concat(bare, " ")) or ""))
  check(name .. ": the ftplugin's bracket maps are unchanged but for their label", #changed == 0, #changed > 0 and table.concat(changed, "; ") or nil)
  return labels
end

-- where a key has no map, which-key shows what it shows in a plain buffer
local function no_strays(name, buf)
  local stray, judged = {}, 0
  for id, ml in pairs(all) do
    local mode, lhs = ml[1], ml[2]
    if vim.tbl_isempty(vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, mode, false, true) end)) then
      judged = judged + 1
      local l = label(buf, mode, lhs)
      if l ~= base[id] then stray[#stray + 1] = ("%s:%s %q"):format(mode, lhs, tostring(l)) end
    end
  end
  table.sort(stray)
  check(name .. ": no label for an unmapped filetype key", judged > 0 and #stray == 0, judged .. " unmapped" .. (#stray > 0 and (", labelled: " .. table.concat(stray, " ")) or ""))
end

-- a fresh buffer of each filetype
local fresh = {}
for _, ft in ipairs(FTS) do
  local buf = scratch(ft)
  fresh[ft] = judge(ft, buf, ft)
  vim.cmd("bwipeout!")
end

-- the startup file, then the filetype set again and the file edited again
vim.cmd.edit(FIX .. "/app.py")
local py = vim.api.nvim_get_current_buf()
flush()
judge("app.py", py, "python")
vim.bo[py].filetype = "python"
flush()
judge("app.py, filetype set again", py, "python")
vim.cmd.edit()
flush()
judge("app.py, :edit", py, "python")

-- python to markdown in the same buffer: markdown's maps, labelled as in a fresh markdown buffer, and no python label left
vim.bo[py].filetype = "markdown"
flush()
local md = judge("app.py as markdown", py, "markdown")
local differ = {}
for id, l in pairs(md) do
  if l ~= fresh.markdown[id] then differ[#differ + 1] = ("%s %q vs fresh %q"):format(id, tostring(l), tostring(fresh.markdown[id])) end
end
check("app.py as markdown: labels as in a fresh markdown buffer", #differ == 0, #differ > 0 and table.concat(differ, "; ") or nil)
no_strays("app.py as markdown", py)

-- the ftplugin maps turned off
vim.g.no_python_maps = 1
no_strays("python, no_python_maps", scratch("python"))
vim.cmd("bwipeout!")
vim.g.no_python_maps = nil
vim.g.no_plugin_maps = 1
for _, ft in ipairs(FTS) do
  no_strays(ft .. ", no_plugin_maps", scratch(ft))
  vim.cmd("bwipeout!")
end
vim.g.no_plugin_maps = nil
