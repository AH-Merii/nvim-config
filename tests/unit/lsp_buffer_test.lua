-- K, the hover key lsp/buffer.lua declares, pressed where no attached server can hover (D165 in
-- docs/hover-decisions.md): in a buffer whose language names servers it says why instead of running 'keywordprg';
-- elsewhere it stays Vim's K. Tools on the fake backend, servers in-process:
-- nvim --clean --headless -l tests/unit/lsp_buffer_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local fake = require("fake_backend")
local server = require("fake_server")

local tmp = h.tmpdir()
require("tools.state").file = tmp .. "/state/projects.json"

-- Python names its two servers, as lua/lang/python.lua does; shell names none
package.loaded.lang = require("lang")._from({
  python = { filetypes = { "python" }, servers = { pyrefly = {}, ruff = {} } },
  shell = { filetypes = { "sh" }, formatters = { "shfmt" } },
})
local tools = require("tools")
local facts = require("ui.facts")
local keys = require("keys")

vim.g.mapleader = " "
require("lsp.buffer")

--- Runs what handlers scheduled; two rounds cover a schedule made from a scheduled callback.
local function settle()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    vim.wait(1000, function() return ran end, 5)
  end
end

-- Vim's K runs 'keywordprg'; each buffer's is this command, which records the word instead of running pydoc or man
local looked_up = {} ---@type string[]
vim.api.nvim_create_user_command("NvrKeyword", function(a) table.insert(looked_up, a.args) end, { nargs = "*" })

local n = 0
--- A file with one line, `x = 1`, of filetype ft in a fresh project dir, current, cursor on the x; installed: the
--- servers the fake backend has (pyrefly, ruff), each resolved before this returns. Keyword lookups start empty.
---@param ft string
---@param installed string[]
---@return integer buf, string dir
local function open(ft, installed)
  n = n + 1
  local dir = ("%s/%d"):format(tmp, n)
  vim.fn.mkdir(dir, "p")
  vim.env.PATH = dir -- an empty system PATH: only the fake's tools are found
  local global = {}
  for _, bin in ipairs(installed) do
    global[bin] = "1.0.0"
  end
  tools.setup({ backend = fake({ global = global }) })
  facts.setup()
  vim.cmd.edit(dir .. "/a." .. ft)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "x = 1" })
  vim.bo[buf].filetype = ft
  vim.bo[buf].keywordprg = ":NvrKeyword"
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  h.await(function(done) tools.resolve_all({ "pyrefly", "ruff" }, tools.root(buf), done) end)
  h.await(function(done) tools.project(tools.root(buf), done) end)
  settle()
  looked_up = {}
  return buf, dir
end

--- Whether the popup lists K in buf.
---@param buf integer
local function listed(buf)
  return vim.iter(keys.menu(buf)):any(function(item) return item.lhs == "K" end)
end

--- The messages echoed while K was pressed.
local function press_k()
  vim.cmd("messages clear")
  vim.api.nvim_feedkeys("K", "mx", false)
  settle()
  return vim.api.nvim_exec2("messages", { output = true }).output
end

--- A client of server name attached to buf whose initialize is never answered: a server still starting.
---@param buf integer
---@param name string
---@param dir string
---@return integer client id
local function starting(buf, name, dir)
  local id = vim.lsp.start({
    name = name,
    root_dir = dir,
    cmd = function(d)
      local closing = false
      local function close()
        if not closing then
          closing = true
          vim.schedule(function() d.on_exit(0, 15) end)
        end
      end
      return {
        request = function() return true, 1 end,
        notify = function() return true end,
        is_closing = function() return closing end,
        terminate = close,
      }
    end,
  }, { bufnr = buf, reuse_client = function() return false end })
  return assert(id, "vim.lsp.start returned no client")
end

local function stop(id)
  local client = vim.lsp.get_client_by_id(id)
  if client then
    client:stop(true)
  end
  vim.wait(3000, function() return vim.lsp.get_client_by_id(id) == nil end, 5)
  settle()
end

h.case("in a Python buffer whose servers are not installed, K names them and :Tools, and looks nothing up", function()
  local buf = open("python", {})
  local missing = facts.get(buf).missing
  h.ok(vim.list_contains(missing, "pyrefly") and vim.list_contains(missing, "ruff"), "precondition: the resolver found neither, missing: " .. vim.inspect(missing))
  local msg = press_k()
  h.eq(looked_up, {}, "'keywordprg' runs")
  h.ok(msg:find("pyrefly", 1, true) and msg:find("ruff", 1, true), "the message names both servers, got " .. msg)
  h.ok(msg:find("not installed", 1, true) and msg:find(":Tools", 1, true), "the message says they are not installed and names :Tools, got " .. msg)
  h.ok(not listed(buf), "K is in the menu, where it does not hover")
end)

h.case("where a server is still starting, K says so and looks nothing up", function()
  local buf, dir = open("python", { "pyrefly", "ruff" })
  local id = starting(buf, "pyrefly", dir)
  local msg = press_k()
  h.eq(looked_up, {}, "'keywordprg' runs")
  h.ok(msg:find("pyrefly is starting", 1, true), "the message says pyrefly is starting, got " .. msg)
  stop(id)
end)

h.case("where the attached servers have no hover, K says so and looks nothing up", function()
  local buf, dir = open("python", { "pyrefly", "ruff" })
  local a = server.start({ buf = buf, name = "pyrefly", methods = { "textDocument/definition" }, root_dir = dir })
  local b = server.start({ buf = buf, name = "ruff", methods = { "textDocument/codeAction" }, root_dir = dir })
  local msg = press_k()
  h.eq(looked_up, {}, "'keywordprg' runs")
  h.ok(msg:find("pyrefly and ruff have no hover", 1, true), "the message says neither has hover, got " .. msg)
  h.ok(not vim.iter(vim.list_extend(vim.deepcopy(a.requests), b.requests)):any(function(r) return r.method == "textDocument/hover" end), "a hover request was sent")
  a.stop()
  b.stop()
end)

h.case("where an installed server is not running, K says so and names :Tools", function()
  local buf = open("python", { "pyrefly", "ruff" })
  local msg = press_k()
  h.eq(looked_up, {}, "'keywordprg' runs")
  h.ok(msg:find("pyrefly and ruff are not running", 1, true) and msg:find(":Tools", 1, true), "the message says they are not running and names :Tools, got " .. msg)
end)

h.case("where a server hovers, K asks it and says nothing", function()
  local buf, dir = open("python", { "pyrefly", "ruff" })
  local hover = function() return { contents = { kind = "plaintext", value = "x: int" } } end
  local srv = server.start({ buf = buf, name = "pyrefly", methods = { "textDocument/hover" }, handlers = { ["textDocument/hover"] = hover }, root_dir = dir })
  local msg = press_k()
  local asked = vim.wait(2000, function() return vim.iter(srv.requests):any(function(r) return r.method == "textDocument/hover" end) end, 5)
  h.ok(asked, "pyrefly got no hover request")
  h.eq({ looked_up, msg }, { {}, "" }, "keyword lookups and messages")
  h.ok(listed(buf), "K is not in the menu where it hovers")
  vim.cmd("fclose!")
  srv.stop()
end)

h.case("where no server can attach, K stays Vim's K: it looks the word up", function()
  -- a filetype whose language names no servers, one no language declares, and a buffer servers never attach to
  open("sh", {})
  press_k()
  h.eq(looked_up, { "x" }, "a language with no servers")
  open("nvrnolang", {})
  press_k()
  h.eq(looked_up, { "x" }, "a filetype no language declares")
  local buf = open("python", {})
  vim.bo[buf].buftype = "nofile"
  press_k()
  h.eq(looked_up, { "x" }, "a Python buffer that is not a file")
end)

h.finish()
