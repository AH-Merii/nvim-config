-- @desc     once treesitter attaches, and after <leader>TT turns it off and on, each filetype has regex syntax on beside it exactly when its language keeps it, and the runtime's indent plugin when its language keeps that
-- @areas    treesitter editing
-- @budget   30
local lang = require("lang")

-- The indentexpr the runtime's indent plugins give ft, read in a buffer where no FileType autocmd ran
local function runtime_indentexpr(ft)
  local buf = vim.api.nvim_create_buf(false, true)
  local got
  vim.api.nvim_buf_call(buf, function()
    vim.cmd("noautocmd setlocal filetype=" .. ft)
    for _, part in ipairs(vim.split(ft, ".", { plain = true })) do
      vim.cmd(("runtime! indent/%s.vim indent/%s.lua"):format(part, part))
    end
    got = vim.bo.indentexpr
  end)
  vim.api.nvim_buf_delete(buf, { force = true })
  return got
end

local function regex_syntax(buf)
  local out = vim.api.nvim_buf_call(buf, function() return vim.api.nvim_exec2("syntax list", { output = true }).output end)
  return not out:find("No Syntax items defined", 1, true)
end

-- Every filetype a language declares whose parser is there with highlights
local fts, declared, undeclared = {}, 0, 0
for _, ft in ipairs(lang.filetypes()) do
  local parser = vim.treesitter.language.get_lang(ft)
  if parser and pcall(vim.treesitter.language.add, parser) and vim.treesitter.query.get(parser, "highlights") then
    fts[#fts + 1] = ft
    if lang.of(ft).treesitter then
      declared = declared + 1
    else
      undeclared = undeclared + 1
    end
  end
end
check("python is among the filetypes, and some declare treesitter settings and some none", vim.list_contains(fts, "python") and declared > 0 and undeclared > 0, ("%d declare, %d don't"):format(declared, undeclared))

for _, ft in ipairs(fts) do
  local settings = lang.of(ft).treesitter or {}
  local parser = assert(vim.treesitter.language.get_lang(ft))
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = ft
  if check(ft .. ": treesitter attaches", wait_until(function() return vim.treesitter.highlighter.active[buf] ~= nil end, 3000)) then
    check(ft .. ": regex syntax on beside treesitter " .. tostring(settings.syntax == true), regex_syntax(buf) == (settings.syntax == true))
    local want = runtime_indentexpr(ft)
    if settings.indent == false then
      check(ft .. ": keeps the runtime's indent plugin", vim.bo[buf].indentexpr == want, ("%q, want %q"):format(vim.bo[buf].indentexpr, want))
    elseif vim.treesitter.query.get(parser, "indents") then
      local got = vim.bo[buf].indentexpr
      check(ft .. ": treesitter indents, not the runtime's indent plugin", got ~= "" and got ~= want, ("%q, the runtime's %q"):format(got, want))
    end
    feed("<Space>TT")
    local off = vim.treesitter.highlighter.active[buf] == nil
    feed("<Space>TT")
    local on = vim.treesitter.highlighter.active[buf] ~= nil
    check(
      ft .. ": after <leader>TT off and on, regex syntax on beside treesitter " .. tostring(settings.syntax == true),
      off and on and regex_syntax(buf) == (settings.syntax == true),
      ("off %s, on %s, regex syntax %s"):format(off, on, regex_syntax(buf))
    )
  end
  vim.api.nvim_buf_delete(buf, { force = true })
end
