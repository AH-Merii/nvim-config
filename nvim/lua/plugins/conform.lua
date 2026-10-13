return {
  "stevearc/conform.nvim",
  event = { "BufWritePre" },
  cmd = { "ConformInfo", "FormatWithConform" },

  opts = {
    formatters = {
      shfmt = {
        -- Use 2-space indentation and preserve manual alignment padding.
        prepend_args = { "-i", "2", "-kp" },
      },
      -- The resolved fish runs its builtin fish_indent (fish >= 4.1, tools/catalog.lua): mise's fish is a single binary
      fish_indent = { args = { "-c", "builtin fish_indent" } },
    },

    -- A dotted filetype with no key of its own uses its most specific part that has one (yaml.docker-compose -> yaml)
    formatters_by_ft = {
      -- Web technologies (Biome for JS/TS/JSON, Prettier for markup/config)
      javascript = { "biome" },
      typescript = { "biome" },
      javascriptreact = { "biome" },
      typescriptreact = { "biome" },
      json = { "biome" },
      jsonc = { "biome" },
      yaml = { "prettierd" },
      markdown = { "prettierd" },
      html = { "prettierd" },
      css = { "prettierd" },
      scss = { "prettierd" },

      python = {
        "ruff_fix",
        "ruff_format",
        "ruff_organize_imports",
      },

      -- Shell
      sh = { "shfmt" },
      bash = { "shfmt" },
      fish = { "fish_indent" },

      -- C/C++
      c = { "clang-format" },
      cpp = { "clang-format" },

      go = { "goimports", "gofumpt" },
      lua = { "stylua" },
      rust = { "rustfmt" },

      terraform = { "terraform_fmt" },
      tf = { "terraform_fmt" },
      ["terraform-vars"] = { "terraform_fmt" },

      cmake = { "gersemi" },

      -- pyproject.toml is toml.pyproject (lua/tools/filetypes.lua)
      toml = { "tombi" },
      ["toml.pyproject"] = { "pyproject-fmt" },
    },

    -- Use LSP if no external formatter is configured
    default_format_opts = {
      lsp_format = "fallback",
    },
  },

  config = function(_, opts)
    local c = require("conform")
    local tools = require("tools")

    -- Run each formatter's binary as the resolver finds it for the buffer's project, keeping the built-in args.
    -- A missing tool gets a command that is not executable, so conform marks it unavailable and LSP formatting takes over.
    for _, names in pairs(opts.formatters_by_ft) do
      for _, name in ipairs(names) do
        local bin = tools.catalog.binary("formatter", name)
        if bin then
          opts.formatters[name] = vim.tbl_extend("force", opts.formatters[name] or {}, {
            command = function(_, ctx)
              local result = tools.wait(bin, tools.root(ctx.buf))
              return result and result.path or ("%s (%s)"):format(bin, result and result.reason or "still resolving")
            end,
            env = function(_, ctx)
              local result = tools.get(bin, tools.root(ctx.buf))
              return result and result.env
            end,
          })
        end
      end
    end
    c.setup(opts)

    -- use conform for formatexpr
    vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"

    --- Format helper that reports which formatter(s) ran, while still allowing LSP fallback.
    ---@param args { async?: boolean, bufnr?: integer }|nil
    function c.format_buffer(args)
      args = args or {}

      local async = args.async
      if async == nil then
        async = true
      end

      local bufnr = args.bufnr or vim.api.nvim_get_current_buf()

      -- External formatters that conform plans to run (LSP fallback not included here)
      local formatters = c.list_formatters_to_run(bufnr)
      local names = vim.tbl_map(function(f) return f.name end, formatters)

      -- Capture filename for this buffer (independent of current window/buffer)
      local filepath = vim.api.nvim_buf_get_name(bufnr)
      local filename = (filepath ~= "" and vim.fn.fnamemodify(filepath, ":t")) or "<buffer>"
      local ft = vim.bo[bufnr].filetype

      -- Check if there's any LSP attached that can format this buffer (modern API)
      local has_lsp = false
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
        if client.supports_method and (client:supports_method("textDocument/formatting") or client:supports_method("textDocument/rangeFormatting")) then
          has_lsp = true
          break
        end
      end

      -- Choose label: explicit external formatters, LSP, or none
      local formatter_label
      if #names > 0 then
        formatter_label = table.concat(names, ", ")
      elseif has_lsp then
        formatter_label = "LSP"
      else
        vim.notify(string.format("No formatter or LSP available for filetype (%s)", ft), vim.log.levels.WARN, { title = "Conform" })
        return
      end

      c.format({ async = async, bufnr = bufnr }, function(err, did_edit)
        if err then
          -- LSP fallback passes the raw lsp.ResponseError table, which has no __tostring since Neovim 0.13
          local reason = type(err) == "table" and vim.lsp.rpc.format_rpc_error(err) or err
          vim.notify(string.format("Formatting failed in %s with %s: %s", filename, formatter_label, reason), vim.log.levels.ERROR, { title = "Conform" })
          return
        end

        if not did_edit then
          vim.notify(string.format("No changes made while formatting (%s)", ft), vim.log.levels.INFO, { title = "Conform" })
          return
        end

        vim.notify(string.format("Formatted %s with: %s", filename, formatter_label), vim.log.levels.INFO, { title = "Conform" })
      end)
    end

    vim.api.nvim_create_user_command("FormatWithConform", function() c.format_buffer({ async = true, quiet = false }) end, {
      desc = "Format current buffer with Conform and print formatters used",
    })
  end,
}
