#!/usr/bin/env bash
# usage: ref-e1.sh <clone dir>: the reference solution for e1 (Zig: zls + zig fmt), applied to a seeded clone
set -euo pipefail
cd "$1"
perl -0pi -e 's/(  -- Make\n)/  -- Zig; zls must match the zig version it serves\n  zls = { spec = "zls", servers = { zls = {} } },\n  zig = { spec = "zig", formatters = { "zigfmt" } },\n\n$1/' nvim/lua/tools/catalog.lua
perl -0pi -e 's/(  "docker_language_server",\n)/$1  "zls",\n/' nvim/lua/core/lsp_servers.lua
perl -0pi -e 's/(      cmake = \{ "gersemi" \},\n)/$1\n      zig = { "zigfmt" },\n/' nvim/lua/plugins/conform.lua
grep -q '"zig"' nvim/lua/plugins/nvim-treesitter.lua || perl -0pi -e 's/(local ensure_installed = \{\n(?:  "[^"]+",\n)*)/$1  "zig",\n/' nvim/lua/plugins/nvim-treesitter.lua
printf 'const std = @import("std");\n\npub fn main() void {\n    std.debug.print("hi\\n", .{});\n}\n' > tests/regress/fixtures/default/main.zig
sed -i 's/^\(-- @needs .*\)$/\1 zls/' tests/regress/checks/lsp_attach.lua
sed -i 's|"\.github/workflows/ci\.yml" }|".github/workflows/ci.yml", "main.zig" }|' tests/regress/checks/lsp_attach.lua
cat > tests/regress/checks/format_zigfmt.lua <<'LUA'
-- @desc     formatting a zig buffer through conform runs zig fmt and leaves it formatted
-- @areas    format
-- @budget   20
-- @needs    zig
vim.fn.writefile({ "pub fn main() void {", "const   x:u8=1;", "_ = x;", "}" }, "fmt.zig")
vim.cmd.edit("fmt.zig")
local buf = vim.api.nvim_get_current_buf()
local conform = require("conform")
local names = vim.tbl_map(function(f) return f.name end, conform.list_formatters_to_run(buf))
check("zigfmt is planned for zig", vim.list_contains(names, "zigfmt"), table.concat(names, ","))
local ok, err = pcall(conform.format, { bufnr = buf, async = false, timeout_ms = 15000, lsp_format = "never" })
check("conform.format runs", ok, err)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
check("the buffer is formatted", vim.deep_equal(lines, { "pub fn main() void {", "    const x: u8 = 1;", "    _ = x;", "}" }), table.concat(lines, " | "))
LUA
D=docs/mise-tooling-decisions.md
perl -0pi -e 's/(\| Make \| none \| none \| checkmake \|\n)/$1| **Zig** | **zls** | **zig fmt** (conform `zigfmt`) | none |\n/' $D
perl -0pi -e 's/(\| gofumpt \| `gofumpt` \(registry, static binary\) \| yes \|\n)/$1| zls | `zls` (registry: `aqua:zigtools\/zls`) | yes |\n| zig | `zig` (registry: `core:zig`; zig fmt is conform `zigfmt`) | yes |\n/' $D
perl -0pi -e 's/(Decided since:\n\n)/$1- **Zig: zls and zig fmt** (2026-10-12). `mise registry zls` printed `aqua:zigtools\/zls` and `mise registry zig`\n  printed `core:zig`; conform ships `zigfmt` (`zig fmt --stdin`). zls must match the zig version (open point).\n/' $D
