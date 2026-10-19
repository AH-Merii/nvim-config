-- C and C++
---@type lang.Spec
return {
  filetypes = { "c", "cpp" },
  -- nvim-lspconfig's list: clangd also serves Objective-C and CUDA, which get no formatter here
  servers = { clangd = { filetypes = { "c", "cpp", "objc", "objcpp", "cuda" } } },
  formatters = { "clang-format" },
  variants = {
    -- In nvim-lspconfig's clangd list; nothing in Neovim or this config sets them
    ["c.doxygen"] = { about = "C with Doxygen comments, from nvim-lspconfig's clangd filetypes" },
    ["cpp.doxygen"] = { about = "C++ with Doxygen comments, from nvim-lspconfig's clangd filetypes" },
  },
}
