-- What the config changes in Neovim's watched files ($VIMRUNTIME/lua/vim/lsp/_watchfiles.lua), which pyrefly
-- registers (lang/python.lua); on Linux Neovim watches them with inotifywait.

local M = {}

function M.setup()
  local watchfiles = vim.lsp._watchfiles

  -- A server can register watched files after its client was told to stop: pyrefly registers them again while a
  -- restart or the quit (lsp/init.lua) stops it. Client:stop cancelled the client's watchers before
  -- ($VIMRUNTIME/lua/vim/lsp/client.lua, Client:stop) and nothing cancels the new ones, so their inotifywait outlives
  -- the client and Neovim. Such a registration is dropped.
  local register = watchfiles.register
  watchfiles.register = function(reg, client_id)
    local client = vim.lsp.get_client_by_id(client_id)
    if client and client:is_stopped() then
      return
    end
    return register(reg, client_id)
  end
end

return M
