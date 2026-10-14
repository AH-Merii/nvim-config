-- @desc     the indent scope animates after a key pressed on its own, not while typed keys repeat, and not for keys a mapping or a smooth scroll's frames send
-- @areas    ui
-- @budget   15
vim.cmd.edit("main.lua")
local buf = vim.api.nvim_get_current_buf()
local function animates() return Snacks.animate.enabled({ buf = buf, name = "indent" }) end
local function typed(keys) vim.api.nvim_feedkeys(vim.keycode(keys), "mtx", false) end
local function pause() vim.wait(300) end

pause()
typed("j")
check("a key after a pause animates", animates() == true)
typed("k")
check("a key right after another does not", animates() == false)
pause()
typed("j")
check("after a pause it animates again", animates() == true)
-- what a smooth scroll's frames and mappings send: keys that were not typed
feed("j")
feed("k")
check("keys that were not typed don't count as repeats", animates() == true)
