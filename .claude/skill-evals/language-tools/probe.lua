-- Read-only probe of a clone's tool wiring, run inside the clone's sandboxed nvim (tests/regress/nv.sh):
--   cd <scratch> && FILES="a.zig b.lua" <clone>/tests/regress/nv.sh nightly --headless -c "luafile probe.lua"
-- Prints tab-separated facts, one per line:
--   catalog   <binary> spec=<spec> servers=<a,b> formatters=<a,b> linters=<a,b>
--   enabled   <server> lspconfig=<yes|no>
--   file      <path> ft=<ft> servers=<..> formatters=<..> linters=<..>     (what lang.of gives the buffer)
--   linterdef <name> custom=<yes|no> builtin=<yes|no> cmd=<cmd> dup=<built-in linters running the same command>
--   fmtdef    <name> builtin=<yes|no> cmd=<cmd> dup=<built-in formatters running the same command>
--   lspft     <server> <filetype,...>
--   PROBE DONE
local lang, catalog = require("lang"), require("tools.catalog")
local conform, lint = require("conform"), require("lint")
local enabled = require("lsp").servers
local function out(...) io.stdout:write(table.concat({ ... }, "\t") .. "\n") end
local function keys(t)
  local k = vim.tbl_keys(t or {})
  table.sort(k)
  return k
end
local function join(t) return table.concat(t or {}, ",") end

for _, bin in ipairs(keys(catalog.tools)) do
  local e = catalog.tools[bin]
  out("catalog", bin, "spec=" .. (e.spec or ""), "servers=" .. join(keys(e.servers)), "formatters=" .. join(e.formatters), "linters=" .. join(e.linters))
end
for _, name in ipairs(enabled) do
  out("enabled", name, "lspconfig=" .. ((pcall(function() return vim.lsp.config[name] end) and vim.lsp.config[name]) and "yes" or "no"))
  local ok, cfg = pcall(function() return vim.lsp.config[name] end)
  out("lspft", name, join(ok and cfg and cfg.filetypes or {}))
end

-- The commands of the plugins' built-in definitions, read as text (loading them can run tools)
local function builtin_commands(glob, field)
  local by_cmd, names = {}, {}
  for _, f in ipairs(vim.api.nvim_get_runtime_file(glob, true)) do
    local name = vim.fn.fnamemodify(f, ":t:r")
    names[name] = true
    local text = table.concat(vim.fn.readfile(f), "\n")
    local cmd = text:match(field .. "%s*=%s*[\"']([^\"']+)[\"']")
    if cmd then
      by_cmd[cmd] = by_cmd[cmd] or {}
      table.insert(by_cmd[cmd], name)
    end
  end
  return by_cmd, names
end
local lint_by_cmd, lint_builtin = builtin_commands("lua/lint/linters/*.lua", "cmd")
local fmt_by_cmd, fmt_builtin = builtin_commands("lua/conform/formatters/*.lua", "command")

local function others(list, name)
  return join(vim.tbl_filter(function(n) return n ~= name end, list or {}))
end

local linter_names = {}
for _, names in pairs(lint.linters_by_ft) do
  for _, n in ipairs(names) do linter_names[n] = true end
end
for n in pairs(lint.linters) do linter_names[n] = true end -- raw keys only: the config's own definitions
for _, name in ipairs(keys(linter_names)) do
  local raw = rawget(lint.linters, name)
  local def = raw or lint.linters[name]
  if type(def) == "function" then
    local ok, d = pcall(def)
    def = ok and d or nil
  end
  local cmd = type(def) == "table" and type(def.cmd) == "string" and vim.fs.basename(def.cmd) or (catalog.binary("linter", name) or "")
  out("linterdef", name, "custom=" .. (raw and "yes" or "no"), "builtin=" .. (lint_builtin[name] and "yes" or "no"), "cmd=" .. cmd,
    "dup=" .. (raw and others(lint_by_cmd[cmd], name) or ""))
end

local fmt_names = {}
for _, names in pairs(conform.formatters_by_ft) do
  for _, n in ipairs(type(names) == "table" and names or {}) do
    if type(n) == "string" then fmt_names[n] = true end
  end
end
for _, name in ipairs(keys(fmt_names)) do
  local def = conform.formatters[name]
  local cmd = type(def) == "table" and type(def.command) == "string" and vim.fs.basename(def.command) or (catalog.binary("formatter", name) or "")
  local builtin = fmt_builtin[name] == true
  out("fmtdef", name, "builtin=" .. (builtin and "yes" or "no"), "cmd=" .. cmd, "dup=" .. (builtin and "" or others(fmt_by_cmd[cmd], name)))
end

for _, path in ipairs(vim.split(vim.env.FILES or "", "%s+", { trimempty = true })) do
  local ft = vim.filetype.match({ filename = vim.fs.abspath(path) }) or ""
  local f = lang.of(ft) or { servers = {}, formatters = {}, linters = {} }
  out("file", path, "ft=" .. ft, "servers=" .. join(f.servers), "formatters=" .. join(f.formatters), "linters=" .. join(f.linters))
end
out("PROBE DONE")
vim.cmd("qa!")
