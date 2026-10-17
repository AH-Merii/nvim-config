-- Each language file's key rows (lua/lang/<lang>.lua `keys`), buffer-local in its filetypes' buffers (keys.language)
local keys = require("keys")

for ft, rows in vim.spairs(require("lang").views().keys) do
  keys.language(ft)(rows)
end
