-- Message history picker, like noice's `:Noice history`: vim.notify calls (snacks.notifier's history)
-- and the ui2 messages config.ui2.messages saw (toasts, split output and what ui2 kept), newest first,
-- filterable by level, title and text. Toasts of ui2 messages skip snacks' history (history = false),
-- so nothing is listed twice. g< and :messages still open ui2's pager.
local M = {}

function M.open()
  local items = {}
  ---@param n { added: number, level: string, title: string?, msg: string }
  ---@param ft string?
  local function add(n, ft)
    items[#items + 1] = {
      text = Snacks.picker.util.text(n, { "level", "title", "kind", "msg" }),
      item = n,
      severity = n.level,
      preview = { text = n.msg, ft = ft },
    }
  end
  -- Same item shape as snacks' notifications source (snacks/picker/source/snacks.lua:4-21).
  for _, n in ipairs(Snacks.notifier.get_history()) do
    add(n, "markdown")
  end
  for _, e in ipairs(require("config.ui2.messages").entries()) do
    e.title = e.title or e.kind
    add(e)
  end
  table.sort(items, function(a, b) return a.item.added > b.item.added end)

  -- snacks' notifications picker config (snacks/picker/config/sources.lua:836-842) over these items.
  Snacks.picker.pick({
    title = "Messages",
    items = items,
    format = "notification",
    preview = "preview",
    formatters = { severity = { level = true } },
    confirm = "close",
  })
end

return M
