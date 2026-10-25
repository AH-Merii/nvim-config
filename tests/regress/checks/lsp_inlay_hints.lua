-- @desc     a buffer whose server has inlay hints shows them without a key press; <leader>Th hides and shows them in that buffer only, and its which-key label follows
-- @areas    lsp which-key
-- @budget   30
-- @needs    clangd
-- clangd sends parameter-name hints with no setting (clangd's InlayHints.ParameterNames defaults to on)
local function open(name)
  vim.fn.writefile({ "int add(int a, int b) { return a + b; }", "int main(void) { return add(1, 2); }" }, name)
  vim.cmd.edit(name)
  local buf = vim.api.nvim_get_current_buf()
  local missing, why = wait_attach(buf, { "clangd" }, 20000)
  check(name .. ": clangd attaches", #missing == 0, vim.inspect(why))
  return buf
end
local function hints(buf) return vim.lsp.inlay_hint.get({ bufnr = buf }) end
local function labels(buf)
  return table.concat(vim.tbl_map(function(h)
    local l = h.inlay_hint.label
    return type(l) == "table" and table.concat(vim.tbl_map(function(p) return p.value end, l)) or l
  end, hints(buf)), " ")
end

local a = open("a.c")
check("hints show on attach, with no key pressed", wait_until(function() return #hints(a) > 0 end, 10000), labels(a))
check("the hints are clangd's parameter names", labels(a):find("a:", 1, true) ~= nil, labels(a))
check("<leader>Th offers to hide them", wk_lists(a, "n", "<leader>Th") == "Hide Inlay Hints", tostring(wk_lists(a, "n", "<leader>Th")))

local b = open("b.c")
check("a second buffer shows its hints too", wait_until(function() return #hints(b) > 0 end, 10000), labels(b))

vim.cmd.buffer(a)
feed("<leader>Th")
check("<leader>Th hides the buffer's hints", wait_until(function() return #hints(a) == 0 end, 2000), labels(a))
check("<leader>Th then offers to show them", wk_lists(a, "n", "<leader>Th") == "Show Inlay Hints", tostring(wk_lists(a, "n", "<leader>Th")))
check("the other buffer keeps its hints", #hints(b) > 0, labels(b))

feed("<leader>Th")
check("<leader>Th shows them again", wait_until(function() return #hints(a) > 0 end, 10000), labels(a))
