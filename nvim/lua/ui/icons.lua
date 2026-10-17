-- Icons for snacks, which-key and diffview
return {
  plugins = {
    {
      "nvim-mini/mini.icons",
      -- VeryLazy, not lazy = true: snacks never requires mini.icons, it only reads the MiniIcons global that setup() sets
      event = "VeryLazy",
      opts = {},
      init = function()
        -- diffview's filetype icons require nvim-web-devicons; mini.icons stands in for it
        package.preload["nvim-web-devicons"] = function()
          require("mini.icons").mock_nvim_web_devicons()
          return package.loaded["nvim-web-devicons"]
        end
      end,
    },
  },
}
