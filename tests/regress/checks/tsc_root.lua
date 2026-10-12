-- @desc     tsc attaches to .ts/.tsx/.jsx at the lockfile or git root, runs the project's own node_modules/.bin/tsc when it is TS 7, skips a project's TS 5 for the global one, and stays off deno projects
-- @areas    lsp tools
-- @budget   40
-- @needs    tsc

local function put(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
local function tsc(buf) return vim.lsp.get_clients({ bufnr = buf, name = "tsc" })[1] end

-- the suite's global tsc (TS 7, from its mise); the harness already failed the check if it is missing
local global = require("tools").wait("tsc", FIX, 15000)
local real = global and global.path
if not check("the global tsc resolves", real ~= nil, global and global.reason) then return end

-- FIX is a git repo with no lockfile; lock/ has a package-lock.json; local/ has its own TS 7 tsc; old/ has a TS 5 one.
-- Each wrapper leaves a marker when it serves, then runs the real server; --version answers for the TS version.
local lockfile = { '{ "name": "p", "lockfileVersion": 3, "requires": true, "packages": {} }' }
local function wrapper(dir, version)
  local marker = dir .. "/served"
  local path = dir .. "/node_modules/.bin/tsc"
  put(dir .. "/package-lock.json", lockfile)
  put(path, {
    "#!/bin/sh",
    'if [ "$1" = --version ]; then echo "Version ' .. version .. '"; exit 0; fi',
    ": > " .. vim.fn.shellescape(marker),
    "exec " .. vim.fn.shellescape(real) .. ' "$@"',
  })
  vim.fn.setfperm(path, "rwxr-xr-x")
  return marker
end
put(FIX .. "/lock/package-lock.json", lockfile)
local local_marker = wrapper(FIX .. "/local", "7.0.2")
local old_marker = wrapper(FIX .. "/old", "5.9.3")
local sources = {
  { "a.ts", "export const a: number = 1;" },
  { "b.tsx", "export const B = () => <div>hi</div>;" },
  { "c.jsx", "export const C = () => <p>hi</p>;" },
}
local projects = {
  { FIX, "git root" },
  { FIX .. "/lock", "lockfile root" },
  { FIX .. "/local", "TS 7 project" },
  { FIX .. "/old", "TS 5 project" },
}

local attached = 0
for _, p in ipairs(projects) do
  local dir, label = p[1], p[2]
  for _, s in ipairs(sources) do
    put(dir .. "/" .. s[1], { s[2] })
    vim.cmd.edit(dir .. "/" .. s[1])
    local buf = vim.api.nvim_get_current_buf()
    local _, why = wait_attach(buf, { "tsc" }, 30000)
    local c = tsc(buf)
    if c then attached = attached + 1 end
    check(("%s %s (%s): tsc attaches at the project root"):format(label, s[1], vim.bo[buf].filetype),
      c ~= nil and vim.fs.normalize(c.root_dir or "") == vim.fs.normalize(dir),
      c and ("root " .. tostring(c.root_dir) .. ", want " .. dir) or table.concat(why, "; "))
  end
end
check("TS 7 project: tsc runs the project's node_modules/.bin/tsc", vim.uv.fs_stat(local_marker) ~= nil,
  "the wrapper never served; the server came from elsewhere")
check("TS 5 project: its node_modules/.bin/tsc is skipped for the global TS 7", vim.uv.fs_stat(old_marker) == nil,
  "the TS 5 wrapper served the language server")
local old = require("tools").get("tsc", FIX .. "/old")
check("TS 5 project: the resolver says why it skipped the project tsc",
  old ~= nil and old.path == real and (old.reason or ""):find("5.9.3", 1, true) ~= nil,
  old and ("%s %s (%s)"):format(old.source, tostring(old.path), tostring(old.reason)) or "nothing resolved for old/")

put(FIX .. "/deno/deno.json", { "{}" })
put(FIX .. "/deno/a.ts", { "export const d: number = 1;" })
vim.cmd.edit(FIX .. "/deno/a.ts")
local buf = vim.api.nvim_get_current_buf()
local function deno_client()
  if tsc(buf) then return tsc(buf) end
  for _, c in ipairs(vim.lsp.get_clients({ name = "tsc" })) do
    if vim.fs.normalize(c.root_dir or "") == vim.fs.normalize(FIX .. "/deno") then return c end
  end
end
-- a root_dir that takes the buffer starts a client at once; wait_attach gives a server the same 3s to appear
wait_until(function() return deno_client() ~= nil end, 3000)
local c = deno_client()
check("deno project: tsc stays off it", attached > 0 and vim.bo[buf].filetype == "typescript" and c == nil,
  attached == 0 and "tsc attached nowhere, so staying off deno proves nothing"
    or vim.bo[buf].filetype ~= "typescript" and ("filetype " .. vim.bo[buf].filetype)
    or c and ("tsc started at " .. tostring(c.root_dir)) or nil)
