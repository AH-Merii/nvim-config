-- @desc     entering a buffer lints it only when it changed, a file was written or reloaded, a shell command ran or Neovim regained focus since its last lint, or its filetype changed or its covering server left; a write and a reload always lint, and so does leaving insert mode after typing
-- @areas    lint
-- @budget   30
local lint = require("lint")
local spawned = {}
-- args are evaluated once per spawn, in the buffer being linted, so this counts runs per buffer
lint.linters.nvr_probe = {
  cmd = "sh",
  args = { function() local b = vim.api.nvim_get_current_buf(); spawned[b] = (spawned[b] or 0) + 1; return "-c" end, ":" },
  stdin = false, append_fname = false, ignore_exitcode = true,
  parser = function() return {} end,
}
-- a language for *.nvrskip, as a file in lua/lang/ would declare it; the nvr_cover server reports its linter's findings
require("lang")._declare("nvr_skip", { filetypes = { "nvrskip" }, linters = { nvr_probe = { covered_by = "nvr_cover" } } })
vim.filetype.add({ extension = { nvrskip = "nvrskip" } })
vim.fn.writefile({ "a" }, "a.nvrskip")
vim.fn.writefile({ "b" }, "b.nvrskip")
-- resolved up front, so no lint below skips the linter while its binary is looked up
local sh = require("tools").wait("sh", FIX, 10000)
if not check("sh resolves", sh ~= nil and sh.path ~= nil, vim.inspect(sh)) then return end

local function runs(buf) return spawned[buf] or 0 end
--- Whether buf runs one more lint after fn than before it. A lint that never comes is waited for 500 ms.
local function lints(buf, fn)
  local before = runs(buf)
  fn()
  return wait_until(function() return runs(buf) > before end, 500), ("%d -> %d runs"):format(before, runs(buf))
end
local function enter(buf) return function() vim.cmd.buffer(buf) end end

vim.cmd.edit("a.nvrskip")
local a = vim.api.nvim_get_current_buf()
check("the first entry lints", wait_until(function() return runs(a) == 1 end, 3000), runs(a))
vim.cmd.edit("b.nvrskip")
local b = vim.api.nvim_get_current_buf()
check("the first entry of a second buffer lints", wait_until(function() return runs(b) == 1 end, 3000), runs(b))

check("entering an unchanged buffer again does not lint", not lints(a, enter(a)))
vim.cmd.buffer(b)
check("entering it a third time does not lint either", not lints(a, enter(a)))

vim.cmd.buffer(b)
vim.api.nvim_buf_set_lines(a, 0, -1, false, { "a edited" })
check("entering a buffer edited since its last lint lints", lints(a, enter(a)))
vim.cmd("silent write")
check("entering a buffer after a write of another buffer lints", lints(b, enter(b)))

check("a write lints, even with nothing changed since the last lint", lints(b, function() vim.cmd("silent write") end))

check("leaving insert mode without typing does not lint", not lints(b, function() feed("i<Esc>") end))
check("leaving insert mode after typing lints", lints(b, function() feed("ix<Esc>") end))
vim.cmd("silent write")
vim.cmd.buffer(a)
vim.cmd.buffer(b)
-- a size change, so the reload needs no wait for a newer mtime
check("a reload from disk lints the reloaded buffer", lints(b, function()
  vim.fn.writefile({ "b reloaded from disk" }, "b.nvrskip")
  vim.cmd.checktime()
end))
check("the reload took the file's text", vim.api.nvim_buf_get_lines(b, 0, -1, false)[1] == "b reloaded from disk")
check("entering a buffer after another buffer reloaded lints", lints(a, enter(a)))

vim.fn.writefile({ "c" }, "c.txt")
vim.cmd.edit("c.txt")
local c = vim.api.nvim_get_current_buf()
vim.cmd.buffer(a)
vim.bo[c].filetype = "nvrskip"
check("entering a buffer whose filetype changed since its last entry lints", lints(c, enter(c)))
vim.cmd.buffer(a)

-- files may have changed outside Neovim: coming back to it (a terminal sends focus events), or a shell command
vim.cmd.buffer(b)
vim.cmd.buffer(a)
vim.api.nvim_exec_autocmds("FocusGained", {})
check("entering a buffer after Neovim regained focus lints", lints(b, enter(b)))
vim.cmd.buffer(a)
vim.cmd.buffer(b)
vim.cmd.buffer(a)
vim.cmd("silent !true")
check("entering a buffer after a shell command lints", lints(b, enter(b)))
vim.cmd.buffer(a)

-- an in-process stand-in for the covering server
local function covering_server(buf)
  local cmd = function(d)
    local closing = false
    local function close()
      if not closing then
        closing = true
        vim.schedule(function() d.on_exit(0, 15) end)
      end
    end
    return {
      request = function(method, _, callback)
        vim.schedule(function() callback(nil, method == "initialize" and { capabilities = {} } or vim.NIL) end)
        return true, 1
      end,
      notify = function(method)
        if method == "exit" then close() end
        return true
      end,
      is_closing = function() return closing end,
      terminate = close,
    }
  end
  return vim.lsp.start({ name = "nvr_cover", cmd = cmd, root_dir = FIX }, { bufnr = buf, reuse_client = function() return false end })
end
local id = covering_server(a)
if not check("the covering server attaches", wait_until(function() return vim.lsp.buf_is_attached(a, id) end, 3000)) then return end
vim.cmd.buffer(b)
vim.lsp.get_client_by_id(id):stop(true)
check("the covering server stops", wait_until(function() return vim.lsp.get_client_by_id(id) == nil end, 3000))
check("entering a buffer after its covering server left lints", lints(a, enter(a)))
