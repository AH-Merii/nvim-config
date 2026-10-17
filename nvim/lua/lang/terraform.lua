---@type lang.Spec
return {
  -- tf is the filetype Neovim gives a .tf file that looks like TinyFugue (vim.filetype.detect.tf); conform formats it too
  filetypes = { "terraform", "terraform-vars", "tf" },
  parsers = { "terraform" },
  servers = {
    terraformls = { filetypes = { "terraform", "terraform-vars" } },
    -- Without an exit_timeout Neovim doesn't wait for it on exit: its pipes close, it dies of SIGPIPE and its
    -- --act-as-bundled-plugin child is orphaned (core/lsp_servers.lua's VimLeavePre handler covers the rest)
    tflint = { filetypes = { "terraform" }, exit_timeout = 500 },
  },
  formatters = { "terraform_fmt" },
  linters = { tflint = { covered_by = "tflint", filetypes = { "terraform" } }, trivy = { filetypes = { "terraform" } } },
}
