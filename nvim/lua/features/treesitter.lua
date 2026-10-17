-- Treesitter: parsers installed (the languages' and Neovim's own), highlighting and indent attached per buffer, the
-- incremental selection keys and the treesitter toggle. The text objects and moves are textobjects/.

-- Parsers no language in lua/lang/ names: Neovim's own files and injections (query, regex, vim, vimdoc) and proto. A
-- literal list: tests/regress/refresh.lua reads it, and the languages' parsers, to choose what to install
local ensure_installed = { "query", "regex", "vim", "vimdoc", "proto" }

-- TS indent can misbehave for these:
local indent_disabled = { "python", "yaml", "markdown" }

-- custom function to disable treesitter on large files
local function disable_on_large(lang, buf)
  local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
  local is_disabled = ok and stats and stats.size > 2 * 1024 * 1024 -- >2MB
  if is_disabled then
    vim.schedule(
      function() vim.notify(string.format("Treesitter disabled for %s (file >2MB)", lang or "unknown"), vim.log.levels.WARN, { title = "nvim-treesitter" }) end
    )
  end
  return is_disabled
end

-- The buffers treesitter attached to: where the incremental selection keys and the toggle act
local attached = {} ---@type table<integer, string>

local function attach(buf, lang)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.treesitter.language.add(lang) then
    return
  end
  if vim.treesitter.query.get(lang, "highlights") and not disable_on_large(lang, buf) then
    vim.treesitter.start(buf, lang)
    if lang == "markdown" then
      vim.bo[buf].syntax = "ON"
    end
  end
  if not vim.list_contains(indent_disabled, lang) and vim.treesitter.query.get(lang, "indents") then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
  attached[buf] = lang
end

local specs = {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    version = false,
    lazy = false,
    build = {
      -- master compiled parsers into the plugin dir; main installs them under stdpath("data")/site
      function(plugin)
        vim.fn.delete(plugin.dir .. "/parser", "rf")
        vim.fn.delete(plugin.dir .. "/parser-info", "rf")
      end,
      ":TSUpdate",
    },
    dependencies = {
      -- loaded first, for textobjects/, which config sets up; textobjects/ wraps the plugin's modules when it is
      -- first required, so it is not required before this
      { "nvim-treesitter/nvim-treesitter-textobjects", branch = "main" },
      -- config uses Snacks.toggle; on the first start lazy runs configs as plugins finish installing, not by priority
      "folke/snacks.nvim",
    },
    config = function()
      local ts = require("nvim-treesitter")
      local keys = require("keys")
      keys.need("treesitter", function(buf) return attached[buf] ~= nil end)
      keys.feature("treesitter", { need = "treesitter" })({
        -- incremental selection, on the core `an` (parent node) and `in` (child node)
        { "<leader>v", "van", "Start incremental selection", remap = true, icon = { icon = "󰩭", color = "cyan" } },
        { "+", "an", "Grow selection to parent node", mode = "x", remap = true, icon = { icon = "󰩭", color = "cyan" } },
        { "-", "in", "Shrink selection to child node", mode = "x", remap = true, icon = { icon = "󰩭", color = "cyan" } },
        { "<leader>TT", toggle = Snacks.toggle.treesitter() },
      })
      local group = vim.api.nvim_create_augroup("features.treesitter", { clear = true })
      -- on the first start lazy runs this config inside its install wait, where the install log raises a hit-enter prompt
      vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        once = true,
        callback = function() ts.install(vim.list_extend(vim.deepcopy(require("lang").views().parsers), ensure_installed)) end,
      })

      require("textobjects").setup()

      local installs = {} -- language -> its one install task this session, so a failed build is not retried per buffer
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        callback = function(args)
          local lang = vim.treesitter.language.get_lang(args.match)
          if lang and vim.treesitter.language.add(lang) then
            attach(args.buf, lang)
            return
          end
          attached[args.buf] = nil
          if lang and vim.list_contains(ts.get_available(), lang) then
            installs[lang] = installs[lang] or ts.install(lang)
            installs[lang]:await(function()
              vim.schedule(function() attach(args.buf, lang) end)
            end)
          end
        end,
      })
    end,
  },
}

return { plugins = specs }
