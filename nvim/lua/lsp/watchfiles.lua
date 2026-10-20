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

  -- When a directory appears under the root and is renamed or removed before inotifywait can watch it, inotifywait
  -- prints "Couldn't watch new directory <dir>/: No such file or directory" and keeps watching; a rename's new name is
  -- watched from its move event (inotify-tools src/inotifywait.cpp, the IN_CREATE branch). cargo makes target/ that
  -- way, as target<random>/ then a rename (cargo-util's create_dir_all_excluded_from_backups_atomic). Neovim reports
  -- each stderr line as "file watcher failed" at ERROR ($VIMRUNTIME/lua/vim/_watch.lua, inotify), so those lines are
  -- left out of what reaches on_error; any other line is still reported.
  local watchfunc = watchfiles._watchfunc
  watchfiles._watchfunc = function(rules, opts, callback)
    local on_error = opts.on_error
    return watchfunc(
      rules,
      vim.tbl_extend("force", opts, {
        on_error = on_error and function(err)
          -- vim._watch appends the root it watches to the backend's error
          local text, root = err:match("^(.-)\n?( %(watching [^\n]*%))$")
          local lines = vim.split(text or err, "\n", { trimempty = true })
          local kept = vim.tbl_filter(function(line) return not line:match("^Couldn't watch new directory .*: No such file or directory$") end, lines)
          if #kept == #lines then
            on_error(err)
          elseif #kept > 0 then
            on_error(table.concat(kept, "\n") .. "\n" .. (root or ""))
          end
        end,
      }),
      callback
    )
  end
end

return M
