---@type lang.Spec
return {
  -- tf is the filetype Neovim gives a .tf file that looks like TinyFugue (vim.filetype.detect.tf); conform formats it too
  filetypes = { "terraform", "terraform-vars", "tf" },
  parsers = { "terraform" },
  servers = {
    terraformls = { filetypes = { "terraform", "terraform-vars" } },
    tflint = { filetypes = { "terraform" } },
  },
  formatters = { "terraform_fmt" },
  linters = { tflint = { covered_by = "tflint", filetypes = { "terraform" } }, trivy = { filetypes = { "terraform" } } },
}
