-- Every LSP server, formatter and linter binary, keyed by the binary's name; replaces Mason's package tables.
-- Which filetypes use a tool stays in after/lsp/, conform's formatters_by_ft and nvim-lint's linters_by_ft.

---@class tools.Entry
---@field spec? string mise spec for `mise use -g`, version left out ("latest" is added); nil when only the system provides it
---@field project? string[] dirs under a project, searched upward from its root, that may hold a project copy
---@field runtime? "node"|"go"|"rust" what the binary needs on PATH when it runs
---@field component? string rustup component providing it; checked with `rustup which` and installed with `rustup component add`
---@field run? string binary to execute instead, from the same dir (cargo for cargo-clippy)
---@field accept? fun(version: string): boolean a candidate whose `--version` output fails this is skipped
---@field requires? string[] other catalog binaries it calls at run time
---@field servers? table<string, string[]> server name -> args after the binary
---@field formatters? string[] conform formatter names
---@field linters? string[] nvim-lint linter names

---@class tools.Runtime
---@field bin string
---@field spec string `mise use -g` spec when it is missing

local M = {}

---@type table<string, tools.Runtime>
M.runtimes = {
  node = { bin = "node", spec = "node@lts" },
  go = { bin = "go", spec = "go@latest" },
  rust = { bin = "rustup", spec = "rust@stable" },
}

local venv = { ".venv/bin" }
local node_modules = { "node_modules/.bin" }

-- TS 7 is the first tsc with --lsp; a project still on TS 5/6 falls through to the global one
local function ts7(version)
  local v = vim.version.parse(version)
  return v ~= nil and v.major >= 7
end

---@type table<string, tools.Entry>
M.tools = {
  -- Python
  pyrefly = { spec = "pypi:pyrefly", project = venv, servers = { pyrefly = { "lsp" } } },
  ruff = {
    spec = "ruff",
    project = venv,
    servers = { ruff = { "server" } },
    formatters = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
    linters = { "ruff" },
  },
  ["pyproject-fmt"] = { spec = "pypi:pyproject-fmt", project = venv, formatters = { "pyproject-fmt" } },

  -- TOML
  tombi = { spec = "tombi", servers = { tombi = { "lsp" } }, formatters = { "tombi" }, linters = { "tombi" } },

  -- Lua
  ["lua-language-server"] = { spec = "lua-language-server", servers = { lua_ls = {} } },
  stylua = { spec = "stylua", formatters = { "stylua" } },

  -- JS / TS / JSON
  tsc = { spec = "npm:typescript", project = node_modules, runtime = "node", accept = ts7, servers = { tsc = { "--lsp", "--stdio" } } },
  biome = { spec = "biome", project = node_modules, servers = { biome = { "lsp-proxy" } }, formatters = { "biome" }, linters = { "biomejs" } },

  -- YAML
  ["yaml-language-server"] = { spec = "npm:yaml-language-server", project = node_modules, runtime = "node", servers = { yamlls = { "--stdio" } } },
  prettierd = { spec = "npm:@fsouza/prettierd", project = node_modules, runtime = "node", formatters = { "prettierd" } },
  yamllint = { spec = "yamllint", project = venv, linters = { "yamllint" } },
  -- jdx's maintained fork of actionlint, which mise's registry deprecates for it
  jactionlint = { spec = "jactionlint", linters = { "jactionlint" } },
  zizmor = { spec = "zizmor", project = venv, linters = { "zizmor" } },

  -- Markdown
  marksman = { spec = "marksman", servers = { marksman = { "server" } } },
  ["markdownlint-cli2"] = { spec = "markdownlint-cli2", project = node_modules, runtime = "node", linters = { "markdownlint-cli2" } },

  -- HTML / CSS / SCSS, both from one npm package
  ["vscode-html-language-server"] = { spec = "npm:vscode-langservers-extracted", project = node_modules, runtime = "node", servers = { html = { "--stdio" } } },
  ["vscode-css-language-server"] = { spec = "npm:vscode-langservers-extracted", project = node_modules, runtime = "node", servers = { cssls = { "--stdio" } } },

  -- sh / bash; bashls runs shellcheck itself
  ["bash-language-server"] = { spec = "npm:bash-language-server", runtime = "node", requires = { "shellcheck" }, servers = { bashls = { "start" } } },
  shellcheck = { spec = "shellcheck" },
  shfmt = { spec = "shfmt", formatters = { "shfmt" } },

  -- Fish
  ["fish-lsp"] = { spec = "npm:fish-lsp", runtime = "node", servers = { fish_lsp = { "start" } } },
  fish_indent = { formatters = { "fish_indent" } }, -- ships with fish

  -- C / C++
  clangd = { spec = "github:clangd/clangd", servers = { clangd = {} } },
  ["clang-format"] = { spec = "clang-format", formatters = { "clang_format", "clang-format" } },

  -- Go
  gopls = { spec = "go:golang.org/x/tools/gopls", runtime = "go", servers = { gopls = {} } },
  goimports = { spec = "go:golang.org/x/tools/cmd/goimports", runtime = "go", formatters = { "goimports" } },
  gofumpt = { spec = "gofumpt", formatters = { "gofumpt" } },
  ["golangci-lint"] = { spec = "golangci-lint", runtime = "go", linters = { "golangcilint" } },

  -- Rust, rustup components of mise's rust
  ["rust-analyzer"] = { component = "rust-analyzer", runtime = "rust", servers = { rust_analyzer = {} } },
  rustfmt = { component = "rustfmt", runtime = "rust", formatters = { "rustfmt" } },
  ["cargo-clippy"] = { component = "clippy", runtime = "rust", run = "cargo", linters = { "clippy" } },

  -- Terraform
  ["terraform-ls"] = { spec = "terraform-ls", servers = { terraformls = { "serve" } } },
  terraform = { spec = "terraform", formatters = { "terraform_fmt" } },
  tflint = { spec = "tflint", servers = { tflint = { "--langserver" } }, linters = { "tflint" } },
  trivy = { spec = "trivy", linters = { "trivy" } },

  -- CMake
  neocmakelsp = { spec = "github:neocmakelsp/neocmakelsp", servers = { neocmake = { "stdio" } } },
  gersemi = { spec = "pypi:gersemi", project = venv, formatters = { "gersemi" } },

  -- Typst, tinymist formats with typstyle
  tinymist = { spec = "tinymist", servers = { tinymist = {} } },

  -- Dockerfile
  ["docker-language-server"] = { spec = "github:docker/docker-language-server", servers = { docker_language_server = { "start", "--stdio" } } },
  hadolint = { spec = "hadolint", linters = { "hadolint" } },

  -- Make
  checkmake = { spec = "checkmake", linters = { "checkmake" } },
}

---@type table<"server"|"formatter"|"linter", table<string, string>>
local by_role = { server = {}, formatter = {}, linter = {} }
for bin, entry in pairs(M.tools) do
  for server in pairs(entry.servers or {}) do
    by_role.server[server] = bin
  end
  for _, name in ipairs(entry.formatters or {}) do
    by_role.formatter[name] = bin
  end
  for _, name in ipairs(entry.linters or {}) do
    by_role.linter[name] = bin
  end
end

--- The catalog binary behind a server, conform formatter or nvim-lint linter name.
---@param role "server"|"formatter"|"linter"
---@param name string
---@return string? bin
function M.binary(role, name) return by_role[role][name] end

--- Every server name in the catalog, sorted; the list for vim.lsp.enable.
---@return string[]
function M.servers()
  local names = vim.tbl_keys(by_role.server)
  table.sort(names)
  return names
end

--- Args that follow the binary in a server's cmd.
---@param server string
---@return string[]?
function M.server_args(server)
  local bin = by_role.server[server]
  return bin and M.tools[bin].servers[server]
end

return M
