-- Treesitter: highlighting and indent attached per buffer once its parsers are there (parsers/ installs them when a
-- buffer first needs them), the incremental selection keys and the treesitter toggle. The text objects and moves are
-- textobjects/. What a language keeps beside treesitter, its runtime indent plugin or regex syntax, is in its file in
-- lang/ (lang.Treesitter).

--- The treesitter settings of buf's language
---@param buf integer
---@return lang.Treesitter
local function settings(buf)
  local answer = require("lang").of(vim.bo[buf].filetype)
  return answer and answer.treesitter or {}
end

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

-- Starts treesitter's highlighting, then turns regex syntax back on where the language keeps it: vim.treesitter.start
-- turns it off, so it is turned on after every start, the toggle's included, and not with the language's options
---@param buf integer
---@param lang? string
local function highlight(buf, lang)
  vim.treesitter.start(buf, lang)
  if settings(buf).syntax then
    vim.bo[buf].syntax = "ON"
  end
end

local function attach(buf, lang)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.treesitter.language.add(lang) then
    return
  end
  if vim.treesitter.query.get(lang, "highlights") and not disable_on_large(lang, buf) then
    highlight(buf, lang)
  end
  if settings(buf).indent ~= false and vim.treesitter.query.get(lang, "indents") then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
  end
  attached[buf] = lang
end

local specs = {
  -- before nvim-treesitter, for textobjects/, which its setup sets up; textobjects/ wraps the plugin's modules when it
  -- is first required, so it is not required before this
  { src = "nvim-treesitter/nvim-treesitter-textobjects", version = "main", phase = "startup" },
  {
    src = "nvim-treesitter/nvim-treesitter",
    version = "main",
    -- before the first file's FileType; its setup uses Snacks.toggle, and snacks loads before it (ui/snacks.lua)
    phase = "startup",
    -- :TSUpdate, which nvim-treesitter's plugin/ file defines after this runs at startup
    build = function() require("nvim-treesitter").update(nil, { summary = true }) end,
    setup = function()
      local keys = require("keys")
      keys.need("treesitter", function(buf) return attached[buf] ~= nil end)
      keys.feature("treesitter", { need = "treesitter" })({
        -- incremental selection, on the core `an` (parent node) and `in` (child node)
        { "<leader>v", "van", "Start incremental selection", remap = true, icon = { icon = "󰩭", color = "cyan" } },
        { "+", "an", "Grow selection to parent node", mode = "x", remap = true, icon = { icon = "󰩭", color = "cyan" } },
        { "-", "in", "Shrink selection to child node", mode = "x", remap = true, icon = { icon = "󰩭", color = "cyan" } },
        {
          "<leader>TT",
          toggle = Snacks.toggle.treesitter({
            set = function(state)
              local buf = vim.api.nvim_get_current_buf()
              if state then
                highlight(buf, attached[buf])
              else
                vim.treesitter.stop(buf)
              end
            end,
          }),
        },
      })
      local group = vim.api.nvim_create_augroup("features.treesitter", { clear = true })

      require("textobjects").setup()

      -- Nothing is installed at startup (D116): a buffer's parsers install when it first needs them, after the UI is
      -- up, so their logs raise no hit-enter prompt (checks/fresh_no_prompt.sh)
      local parsers = require("parsers")
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        callback = function(args)
          attached[args.buf] = nil
          parsers.ensure(args.buf, function(lang) attach(args.buf, lang) end)
        end,
      })
    end,
  },
}

return { plugins = specs }
