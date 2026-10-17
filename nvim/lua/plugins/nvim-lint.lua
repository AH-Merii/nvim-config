-- Linting lives in lua/linting/; this loads nvim-lint for it, and maps <leader>ll and <leader>li where they apply
return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local linting = require("linting")
    linting.setup()

    ---@param buf integer
    local function map_lint_keys(buf)
      pcall(vim.keymap.del, "n", "<leader>ll", { buf = buf })
      pcall(vim.keymap.del, "n", "<leader>li", { buf = buf })
      local plan = linting.plan(buf)
      if #plan.linters == 0 then
        return
      end

      -- Manual linting command, while linting.buffer() would run at least one linter
      if vim.iter(plan.linters):any(function(name) return not plan.covered[name] end) then
        vim.keymap.set("n", "<leader>ll", function()
          linting.buffer(buf)
          vim.notify("Linting...", vim.log.levels.INFO, { title = "nvim-lint" })
        end, { buf = buf, desc = "Trigger linting for current file" })
      end

      -- Show linter status
      vim.keymap.set("n", "<leader>li", function()
        local now = linting.plan(buf)
        local linters = vim.tbl_map(
          function(name) return now.covered[name] and ("%s (reported by the %s server)"):format(name, now.covered[name]) or name end,
          now.linters
        )
        if #linters == 0 then
          print("No linters configured for filetype: " .. vim.bo.filetype)
        else
          print("Linters for " .. vim.bo.filetype .. ": " .. table.concat(linters, ", "))
        end
      end, { buf = buf, desc = "Show available linters for current filetype" })
    end

    local group = vim.api.nvim_create_augroup("UserAutocmdsNvimLint", { clear = true })
    vim.api.nvim_create_autocmd({ "FileType", "LspAttach" }, { group = group, callback = function(ev) map_lint_keys(ev.buf) end })
    vim.api.nvim_create_autocmd("LspDetach", {
      group = group,
      callback = function(ev)
        -- The detaching client still counts as attached while LspDetach runs
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(ev.buf) then
            map_lint_keys(ev.buf)
          end
        end)
      end,
    })
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        map_lint_keys(buf)
      end
    end
  end,
}
