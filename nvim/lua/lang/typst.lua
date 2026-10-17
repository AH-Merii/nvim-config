---@type lang.Spec
return {
  filetypes = { "typst" },
  -- tinymist formats with typstyle; conform has no formatter for typst, so LSP formatting runs
  servers = { tinymist = { root_markers = { "typst.toml", ".git" }, settings = { formatterMode = "typstyle" } } },
}
