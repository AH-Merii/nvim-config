-- format/'s adapter for conform.nvim: conform runs each formatter with the binary the resolver finds for the buffer's
-- project, and conform's formatexpr formats with gq. Nothing outside format/ requires conform for formatting.

local M = {}

-- How the config runs a formatter, merged over conform's own definition of it; a formatter conform lacks gets its whole
-- definition here, with `command` its bare binary name (the resolved path replaces it). Kept by tool, not by language:
-- conform keys formatters by name for every filetype, and a tool such as prettierd serves several languages
local definitions = {
  -- 2-space indentation, and manual alignment padding kept
  shfmt = { prepend_args = { "-i", "2", "-kp" } },
  -- The resolved fish runs its builtin fish_indent (fish >= 4.1, tools/catalog.lua): mise's fish is a single binary
  fish_indent = { args = { "-c", "builtin fish_indent" } },
}

function M.setup()
  local conform = require("conform")
  local tools = require("tools")
  local opts = {
    formatters = vim.deepcopy(definitions),
    -- Every filetype a language declares, variants included, so conform's lookup by a dotted filetype's parts decides
    -- nothing for them (lua/lang/)
    formatters_by_ft = vim.deepcopy(require("lang").views().conform),
    -- A server formats where no formatter runs
    default_format_opts = { lsp_format = "fallback" },
  }

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
  conform.setup(opts)

  vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
end

--- Whether conform would run formatter name on buf, for a formatter with no catalog binary to resolve.
---@param name string
---@param buf integer
---@return boolean
function M.available(name, buf)
  local ok, conform = pcall(require, "conform")
  return ok and conform.get_formatter_info(name, buf).available == true
end

--- conform.format, looked up when called, with its error as text.
---@param opts table conform.format's options
---@param cb fun(err?: string, did_edit?: boolean)
function M.format(opts, cb)
  require("conform").format(opts, function(err, did_edit)
    -- LSP fallback passes the raw lsp.ResponseError table, which has no __tostring since Neovim 0.13
    cb(type(err) == "table" and vim.lsp.rpc.format_rpc_error(err) or err, did_edit)
  end)
end

-- Loads conform for format/. Formatting on save and conform's formatexpr start at VeryLazy, as when the snacks spec
-- loaded conform for them; a write before then is not formatted
M.plugins = {
  {
    "stevearc/conform.nvim",
    event = "VeryLazy",
    cmd = { "ConformInfo", "FormatWithConform" },
    config = function() require("format").setup() end,
  },
}

return M
