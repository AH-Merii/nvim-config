-- Every LSP server, formatter and linter binary, keyed by the binary's name; replaces Mason's package tables.
-- Which filetypes use a tool, and a server's settings, are in the language files (lua/lang/).

---@class tools.Entry
---@field spec? string mise spec for a global install (`mise use --path <tools file>`), version left out ("latest" is added); nil when only the system provides it
---@field project? string[] dirs under a project, searched upward from its root, that may hold a project copy
---@field runtime? "node"|"go"|"rust" what the binary needs on PATH when it runs
---@field component? string rustup component providing it; checked with `rustup which` and installed with `rustup component add`
---@field run? string binary to execute instead, from the same dir (cargo for cargo-clippy)
---@field min? string lowest version accepted, e.g. "7"; a candidate whose `--version` reports an older one is skipped
---@field requires? string[] other catalog binaries it calls at run time
---@field servers? table<string, string[]> server name -> args after the binary
---@field formatters? string[] conform formatter names
---@field linters? string[] nvim-lint linter names

---@class tools.Runtime
---@field bin string
---@field spec string mise spec for its global install when it is missing

local M = {}

---@type table<string, tools.Runtime>
M.runtimes = {
  node = { bin = "node", spec = "node@lts" },
  go = { bin = "go", spec = "go@latest" },
  rust = { bin = "rustup", spec = "rust@stable" },
}

local venv = { ".venv/bin" }
local node_modules = { "node_modules/.bin" }

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
  -- TS 7 is the first tsc with --lsp; a project still on TS 5/6 falls through to the global one
  tsc = { spec = "npm:typescript", project = node_modules, runtime = "node", min = "7", servers = { tsc = { "--lsp", "--stdio" } } },
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
  -- fish-lsp runs `fish` from PATH (or $fish_lsp_fish_path). conform formats with `fish -c 'builtin fish_indent'`:
  -- mise's fish is one binary without a fish_indent command, and the builtin came in fish 4.1.0
  ["fish-lsp"] = { spec = "npm:fish-lsp", runtime = "node", requires = { "fish" }, servers = { fish_lsp = { "start" } } },
  fish = { spec = "github:fish-shell/fish-shell", min = "4.1", formatters = { "fish_indent" } },

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

local role_words = { server = "lsp", formatter = "formatter", linter = "linter" }

--- The catalog binaries a filetype's tools run: its servers', formatters' and linters' binaries and what each calls
--- (requires), and per binary its roles there in plain words, e.g. { "lsp", "formatter", "linter" } or
--- { "used by bashls" }. Names outside the catalog (conform's trim_whitespace, ...) are not binaries mise provides.
---@param found lang.Answer
---@return string[] names, table<string, string[]> roles
function M.needed(found)
  local names, roles = {}, {}
  ---@param list string[]
  ---@param name string
  local function add(list, name)
    if not vim.list_contains(list, name) then
      table.insert(list, name)
    end
  end
  for _, role in ipairs({ { "server", found.servers }, { "formatter", found.formatters }, { "linter", found.linters } }) do
    for _, name in ipairs(role[2]) do
      local bin = by_role[role[1]][name]
      if bin then
        add(names, bin)
        roles[bin] = roles[bin] or {}
        add(roles[bin], role_words[role[1]])
        for _, required in ipairs(M.tools[bin].requires or {}) do
          add(names, required)
          roles[required] = roles[required] or {}
          add(roles[required], "used by " .. name)
        end
      end
    end
  end
  return names, roles
end

--- Args that follow the binary in a server's cmd.
---@param server string
---@return string[]?
function M.server_args(server)
  local bin = by_role.server[server]
  return bin and M.tools[bin].servers[server]
end

return M
