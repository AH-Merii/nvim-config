-- Completion and snippets: blink.cmp, with friendly-snippets and lazydev's source

local specs = {
  -- blink's snippets source reads them from the runtimepath
  { src = "rafamadriz/friendly-snippets", phase = "startup" },
  {
    src = "saghen/blink.cmp",
    -- a release tag: blink downloads the prebuilt fuzzy matcher for the tag it is at
    version = vim.version.range("1.*"),
    phase = "startup",
    setup = function()
      require("blink.cmp").setup({
        sources = {
          per_filetype = {
            codecompanion = { "codecompanion" },
          },
          default = { "lazydev", "lsp", "path", "snippets", "buffer" },
          providers = {
            lazydev = {
              name = "LazyDev",
              module = "lazydev.integrations.blink",
              -- make lazydev completions top priority (see `:h blink.cmp`)
              score_offset = 100,
            },
            -- Path completion: `./` and `../` from the file's folder (blink's default get_cwd), any other relative path
            -- (`src/`, `docs/`) from the project root; absolute ones as typed (D163)
            path = { module = "features.completion_path" },
            cmdline = {
              min_keyword_length = 2,
            },
          },
        },
        cmdline = {
          completion = { menu = { auto_show = true } },
          keymap = {
            ["<Up>"] = { "select_prev", "fallback" },
            ["<Down>"] = { "select_next", "fallback" },
          },
        },
        completion = {
          list = {
            selection = {
              preselect = false,
              auto_insert = false,
            },
          },
          -- Configure how the menu looks; icon order, borders etc..
          menu = {
            auto_show = true,
            border = "rounded",
            scrolloff = 1,
            draw = {
              columns = {
                { "kind_icon" },
                { "label", "label_description", gap = 1 },
                { "kind" },
                { "source_name" },
              },
            },
          },

          -- Show documentation when selecting a completion item
          documentation = {
            window = {
              border = "rounded",
            },
            auto_show = true,
            auto_show_delay_ms = 500,
          },

          -- Display a preview of the selected item on the current line
          ghost_text = { enabled = true },
        },

        -- Signature help while typing a call (on trigger characters and after accepting an item);
        -- noice did this before ui2 replaced it. Border comes from 'winborder' (options.lua).
        signature = { enabled = true },
      })
    end,
  },
}

return { plugins = specs }
