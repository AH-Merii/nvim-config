-- snacks.nvim: the picker, the notifier, and the rest of snacks the config uses (indent guides, scrolling, the
-- status column, words, profiler, scratch, zen). The features declare the keys that call it.
local M = {}

---@type snacks.Config
local opts = {
  bigfile = { enabled = true },
  profiler = { enabled = true },
  dashboard = { enabled = false }, --
  explorer = { enabled = false }, --
  indent = {
    enabled = true,
    -- The scope grows out from the cursor in 150 ms rather than snacks' 500 (20 ms a line): a jump settled sooner
    -- and redrew for half as long (docs/profiling-scrolling.md)
    animate = { duration = { step = 10, total = 150 } },
  },
  input = { enabled = true },
  picker = {
    enabled = true,
    win = {
      input = {
        keys = {
          -- Navigation
          ["<C-h>"] = { "focus_list", mode = { "n", "i" } },
          ["<C-l>"] = { "focus_preview", mode = { "n", "i" } },
          ["<C-k>"] = { "focus_list", mode = { "n", "i" } },
          ["<C-j>"] = { "focus_preview", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          -- Navigation
          ["<C-h>"] = { "focus_input", mode = { "n" } },
          ["<C-l>"] = { "focus_preview", mode = { "n" } },
          ["<C-k>"] = { "focus_input", mode = { "n" } },
          ["<C-j>"] = { "focus_preview", mode = { "n" } },
        },
      },
      preview = {
        keys = {
          -- Only map "go back to picker" keys; C-l/C-j are no-op (already at destination)
          ["<C-h>"] = { "focus_list", mode = { "n" } },
          ["<C-k>"] = { "focus_list", mode = { "n" } },
        },
      },
    },
  },
  notifier = {
    enabled = true,
    -- Errors stay until dismissed (<leader>N), like ui2 message errors, except the routine ones
    -- neoblocks' messages module marks `routine` (a search that found nothing); the rest is snacks' default keep
    -- (snacks/notifier.lua:131-133).
    keep = function(n) return n.level == "error" and not n.routine or vim.fn.getcmdpos() > 0 end,
  },
  quickfile = { enabled = true },
  -- The scope still draws, without snacks' keys: they mapped [i ]i ii ai over the conditional textobjects, set up on
  -- UIEnter after ours, while the popup kept our labels (D146). [b ]b [B ]B jump to a block's edges
  scope = { enabled = true, keys = { jump = { ["[i"] = false, ["]i"] = false }, textobject = { ii = false, ai = false } } },
  scroll = {
    enabled = true,
    -- Front-loaded, so C-d/C-u cover half the distance in about 20 ms, and done in about 80 ms; snacks' default
    -- is linear over 200 ms, halfway at about 85 ms (docs/profiling-scrolling.md)
    animate = { duration = { step = 10, total = 120 }, easing = "outCubic" },
  },
  statuscolumn = {
    enabled = true,
    folds = {
      open = true, -- show open fold icons
      git_hl = false, -- use Git Signs hl for fold icons
    },
  },
  words = { enabled = true },
}

--- Merges more of snacks' options over these, before snacks loads: the features' own (trouble's picker actions,
--- features/diagnostics.lua)
---@param more snacks.Config
function M.extend(more) opts = vim.tbl_deep_extend("force", opts, more) end

local spec = {
  src = "folke/snacks.nvim",
  -- right after the theme: the startup plugins after it use Snacks (the treesitter toggle)
  phase = "startup",

  setup = function()
    require("snacks").setup(opts)

    -- Nightly names its built-in modules "@vim/loader", without ".lua", and the profiler reads that path as a file
    local loc = require("snacks.profiler.loc")
    local ts_locs = loc.ts_locs
    loc.ts_locs = function(file)
      for _, f in ipairs({ file, file .. ".lua", file .. "/init.lua" }) do
        if vim.fn.filereadable(f) == 1 then
          return ts_locs(f)
        end
      end
      return {}
    end

    -- The indent scope animates after a key pressed on its own, not while keys repeat (a held j or C-d): each of
    -- those started another 150 ms of redraws for a scope the cursor then left (docs/profiling-scrolling.md). Keys,
    -- not cursor moves, since a smooth scroll's frames move the cursor too; and only typed ones, since the frames run
    -- `normal!` and mappings expand. A buffer variable, which snacks reads before the global one.
    local last_key = 0
    vim.on_key(function(_, typed)
      if not typed or typed == "" then
        return
      end
      local now = vim.uv.hrtime()
      if now - last_key > 150e6 then
        vim.b.snacks_animate_indent = nil
      else
        vim.b.snacks_animate_indent = false
      end
      last_key = now
    end, vim.api.nvim_create_namespace("config.indent_at_rest"))

    -- snacks caches each row of the statuscolumn by its relative number too, which with 'relativenumber' changes for
    -- every row on every j, and empties the cache every 50 ms. Rows are cached here around their number, which is
    -- put back in each time the way snacks picks it (absolute on the cursor line, relative elsewhere), for 200 ms:
    -- signs and marks show at most that late (docs/profiling-scrolling.md).
    local stc = require("snacks.statuscolumn")
    local stc_get = stc.get
    local rows = {} ---@type table<string, string[]> the row before and after its number, or the whole row
    local wins = {} ---@type table<integer, boolean[]> each window's 'number' and 'relativenumber'
    assert(vim.uv.new_timer()):start(200, 200, function()
      rows, wins = {}, {}
    end)
    vim.api.nvim_create_autocmd("OptionSet", {
      pattern = { "number", "relativenumber" },
      callback = function()
        rows, wins = {}, {}
      end,
    })
    stc.get = function()
      local win = vim.g.statusline_winid
      local buf = vim.api.nvim_win_get_buf(win)
      local w = wins[win]
      if not w then
        w = { vim.wo[win].number, vim.wo[win].relativenumber }
        wins[win] = w
      end
      local nu, rnu = w[1], w[2]
      local num = (nu or rnu) and vim.v.virtnum == 0 and ((rnu and not (nu and vim.v.relnum == 0)) and vim.v.relnum or vim.v.lnum)
      local key = ("%d:%d:%d:%d:%s:%s"):format(win, buf, vim.v.lnum, vim.v.virtnum ~= 0 and 1 or 0, nu, rnu)
      local row = rows[key]
      if not row then
        -- snacks writes the number as "%=<number> "; found by its shape, since snacks' own cache can hand back a
        -- row drawn just before 'number' or 'relativenumber' changed
        local s = stc_get()
        local from, to = s:find("%%=%d+ ")
        row = from and { s:sub(1, from - 1), s:sub(to + 1) } or { s }
        rows[key] = row
      end
      if not row[2] then
        return row[1]
      end
      return num and (row[1] .. "%=" .. num .. " " .. row[2]) or (row[1] .. row[2])
    end
  end,

  init = function()
    -- What snacks itself shows: the toggles' group, the message history (neoblocks' messages) and the notifications
    local function icon(glyph, color) return { icon = glyph, color = color } end
    -- neoblocks may have failed to install or load; its install failure is a toast of its own (lua/app/plugins.lua)
    local function history()
      local ok, nb = pcall(require, "neoblocks")
      if not (ok and nb.did_setup) then
        return vim.notify("Message history: neoblocks.nvim isn't loaded; :messages has ui2's", vim.log.levels.WARN)
      end
      nb.messages.history()
    end
    require("keys").feature("ui")({
      { "<leader>T", group = "Toggle Features", icon = icon("", "yellow") },
      { "<leader>n", history, "Message History", icon = icon("󰂚", "yellow") },
      { "<leader>N", function() Snacks.notifier.hide() end, "Dismiss Notifications", icon = icon("󰎟", "yellow") },
    })
  end,
}

M.plugins = { spec }

return M
