-- Icons for snacks, which-key and diffview
return {
  plugins = {
    {
      src = "nvim-mini/mini.icons",
      -- After the first screen, not when required: snacks never requires mini.icons, it only reads the MiniIcons
      -- global that setup() sets
      setup = function() require("mini.icons").setup({}) end,
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
