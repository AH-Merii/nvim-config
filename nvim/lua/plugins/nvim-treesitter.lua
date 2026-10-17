-- Parsers no language in lua/lang/ names: Neovim's own files and injections (query, regex, vim, vimdoc) and proto. A
-- literal list: tests/regress/refresh.lua reads it, and the languages' parsers, to choose what to install
local ensure_installed = { "query", "regex", "vim", "vimdoc", "proto" }

-- TS indent can misbehave for these:
local indent_disabled = { "python", "yaml", "markdown" }

local select_textobjects = {
  -- Core text objects (well-supported for selection)
  ["af"] = { query = "@function.outer", desc = "Around function", icon = { icon = "󰊕", color = "purple" } },
  ["if"] = { query = "@function.inner", desc = "Inside function", icon = { icon = "󰊕", color = "purple" } },
  ["ac"] = { query = "@class.outer", desc = "Around class", icon = { icon = "", color = "purple" } },
  ["ic"] = { query = "@class.inner", desc = "Inside class", icon = { icon = "", color = "purple" } },
  ["ai"] = { query = "@conditional.outer", desc = "Around conditional", icon = { icon = "󰙁", color = "purple" } },
  ["ii"] = { query = "@conditional.inner", desc = "Inside conditional", icon = { icon = "󰙁", color = "purple" } },
  ["al"] = { query = "@loop.outer", desc = "Around loop", icon = { icon = "", color = "purple" } },
  ["il"] = { query = "@loop.inner", desc = "Inside loop", icon = { icon = "", color = "purple" } },
  ["ap"] = { query = "@parameter.outer", desc = "Around parameter", icon = { icon = "", color = "purple" } },
  ["ip"] = { query = "@parameter.inner", desc = "Inside parameter", icon = { icon = "", color = "purple" } },
  ["ab"] = { query = "@block.outer", desc = "Around block", icon = { icon = "󰅩", color = "purple" } },
  ["ib"] = { query = "@block.inner", desc = "Inside block", icon = { icon = "󰅩", color = "purple" } },

  -- Additional useful text objects
  ["a/"] = { query = "@comment.outer", desc = "Around comment", icon = { icon = "󰅺", color = "grey" } },
  ["aa"] = { query = "@call.outer", desc = "Around function call", icon = { icon = "󰅪", color = "purple" } },
  ["ia"] = { query = "@call.inner", desc = "Inside function call", icon = { icon = "󰅪", color = "purple" } },
  ["ar"] = { query = "@return.outer", desc = "Around return", icon = { icon = "󰌑", color = "purple" } },
  ["ir"] = { query = "@return.inner", desc = "Inside return", icon = { icon = "󰌑", color = "purple" } },
}

local move_textobjects = {
  goto_previous_start = {
    ["[f"] = { query = "@function.outer", desc = "Previous function", icon = { icon = "󰊕", color = "orange" } },
    ["[c"] = { query = "@class.outer", desc = "Previous class", icon = { icon = "", color = "orange" } },
    ["[p"] = { query = "@parameter.inner", desc = "Previous parameter", icon = { icon = "", color = "orange" } },
    ["[b"] = { query = "@block.outer", desc = "Previous block", icon = { icon = "󰅩", color = "orange" } },
    ["[i"] = { query = "@conditional.outer", desc = "Previous conditional", icon = { icon = "󰙁", color = "orange" } },
    ["[l"] = { query = "@loop.outer", desc = "Previous loop", icon = { icon = "", color = "orange" } },
    ["[a"] = { query = "@call.outer", desc = "Previous function call", icon = { icon = "󰅪", color = "orange" } },
    ["[r"] = { query = "@return.outer", desc = "Previous return", icon = { icon = "󰌑", color = "orange" } },
    ["[/"] = { query = "@comment.outer", desc = "Previous comment", icon = { icon = "󰅺", color = "grey" } },
  },
  goto_next_start = {
    ["]f"] = { query = "@function.outer", desc = "Next function", icon = { icon = "󰊕", color = "purple" } },
    ["]c"] = { query = "@class.outer", desc = "Next class", icon = { icon = "", color = "purple" } },
    ["]p"] = { query = "@parameter.inner", desc = "Next parameter", icon = { icon = "", color = "purple" } },
    ["]b"] = { query = "@block.outer", desc = "Next block", icon = { icon = "󰅩", color = "purple" } },
    ["]i"] = { query = "@conditional.outer", desc = "Next conditional", icon = { icon = "󰙁", color = "purple" } },
    ["]l"] = { query = "@loop.outer", desc = "Next loop", icon = { icon = "", color = "purple" } },
    ["]a"] = { query = "@call.outer", desc = "Next function call", icon = { icon = "󰅪", color = "purple" } },
    ["]r"] = { query = "@return.outer", desc = "Next return", icon = { icon = "󰌑", color = "purple" } },
    ["]/"] = { query = "@comment.outer", desc = "Next comment", icon = { icon = "󰅺", color = "grey" } },
  },
  goto_previous_end = {
    ["[F"] = { query = "@function.outer", desc = "Previous function end", icon = { icon = "󰡱", color = "cyan" } },
    ["[B"] = { query = "@block.outer", desc = "Previous block end", icon = { icon = "", color = "cyan" } },
  },
  goto_next_end = {
    ["]F"] = { query = "@function.outer", desc = "Next function end", icon = { icon = "󰡱", color = "cyan" } },
    ["]B"] = { query = "@block.outer", desc = "Next block end", icon = { icon = "", color = "cyan" } },
  },
}

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

return {
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
      -- on the first start lazy runs this config inside its install wait, where the install log raises a hit-enter prompt
      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function() ts.install(vim.list_extend(vim.deepcopy(require("lang").views().parsers), ensure_installed)) end,
      })

      require("nvim-treesitter-textobjects").setup({
        select = {
          lookahead = true,
          selection_modes = {
            ["@parameter.outer"] = "v",
            ["@parameter.inner"] = "v",
            ["@function.outer"] = "v",
            ["@conditional.outer"] = "v",
            ["@loop.outer"] = "v",
            ["@class.outer"] = "<c-v>",
            ["@block.outer"] = "v",
            ["@call.outer"] = "v",
            ["@comment.outer"] = "v",
            ["@assignment.outer"] = "v",
            ["@return.outer"] = "v",
          },
          include_surrounding_whitespace = true,
        },
        move = {
          set_jumps = true,
        },
      })
      require("config.textobjects").setup(select_textobjects, move_textobjects)

      local installs = {} -- language -> its one install task this session, so a failed build is not retried per buffer
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("UserTreesitter", { clear = true }),
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
