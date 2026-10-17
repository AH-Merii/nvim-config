-- PHP: no tools, only the labels for its runtime ftplugin's maps
local NXO = { "n", "x", "o" }

---@type lang.Spec
return {
  filetypes = { "php" },
  -- Labels for the runtime ftplugin's motions, which it maps without a desc, so the popup would show their rhs
  keys = {
    { "]]", label = "Next function/class line", mode = NXO },
    { "[[", label = "Previous function/class line", mode = NXO },
    filetypes = { "php" },
  },
}
