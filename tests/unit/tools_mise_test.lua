-- The mise backend's global install (require("tools.mise").use_global) against a fake `mise` on PATH that writes each
-- spec to the file the real one would: `--path <file>`, or the global config for `-g`. The rule: the config's tools
-- go to a global file of its own, never into the user's global config.toml (a dotfiles file for many users).
-- Decision: D91 in docs/mise-tooling-decisions.md.
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")

local tmp = h.tmpdir()
-- A wrong path built from HOME must land here, not in the user's own ~/.config/mise
vim.env.HOME = tmp .. "/home"

-- The subset of `mise use` the backend may send. Like mise, `-g` writes MISE_GLOBAL_CONFIG_FILE when set, else
-- config.toml in the config dir (MISE_CONFIG_DIR, else $XDG_CONFIG_HOME/mise, else ~/.config/mise); no target
-- means a project config in the cwd, which the backend must never write. It refuses any file outside the test dir.
-- `ls ... -C /` (global configs only) prints $FAKE_MISE_LS; without `-C /` it prints a project's tools.
h.write(tmp .. "/bin/mise", {
  "#!/bin/sh",
  'if [ "$1" = ls ]; then case " $* " in *" -C / "*) cat "$FAKE_MISE_LS" ;; *) echo \'{"ruff":[{"version":"0.1.0","installed":false,"source":{"path":"/p/mise.toml"}}]}\' ;; esac; exit 0; fi',
  '[ "$1" = use ] || { echo "fake mise: only use and ls" >&2; exit 2; }',
  "shift",
  "target= specs=",
  "while [ $# -gt 0 ]; do",
  '  case "$1" in',
  '    -g|--global) target=${MISE_GLOBAL_CONFIG_FILE:-${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}/config.toml} ;;',
  '    -p|--path) shift; target=$1 ;;',
  '    --path=*) target=${1#--path=} ;;',
  "    -*) ;;",
  '    *) specs="$specs $1" ;;',
  "  esac",
  "  shift",
  "done",
  '[ -n "$target" ] || target=$PWD/mise.toml',
  ('case "$target" in %s/*) ;; *) echo "fake mise: $target is outside the test dir" >&2; exit 3 ;; esac'):format(tmp),
  'mkdir -p "$(dirname "$target")" || exit 1',
  'for s in $specs; do echo "$s" >> "$target"; done',
}, true)
vim.env.PATH = tmp .. "/bin:" .. vim.env.PATH

local mise = require("tools.mise")

---@param path string
---@return string[]? lines, nil when the file does not exist
local function read(path) return vim.uv.fs_stat(path) and vim.fn.readfile(path) or nil end

local n = 0
--- A fresh dir for one case, with the mise env vars cleared.
---@return string dir
local function fresh()
  n = n + 1
  local dir = ("%s/%d"):format(tmp, n)
  vim.env.MISE_CONFIG_DIR, vim.env.MISE_GLOBAL_CONFIG_FILE, vim.env.XDG_CONFIG_HOME = nil, nil, nil
  return dir
end

---@param specs string[]
local function use_global(specs)
  local ok, err = h.await(function(done) mise.use_global(specs, done) end)
  h.ok(ok, "the install failed: " .. tostring(err))
end

local user = { "# my dotfiles", "[tools]", 'node = "lts"' }

-- D99: what the resolver reads to tell a global pin that isn't installed
h.case("global pins: each tool at the version the user's global configs give it, not from the config's own file", function()
  local dir = fresh()
  vim.env.MISE_CONFIG_DIR = dir .. "/mise"
  local config, own = dir .. "/mise/config.toml", dir .. "/mise/conf.d/nvim-config.toml"
  local function v(version, installed, path) return { version = version, installed = installed, source = { path = path } } end
  h.write(dir .. "/ls.json", {
    vim.json.encode({
      shfmt = { v("3.10.0", false, config) },
      -- mise lists the version on PATH first
      node = { v("22.1.0", true, config), v("20.0.0", false, config) },
      stylua = { v("2.6.0", false, own) },
    }),
  })
  vim.env.FAKE_MISE_LS = dir .. "/ls.json"
  h.eq(h.await(function(done) mise.global_pins(done) end), {
    shfmt = { version = "3.10.0", installed = false, source = config },
    node = { version = "22.1.0", installed = true, source = config },
  })
end)

h.case("a global install writes the config's own file in MISE_CONFIG_DIR's conf.d, not its config.toml", function()
  local dir = fresh()
  vim.env.MISE_CONFIG_DIR = dir .. "/mise"
  h.write(dir .. "/mise/config.toml", user)
  use_global({ "ruff@latest", "node@lts" })
  h.eq(read(dir .. "/mise/conf.d/nvim-config.toml"), { "ruff@latest", "node@lts" }, "the config's own file")
  h.eq(read(dir .. "/mise/config.toml"), user, "the user's global config.toml")
end)

h.case("without MISE_CONFIG_DIR, the file is in $XDG_CONFIG_HOME/mise/conf.d", function()
  local dir = fresh()
  vim.env.XDG_CONFIG_HOME = dir .. "/xdg"
  h.write(dir .. "/xdg/mise/config.toml", user)
  use_global({ "stylua@latest" })
  h.eq(read(dir .. "/xdg/mise/conf.d/nvim-config.toml"), { "stylua@latest" }, "the config's own file")
  h.eq(read(dir .. "/xdg/mise/config.toml"), user, "the user's global config.toml")
end)

h.case("without MISE_CONFIG_DIR or XDG_CONFIG_HOME, the file is in ~/.config/mise/conf.d", function()
  fresh()
  local home = vim.env.HOME
  h.write(home .. "/.config/mise/config.toml", user)
  use_global({ "taplo@latest" })
  h.eq(read(home .. "/.config/mise/conf.d/nvim-config.toml"), { "taplo@latest" }, "the config's own file")
  h.eq(read(home .. "/.config/mise/config.toml"), user, "the user's global config.toml")
end)

h.case("with MISE_GLOBAL_CONFIG_FILE set, mise reads no conf.d, so the install goes to that file", function()
  local dir = fresh()
  vim.env.MISE_CONFIG_DIR = dir .. "/mise"
  vim.env.MISE_GLOBAL_CONFIG_FILE = dir .. "/single.toml"
  use_global({ "shfmt@latest" })
  h.eq(read(dir .. "/single.toml"), { "shfmt@latest" }, "MISE_GLOBAL_CONFIG_FILE")
  h.eq(read(dir .. "/mise/conf.d/nvim-config.toml"), nil, "a conf.d file mise would not read")
end)

h.finish()
