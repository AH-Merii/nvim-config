return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local lint = require("lint")
    local tools = require("tools")
    local lint_tools = require("tools.lint")

    -- A dotted filetype with no key of its own gets the linters of all its parts (yaml.github-actions -> yaml + github-actions)
    lint.linters_by_ft = {
      -- Go
      go = { "golangcilint" },

      -- JavaScript/TypeScript/JSON
      javascript = { "biomejs" },
      typescript = { "biomejs" },
      javascriptreact = { "biomejs" },
      typescriptreact = { "biomejs" },
      json = { "biomejs" },
      jsonc = { "biomejs" },

      python = { "ruff" },
      rust = { "clippy" },
      toml = { "tombi" },

      -- Other
      markdown = { "markdownlint-cli2" },
      yaml = { "yamllint" },
      -- Workflow files are yaml.github-actions (lua/tools/filetypes.lua)
      ["github-actions"] = { "jactionlint", "zizmor" },
      make = { "checkmake" },
      terraform = { "tflint", "trivy" },
      dockerfile = { "hadolint" },
    }

    -- jactionlint: jdx's maintained fork of actionlint, with GNU-style options and actionlint's JSON plus a rule id and
    -- a severity. Its default profile adds security rules that zizmor already reports (template-injection,
    -- unpinned-uses, ...); the correctness profile is what actionlint checks
    local severities = { error = vim.diagnostic.severity.ERROR, warn = vim.diagnostic.severity.WARN, info = vim.diagnostic.severity.INFO }
    lint.linters.jactionlint = {
      cmd = "jactionlint",
      stdin = true,
      args = { "--format", "{{json .}}", "--profile", "correctness", "--stdin-filename", function() return vim.api.nvim_buf_get_name(0) end, "-" },
      ignore_exitcode = true, -- exits 1 when it has findings
      parser = function(output)
        local diagnostics = {}
        for _, item in ipairs(output ~= "" and vim.json.decode(output) or {}) do
          table.insert(diagnostics, {
            lnum = item.line - 1,
            end_lnum = (item.end_line or item.line) - 1,
            col = item.column - 1,
            end_col = item.end_column,
            severity = severities[item.severity] or vim.diagnostic.severity.WARN,
            source = "jactionlint",
            code = item.id,
            message = item.message,
          })
        end
        return diagnostics
      end,
    }

    -- Auto-lint on save and text changes
    local autocmd = vim.api.nvim_create_autocmd
    local augroup = vim.api.nvim_create_augroup
    local user_group = augroup("UserAutocmdsNvimLint", { clear = true })

    -- Linters whose parser matches file names relative to Neovim's cwd, so they keep running there
    local keep_cwd = { tflint = true }

    local covering_server, covered, binary = lint_tools.covering_server, lint_tools.covered, lint_tools.binary

    -- golangcilint builds its version-specific args once, when its module loads, from the golangci-lint and go on
    -- Neovim's PATH (lint/linters/golangcilint.lua); build them again with the resolved binary and its runtime first
    local args_by_path = {} ---@type table<string, table|false>
    ---@param result tools.Result
    local function golangcilint_args(result)
      if args_by_path[result.path] == nil then
        local file = vim.api.nvim_get_runtime_file("lua/lint/linters/golangcilint.lua", false)[1]
        local path = vim.env.PATH
        vim.env.PATH = vim.fs.dirname(result.path) .. ":" .. (result.env and result.env.PATH or path)
        local ok, linter = pcall(dofile, file)
        vim.env.PATH = path
        args_by_path[result.path] = ok and type(linter) == "table" and linter.args or false
      end
      return args_by_path[result.path] or nil
    end

    --- The global, tab and window dirs (false where the tab or window has none of its own).
    local function dirs()
      return {
        vim.fn.getcwd(-1, -1),
        vim.fn.haslocaldir(-1, 0) == 1 and vim.fn.getcwd(-1, 0),
        vim.fn.haslocaldir(0, 0) == 1 and vim.fn.getcwd(0, 0),
      }
    end

    --- Runs fn and puts back the dirs it moved. nvim-lint evaluates cmd and args after a global :cd to the
    --- linter's cwd and back to the window's (lint.lua, with_cwd), which drops the user's :tcd and :lcd.
    ---@param fn fun()
    local function keeping_dirs(fn)
      local before = dirs()
      local ok, err = pcall(fn)
      if not vim.deep_equal(dirs(), before) then
        local mods = { noautocmd = true, silent = true }
        vim.cmd.cd({ before[1], mods = mods })
        if before[2] then
          vim.cmd.tcd({ before[2], mods = mods })
        end
        if before[3] then
          vim.cmd.lcd({ before[3], mods = mods })
        end
      end
      if not ok then
        error(err, 0)
      end
    end

    --- Lints the current buffer with the binaries the resolver finds for its project. A linter whose binary is
    --- missing is skipped; one still resolving is skipped too, and ToolsChanged lints again once it is found.
    ---@param names? string|string[]
    local function lint_buffer(names)
      local root = tools.root(0)
      local opts = {
        filter = function(linter) return lint_tools.runs(linter.name, vim.api.nvim_get_current_buf(), root, linter) end,
        wrap_linter = function(linter)
          local bin = binary(linter.name, linter)
          local result = bin and tools.get(bin, root)
          if result then
            linter.cmd = result.path
            if not keep_cwd[linter.name] then
              linter.cwd = root
            end
            -- nvim-lint replaces the whole environment when env is set
            linter.env = result.env and vim.tbl_extend("force", vim.fn.environ(), result.env, linter.env or {}) or linter.env
            if linter.name == "golangcilint" and result.path then
              linter.args = golangcilint_args(result) or linter.args
            end
          end
          local parse = linter.parser
          if covering_server[linter.name] and type(parse) == "function" then
            -- A run that ends after its server attached reports nothing
            linter.parser = function(output, bufnr, ...) return covered(linter.name, bufnr) and {} or parse(output, bufnr, ...) end
          end
          return linter
        end,
      }
      keeping_dirs(function() lint.try_lint(names, opts) end)
    end

    -- Drop what a linter reported before its server attached
    autocmd("LspAttach", {
      group = user_group,
      callback = function(ev)
        local client = vim.lsp.get_client_by_id(ev.data.client_id)
        for linter, server in pairs(covering_server) do
          if client and client.name == server then
            vim.diagnostic.reset(lint.get_namespace(linter), ev.buf)
          end
        end
      end,
    })

    autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      group = user_group,
      callback = function()
        if #lint._resolve_linter_by_ft(vim.bo.filetype) > 0 then
          lint_buffer()
        end
      end,
    })

    -- Lint the root's loaded buffers again when one of their linters was found, installed or went missing
    autocmd("User", {
      group = user_group,
      pattern = tools.event,
      callback = function(ev)
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          local names = vim.api.nvim_buf_is_loaded(buf) and lint._resolve_linter_by_ft(vim.bo[buf].filetype) or {}
          local changed = vim.tbl_filter(function(name) return vim.list_contains(ev.data.tools, binary(name)) end, names)
          if #changed > 0 and tools.root(buf) == ev.data.root then
            for _, name in ipairs(changed) do
              vim.diagnostic.reset(lint.get_namespace(name), buf)
            end
            vim.api.nvim_buf_call(buf, function() lint_buffer(changed) end)
          end
        end
      end,
    })

    ---@param buf integer
    local function map_lint_keys(buf)
      pcall(vim.keymap.del, "n", "<leader>ll", { buf = buf })
      pcall(vim.keymap.del, "n", "<leader>li", { buf = buf })
      -- The lookup try_lint does when lint_buffer() names no linters
      local names = lint._resolve_linter_by_ft(vim.bo[buf].filetype)
      if #names == 0 then
        return
      end

      -- Manual linting command, while lint_buffer() would run at least one linter
      if vim.iter(names):any(function(name) return not covered(name, buf) end) then
        vim.keymap.set("n", "<leader>ll", function()
          lint_buffer()
          vim.notify("Linting...", vim.log.levels.INFO, { title = "nvim-lint" })
        end, { buf = buf, desc = "Trigger linting for current file" })
      end

      -- Show linter status
      vim.keymap.set("n", "<leader>li", function()
        local linters = vim.tbl_map(
          function(name) return covered(name, buf) and ("%s (reported by the %s server)"):format(name, covering_server[name]) or name end,
          lint._resolve_linter_by_ft(vim.bo[buf].filetype)
        )
        if #linters == 0 then
          print("No linters configured for filetype: " .. vim.bo.filetype)
        else
          print("Linters for " .. vim.bo.filetype .. ": " .. table.concat(linters, ", "))
        end
      end, { buf = buf, desc = "Show available linters for current filetype" })
    end

    autocmd({ "FileType", "LspAttach" }, { group = user_group, callback = function(ev) map_lint_keys(ev.buf) end })
    autocmd("LspDetach", {
      group = user_group,
      callback = function(ev)
        -- The detaching client still counts as attached while LspDetach runs
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(ev.buf) then
            map_lint_keys(ev.buf)
          end
        end)
      end,
    })
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        map_lint_keys(buf)
      end
    end
  end,
}
