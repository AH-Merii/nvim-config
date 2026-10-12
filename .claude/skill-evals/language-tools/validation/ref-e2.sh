#!/usr/bin/env bash
# usage: ref-e2.sh <clone dir>: the reference solution for e2 (selene for Lua), applied to a seeded clone
set -euo pipefail
cd "$1"
perl -0pi -e 's/(  stylua = \{ spec = "stylua", formatters = \{ "stylua" \} \},\n)/$1  selene = { spec = "aqua:Kampfkarren\/selene", linters = { "selene" } },\n/' nvim/lua/tools/catalog.lua
perl -0pi -e 's/(      python = \{ "ruff" \},\n)/      lua = { "selene" },\n$1/' nvim/lua/plugins/nvim-lint.lua
cat > tests/regress/checks/lint_selene.lua <<'LUA'
-- @desc     selene findings appear on a lua buffer, from the binary the resolver finds
-- @areas    lint tools
-- @budget   20
-- @needs    selene
local ns = require("lint").get_namespace("selene")
vim.fn.writefile({ "local unused = 1", "return 2" }, "sel.lua")
vim.cmd.edit("sel.lua")
local buf = vim.api.nvim_get_current_buf()
check("the sample is lua", vim.bo[buf].filetype == "lua", vim.bo[buf].filetype)
wait_diagnostics(buf, function() return #vim.diagnostic.get(buf, { namespace = ns }) > 0 end, 10000)
local diags = vim.diagnostic.get(buf, { namespace = ns })
check("selene reports the unused_variable finding", vim.iter(diags):any(function(d) return d.code == "unused_variable" end),
  vim.inspect(vim.tbl_map(function(d) return d.code end, diags)))
LUA
D=docs/mise-tooling-decisions.md
sed -i 's/^| Lua | lua_ls | stylua | ~~luacheck~~ |$/| Lua | lua_ls | stylua | **selene**; ~~luacheck~~ |/' $D
perl -0pi -e 's/(\| gofumpt \| `gofumpt` \(registry, static binary\) \| yes \|\n)/$1| selene | `aqua:Kampfkarren\/selene` (not in the registry; static binary) | yes |\n/' $D
perl -0pi -e 's/(Decided since:\n\n)/$1- **selene for Lua** (2026-10-12). `mise registry selene` printed `tool not found in registry`; `mise latest\n  aqua:Kampfkarren\/selene` printed `0.32.0`. nvim-lint ships `selene`. Without a selene.toml it flags `vim` (open point).\n/' $D
