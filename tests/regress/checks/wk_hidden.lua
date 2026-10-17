-- @desc     the keys the config hides from the popup (Neovim's ]L ]Q ]T ]A ]D [<C-L> ... and ]% [%, and x-mode an/in under + and -) are mapped but never listed, in a buffer with a parser and one without
-- @areas    which-key keys
-- @budget   20
-- @args     app.py
local loaded = wait_until(function()
  local c = package.loaded["which-key.config"]
  return c ~= nil and rawget(c, "loaded") == true
end, 5000)
if not check("which-key loaded its spec", loaded, not loaded and "which-key.config never reached loaded" or nil) then return end
local Buf = require("which-key.buf")

-- from Neovim's default maps (:h [L, :h ]%) and the treesitter node selection (+ and - run them)
local HIDDEN = {
  n = { "]L", "[L", "]Q", "[Q", "]T", "[T", "]A", "[A", "]D", "[D", "]<C-L>", "[<C-L>", "]<C-Q>", "[<C-Q>", "]<C-T>", "[<C-T>", "]%", "[%" },
  x = { "]%", "[%" },
}
local function listed(buf, mode, lhs)
  local node = Buf.get({ buf = buf, mode = mode, update = true }).tree:find(vim.keycode(lhs))
  return node ~= nil and not node.hidden
end

local NOPARSER = vim.fn.fnamemodify(vim.fn.tempname(), ":h") .. "/plain.txt"
vim.fn.writefile({ "plain text" }, NOPARSER)
for _, file in ipairs({ "app.py", NOPARSER }) do
  vim.cmd.edit(file)
  local buf = vim.api.nvim_get_current_buf()
  local hidden = vim.deepcopy(HIDDEN)
  if vim.bo[buf].filetype == "python" then
    wait_until(function() return vim.treesitter.highlighter.active[buf] ~= nil end, 5000)
    vim.list_extend(hidden.x, { "an", "in" })
  end
  local mapped, shown = 0, {}
  for mode, keys in pairs(hidden) do
    for _, lhs in ipairs(keys) do
      if not vim.tbl_isempty(vim.fn.maparg(lhs, mode, false, true)) then mapped = mapped + 1 end
      if listed(buf, mode, lhs) then shown[#shown + 1] = mode .. ":" .. lhs end
    end
  end
  local name = vim.fn.fnamemodify(file, ":t")
  check(name .. ": the hidden keys are mapped", mapped > 0, mapped .. " mapped")
  check(name .. ": no hidden key is in the popup", #shown == 0, #shown > 0 and ("listed: " .. table.concat(shown, " ")) or nil)
end
