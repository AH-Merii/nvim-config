;; extends
; Spell checking in table cells, which the markdown query (nvim-treesitter's and Neovim's) leaves out: it spells only
; (inline). Regex syntax spelled them before D135 turned it off for markdown
(pipe_table_cell) @spell
