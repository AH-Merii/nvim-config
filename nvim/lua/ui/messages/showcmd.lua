-- Pending keys in the statusline, without the keys whose command runs at once. Neovim puts every typed key in
-- 'showcmd' while its command runs, and with 'showcmdloc' "statusline" that drew one frame of "w" or "^D" per
-- keypress (docs/profiling-scrolling.md). With 'showcmdloc' "last" the text comes to ui2 as msg_showcmd events
-- instead (:h ui-messages), which this replaces: a lone key is left out unless its command waits for more keys.
-- The statusline draws M.get() (ui/statusline.lua). Without this hook 'showcmdloc' stays "statusline".
--
-- Not a delay: while a command waits for its next key (after a count or a g), Neovim runs no scheduled callbacks,
-- so a delayed count would never show.
--
-- ui2 is private (vim._core). R = $VIMRUNTIME/lua/vim/_core:
-- - R/ui2.lua:159,238: the UI callback looks the handler up in ui.msg on every event.
-- - R/ui2/messages.lua:583: msg_showcmd(content), content as in msg_show: { attr_id, text, hl_id } chunks.
local M = {}

-- Normal-mode keys that wait for another key ($VIMRUNTIME/doc/index.txt, *normal-index*): those taking a
-- {char}, {motion} or {register}, the g z Z [ ] CTRL-W CTRL-\ prefixes, and counts. 'showcmd' writes control
-- keys as ^X.
local waits = { ["^W"] = true, ["^\\"] = true }
for key in ([[!"'<=>@FT[]`fgmqrtzcdyZ123456789]]):gmatch(".") do
  waits[key] = true
end

local shown = ""

--- The pending keys to show, last 10 characters as ui2 shows them (R/ui2/messages.lua:584).
function M.get() return shown end

--- Whether the hook is installed, so the statusline draws M.get() rather than %S.
M.active = false

--- The 'showcmd' text to show: all of it, unless it is one key whose command needs nothing more. Visual mode's
--- selection size ("12", "3x5") is kept.
---@param text string
---@return string
function M.visible(text)
  local lone = #text == 1 or (#text == 2 and text:sub(1, 1) == "^")
  return (lone and not waits[text]) and "" or text
end

---@param ui table require("vim._core.ui2")
---@return boolean? false when the ui2 internal it hooks is missing
function M.setup(ui)
  if type(ui.msg.msg_showcmd) ~= "function" then
    return false
  end
  ui.msg.msg_showcmd = function(content)
    local text = M.visible(table.concat(vim.tbl_map(function(chunk) return chunk[2] end, content or {})):sub(-10))
    if text ~= shown then
      shown = text
      vim.cmd.redrawstatus()
    end
  end
  vim.o.showcmdloc = "last"
  M.active = true
end

return M
