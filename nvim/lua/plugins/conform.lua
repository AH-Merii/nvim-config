-- Formatting lives in lua/format/; this loads conform for it
return {
  "stevearc/conform.nvim",
  -- Formatting on save and conform's formatexpr start at VeryLazy, as when the snacks spec loaded conform for them; a
  -- write before then is not formatted
  event = "VeryLazy",
  cmd = { "ConformInfo", "FormatWithConform" },
  config = function() require("format").setup() end,
}
