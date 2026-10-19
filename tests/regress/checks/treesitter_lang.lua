-- @desc     once treesitter attaches, and after <leader>TT turns it off and on, each filetype has regex syntax on beside it exactly when its language keeps it, and the runtime's indent plugin when its language keeps that; markdown draws no error inside a word and spell-checks text and table cells
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

-- Markdown, with treesitter alone (D135): an underscore inside a word isn't an error, and spelling is checked in table
-- cells, by the config's (pipe_table_cell) @spell, and still in text, by the base query's (inline) @spell, which the
-- addition must extend, not replace
vim.cmd.enew()
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].buftype = "nofile"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "# Notes",
  "",
  "Some ordinary text with a speling mistake, and a snake_case name.",
  "",
  "| Name | Note |",
  "| --- | --- |",
  "| alpha | a misteak here |",
})
vim.bo[buf].filetype = "markdown"
if check("markdown: treesitter attaches for the checks below", wait_until(function() return vim.treesitter.highlighter.active[buf] ~= nil end, 3000)) then
  vim.wo.spell = true
  vim.bo[buf].spelllang = "en"
  vim.treesitter.get_parser(buf):parse(true)
  -- The words ]s stops at, from the top, without wrapping around
  local wrapscan, flagged = vim.go.wrapscan, {}
  vim.go.wrapscan = false
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  for _ = 1, 10 do
    local before = vim.api.nvim_win_get_cursor(0)
    vim.cmd("silent! normal! ]s")
    local after = vim.api.nvim_win_get_cursor(0)
    if after[1] == before[1] and after[2] == before[2] then
      break
    end
    flagged[#flagged + 1] = vim.fn.expand("<cword>")
  end
  vim.go.wrapscan = wrapscan
  check("markdown: ]s flags the misspelled word in normal text and the one in a table cell", vim.deep_equal(flagged, { "speling", "misteak" }), vim.inspect(flagged))
  -- Regex syntax beside treesitter drew this as an error (markdownError, linked to Error)
  local at = vim.inspect_pos(buf, 2, assert(vim.api.nvim_buf_get_lines(buf, 2, 3, true)[1]:find("_", 1, true)) - 1)
  local errors = {}
  for _, item in ipairs(vim.list_extend(vim.list_extend({}, at.syntax), at.treesitter)) do
    for _, group in ipairs({ item.hl_group, item.hl_group_link }) do
      if group and group:lower():find("error", 1, true) then
        errors[#errors + 1] = group
      end
    end
  end
  check("markdown: an underscore inside a word in text isn't highlighted as an error", #errors == 0, table.concat(errors, ", "))
end
vim.api.nvim_buf_delete(buf, { force = true })
