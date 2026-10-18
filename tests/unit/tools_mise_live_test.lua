-- Opt-in live check of a project-only install against the real mise (D100), off by default: it needs mise on PATH
-- and may download a tool. Run it with
--   TOOLS_LIVE_MISE=1 tests/unit/run.sh tools_mise_live
-- and, to reuse installs instead of downloading, TOOLS_LIVE_MISE_DATA=<a mise data dir> (jq is installed there).
-- The other mise dirs are throwaway ones, so the user's mise config and trust are untouched.
-- The scenario: a project whose untrusted mise.toml holds an [env] exec template (as a `git pull` could bring) gets
-- jq for the project only. The exec must not run, mise's trust must not change, and the project must then use jq.
if vim.env.TOOLS_LIVE_MISE ~= "1" then
  print("SKIP: set TOOLS_LIVE_MISE=1 to run the live mise check")
  return
end
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")

local tmp = h.tmpdir()
for name in pairs(vim.fn.environ()) do
  if name:match("^_*MISE_") then
    vim.env[name] = nil
  end
end
vim.env.MISE_CONFIG_DIR, vim.env.MISE_STATE_DIR, vim.env.MISE_CACHE_DIR = tmp .. "/config", tmp .. "/state", tmp .. "/cache"
vim.env.MISE_DATA_DIR = vim.env.TOOLS_LIVE_MISE_DATA or (tmp .. "/data")
vim.env.MISE_CEILING_PATHS = tmp

local mise = require("tools.mise")
h.ok(mise.bin(), "mise is not on PATH")

---@param args string[]
---@param cwd string
local function run(args, cwd) return vim.system({ mise.bin(), unpack(args) }, { cwd = cwd, text = true, stdin = false }):wait() end

h.case("a project-only install in a project with an untrusted exec config runs no exec, adds no trust, and works", function()
  local root = tmp .. "/project"
  local pwned = root .. "/pwned"
  h.write(root .. "/mise.toml", { "[tools]", "[env]", ("PWN = \"{{exec(command='touch %s')}}\""):format(pwned) })
  local trust = run({ "trust", "--show" }, root).stdout
  local ok, err = h.await(function(done) mise.use_local(root, { "jq@latest" }, done) end, 300000)
  h.ok(ok, "the install failed: " .. tostring(err))
  h.eq(vim.uv.fs_stat(pwned) ~= nil, false, "the exec ran")
  h.eq(run({ "trust", "--show" }, root).stdout, trust, "mise trust --show")
  h.eq(vim.fn.readfile(root .. "/mise.local.toml"), { "[tools]", 'jq = "latest"' }, "mise.local.toml")
  -- The [env] keeps mise out of the dir until trusted; without it, the untrusted, tool-only config is used
  h.write(root .. "/mise.toml", { "[tools]" })
  local which = run({ "which", "jq" }, root)
  h.ok(which.code == 0 and vim.startswith(which.stdout, vim.env.MISE_DATA_DIR .. "/installs/jq/"), vim.inspect(which))
  h.eq(vim.uv.fs_stat(pwned) ~= nil, false, "the exec ran later")
end)

h.finish()
