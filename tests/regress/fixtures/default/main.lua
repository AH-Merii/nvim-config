local M = {}
local unused = 1
function M.greet(name)
  vim.print("hi " .. name)
  return { a = 1, b = "two" }
end
return M
