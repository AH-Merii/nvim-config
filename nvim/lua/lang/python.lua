-- Python: pyrefly checks types, ruff lints and formats. pyproject.toml is toml.pyproject (lang/toml.lua).

-- The Python that runs a file: the nearest .venv above it, the active virtualenv, then python3
---@param path string
local function python(path)
  local venv = vim.fs.find(".venv", { upward = true, path = vim.fs.dirname(path), type = "directory" })[1]
  for _, bin in ipairs({ venv and vim.fs.joinpath(venv, "bin", "python"), vim.env.VIRTUAL_ENV and vim.fs.joinpath(vim.env.VIRTUAL_ENV, "bin", "python") }) do
    if vim.fn.executable(bin) == 1 then
      return bin
    end
  end
  return "python3"
end

-- Runs argv in a terminal split below
---@param argv string[]
---@param cwd? string
local function run(argv, cwd)
  vim.cmd("botright new")
  vim.fn.jobstart(argv, { term = true, cwd = cwd })
end

local NXO = { "n", "x", "o" }

---@type lang.Spec
return {
  filetypes = { "python" },
  parsers = { "python" },
  servers = {
    -- https://pyrefly.org/, a Python type checker written in Rust
    pyrefly = {
      settings = {
        -- the Run and Test code lenses, off by default
        python = { pyrefly = { runnableCodeLens = true } },
      },
      -- Those lenses name client commands that pyrefly's VS Code extension implements; these run them the same way
      -- (lsp/src/code-lens.ts): the file, or pytest or unittest on the test, with the project's Python
      commands = {
        ["pyrefly.runMain"] = function(command, ctx)
          local args = command.arguments and command.arguments[1] or {}
          local path = vim.uri_to_fname(args.uri or vim.uri_from_bufnr(ctx.bufnr))
          run({ python(path), path }, args.cwd)
        end,
        ["pyrefly.runTest"] = function(command, ctx)
          local args = command.arguments and command.arguments[1] or {}
          local path = vim.uri_to_fname(args.uri or vim.uri_from_bufnr(ctx.bufnr))
          local names = vim.tbl_filter(function(name) return name ~= nil end, { args.className, args.testName })
          if args.isUnittest then
            -- unittest takes a dotted name: the module's path under the cwd, then the class and test
            local rel = vim.fs.relpath(args.cwd or vim.fn.getcwd(), path)
            local target = rel and rel:match("^(.*)%.py$")
            target = target and table.concat(vim.list_extend({ (target:gsub("/", ".")) }, names), ".") or path
            run({ python(path), "-m", "unittest", target }, args.cwd)
          else
            local py = python(path)
            vim.system({ py, "-c", "import pytest" }, { cwd = args.cwd }, function(out)
              vim.schedule(function()
                if out.code == 0 then
                  run({ py, "-m", "pytest", table.concat(vim.list_extend({ path }, names), "::") }, args.cwd)
                else
                  vim.notify(
                    ("%s can't import pytest, which runs this test; add it to the project, e.g. `uv add --dev pytest`"):format(py),
                    vim.log.levels.WARN,
                    { title = "pyrefly" }
                  )
                end
              end)
            end)
          end
        end,
      },
      handlers = {
        -- pyrefly answers a code lens request that comes before it has applied these settings with none, and asks for no
        -- refresh once it has, so the lenses of a file opened as it starts would stay missing until an edit
        ["workspace/configuration"] = function(err, params, ctx)
          local result = vim.lsp.handlers["workspace/configuration"](err, params, ctx)
          vim.schedule(function() vim.lsp.handlers["workspace/codeLens/refresh"](nil, nil, ctx) end)
          return result
        end,
      },
      root_markers = { "pyrefly.toml", "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", "Pipfile", ".git", "pixi.toml" },
      -- type errors on where the root has a pyproject.toml or pyrefly.toml; pyrefly's own default wants [tool.pyrefly]
      on_init = function(client)
        local root = client.root_dir
        local on = root ~= nil and vim.iter({ "pyproject.toml", "pyrefly.toml" }):any(function(f) return vim.uv.fs_stat(vim.fs.joinpath(root, f)) ~= nil end)
        require("lsp.pyrefly").type_errors(client, on)
      end,
      -- on_exit runs in a fast event, where vim.notify's first call (snacks loading its notifier) fails with E5560
      on_exit = function(code, _, _)
        vim.schedule(function() vim.notify("Closing Pyrefly LSP exited with code: " .. code, vim.log.levels.INFO) end)
      end,
    },
    -- pyrefly answers utf-16 whatever it is offered, so ruff must match it on python buffers
    ruff = { capabilities = { general = { positionEncodings = { "utf-16" } } } },
  },
  formatters = { "ruff_fix", "ruff_format", "ruff_organize_imports" },
  linters = { ruff = { covered_by = "ruff" } },
  -- Labels for the runtime ftplugin's motions, which it maps without a desc, so the popup would show their rhs
  keys = {
    { "]]", label = "Next top-level def/class", mode = NXO },
    { "[[", label = "Previous top-level def/class", mode = NXO },
    { "][", label = "Next top-level block end", mode = NXO },
    { "[]", label = "Previous top-level block end", mode = NXO },
    { "]m", label = "Next def/class line", mode = NXO },
    { "[m", label = "Previous def/class line", mode = NXO },
    { "]M", label = "Next def/class end", mode = NXO },
    { "[M", label = "Previous def/class end", mode = NXO },
    filetypes = { "python" },
  },
}
