---@type lang.Spec
return {
  filetypes = { "lua" },
  servers = { lua_ls = {} },
  formatters = { "stylua" },
  options = { expandtab = true, shiftwidth = 2, tabstop = 2 },
}
