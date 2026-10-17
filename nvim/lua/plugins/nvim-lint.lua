-- Linting lives in lua/linting/; this loads nvim-lint for it, and adds the <leader>ll and <leader>li rows
return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local linting = require("linting")
    linting.setup()

    -- <leader>li where the filetype's language names a linter; <leader>ll where linting.buffer() would run one, a
    -- linter no attached server covers
    local keys = require("keys")
    keys.need("linter", function(buf) return linting.has(buf) end)
    keys.need("uncovered linter", function(buf)
      if not linting.has(buf) then
        return false
      end
      local plan = linting.plan(buf)
      return vim.iter(plan.linters):any(function(name) return not plan.covered[name] end)
    end)
    keys.feature("lint")({
      {
        "<leader>ll",
        function()
          linting.buffer(vim.api.nvim_get_current_buf())
          vim.notify("Linting...", vim.log.levels.INFO, { title = "nvim-lint" })
        end,
        "Trigger linting for current file",
        need = "uncovered linter",
      },
      {
        "<leader>li",
        function()
          local now = linting.plan(vim.api.nvim_get_current_buf())
          local linters = vim.tbl_map(
            function(name) return now.covered[name] and ("%s (reported by the %s server)"):format(name, now.covered[name]) or name end,
            now.linters
          )
          if #linters == 0 then
            print("No linters configured for filetype: " .. vim.bo.filetype)
          else
            print("Linters for " .. vim.bo.filetype .. ": " .. table.concat(linters, ", "))
          end
        end,
        "Show available linters for current filetype",
        need = "linter",
      },
    })
  end,
}
