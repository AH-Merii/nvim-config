-- @desc     ts_ls attaches to .ts/.tsx/.jsx at the lockfile or git root, runs the project's own node_modules/.bin server when there is one, and stays off deno projects
-- @areas    lsp installer
-- @budget   25
-- @needs    typescript-language-server

local function put(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(lines, path)
end
local function ts(buf) return vim.lsp.get_clients({ bufnr = buf, name = "ts_ls" })[1] end

local real = vim.fn.exepath("typescript-language-server")
if real == "" then
  check("typescript-language-server is on PATH", false, "Mason's bin dir has no typescript-language-server")
  return
end

-- FIX is a git repo with no lockfile; lock/ has a package-lock.json; local/ also has its own server;
-- the wrapper leaves a marker, then runs the real server
local lockfile = { '{ "name": "p", "lockfileVersion": 3, "requires": true, "packages": {} }' }
local marker = FIX .. "/local/used-local-server"
local wrapper = FIX .. "/local/node_modules/.bin/typescript-language-server"
put(FIX .. "/lock/package-lock.json", lockfile)
put(FIX .. "/local/package-lock.json", lockfile)
put(wrapper, { "#!/bin/sh", ": > " .. vim.fn.shellescape(marker), "exec " .. vim.fn.shellescape(real) .. ' "$@"' })
vim.fn.setfperm(wrapper, "rwxr-xr-x")
local sources = {
  { "a.ts", "export const a: number = 1;" },
  { "b.tsx", "export const B = () => <div>hi</div>;" },
  { "c.jsx", "export const C = () => <p>hi</p>;" },
}
local projects = { { FIX, "git root" }, { FIX .. "/lock", "lockfile root" }, { FIX .. "/local", "local-server root" } }

local attached = 0
for _, p in ipairs(projects) do
  local dir, label = p[1], p[2]
  for _, s in ipairs(sources) do
    put(dir .. "/" .. s[1], { s[2] })
    vim.cmd.edit(dir .. "/" .. s[1])
    local buf = vim.api.nvim_get_current_buf()
    local _, why = wait_attach(buf, { "ts_ls" }, 30000)
    local c = ts(buf)
    if c then attached = attached + 1 end
    check(("%s %s (%s): ts_ls attaches at the project root"):format(label, s[1], vim.bo[buf].filetype),
      c ~= nil and vim.fs.normalize(c.root_dir or "") == vim.fs.normalize(dir),
      c and ("root " .. tostring(c.root_dir) .. ", want " .. dir) or table.concat(why, "; "))
  end
end
check("local-server root: ts_ls runs the project's node_modules/.bin/typescript-language-server",
  vim.uv.fs_stat(marker) ~= nil, "the wrapper never ran; the server came from elsewhere")

put(FIX .. "/deno/deno.json", { "{}" })
put(FIX .. "/deno/a.ts", { "export const d: number = 1;" })
vim.cmd.edit(FIX .. "/deno/a.ts")
local buf = vim.api.nvim_get_current_buf()
local function deno_client()
  if ts(buf) then return ts(buf) end
  for _, c in ipairs(vim.lsp.get_clients({ name = "ts_ls" })) do
    if vim.fs.normalize(c.root_dir or "") == vim.fs.normalize(FIX .. "/deno") then return c end
  end
end
-- a root_dir that takes the buffer starts a client at once; wait_attach gives a server the same 3s to appear
wait_until(function() return deno_client() ~= nil end, 3000)
local c = deno_client()
check("deno project: ts_ls stays off it", attached > 0 and vim.bo[buf].filetype == "typescript" and c == nil,
  attached == 0 and "ts_ls attached nowhere, so staying off deno proves nothing"
    or vim.bo[buf].filetype ~= "typescript" and ("filetype " .. vim.bo[buf].filetype)
    or c and ("ts_ls started at " .. tostring(c.root_dir)) or nil)
