-- sh and bash; bashls runs shellcheck itself
---@type lang.Spec
return {
  filetypes = { "sh", "bash" },
  servers = { bashls = {} },
  formatters = { "shfmt" },
}
