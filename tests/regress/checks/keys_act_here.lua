-- @desc     a key with a need is listed by which-key, and acts when pressed, only where it would act at the cursor now (D132): the hunk keys on a hunk's line (staged or unstaged, as each acts), the hunk moves and buffer reset with an unstaged hunk, grx on a code lens's line, Neovim's own ]d and gx by their need though Neovim maps them; ]] and [[ stay listed wherever a server has document highlights (D132's exception); every row with a need is classified
-- @areas    keys git lsp which-key
-- @budget   60
-- Judged by pressing the keys and reading which-key's popup, never by which maps exist. Repos are made inside the
-- fixture copy; servers are in-process fakes.

local cur, n, bad
local function done()
  if cur and bad == 0 then check(cur, true, n .. " assertions") end
end
local function section(name)
  done()
  cur, n, bad = name, 0, 0
end
local function expect(ok, fmt, ...)
  n = n + 1
  if not ok then
    bad = bad + 1
    check(cur .. ": " .. fmt:format(...), false)
  end
  return ok
end
-- run what autocmds and handlers scheduled; two rounds cover a schedule made from a scheduled callback
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end
local function git(...) return vim.system({ "git", ... }, { text = true }):wait() end
--- Which of lhss which-key lists in buf (mode n), as "lhs lhs ...", in the order given.
local function listing(buf, lhss, mode)
  local out = {}
  for _, lhs in ipairs(lhss) do
    if wk_lists(buf, mode or "n", lhs) ~= nil then out[#out + 1] = lhs end
  end
  return table.concat(out, " ")
end
--- The messages echoed while fn ran.
local function echoed(fn)
  vim.cmd("messages clear")
  fn()
  flush()
  return vim.api.nvim_exec2("messages", { output = true }).output
end

section("the hunk keys follow the cursor's hunk")
-- a repo whose f.txt has a staged change on line 2, and unstaged ones: a change on line 5 and a deleted line below 6
local R = FIX .. "/.nvr-act"
local BASE = { "a", "b", "c", "d", "e", "f", "g", "h" }
git("init", "-q", R)
vim.fn.writefile(BASE, R .. "/f.txt")
git("-C", R, "add", "f.txt")
local r = git("-C", R, "-c", "user.name=nvr", "-c", "user.email=nvr@localhost", "-c", "commit.gpgsign=false", "commit", "-q", "--no-verify", "-m", "init")
assert(r.code == 0, "git commit: " .. (r.stderr or ""))
local STAGED = { "a", "B", "c", "d", "e", "f", "g", "h" }
vim.fn.writefile(STAGED, R .. "/f.txt")
git("-C", R, "add", "f.txt")
local WORK = { "a", "B", "c", "d", "E", "f", "h" }
vim.fn.writefile(WORK, R .. "/f.txt")
vim.cmd.edit(R .. "/f.txt")
local hbuf = vim.api.nvim_get_current_buf()
local cache = require("gitsigns.cache").cache
local function counts()
  local c = cache[hbuf]
  return ("%d/%d"):format(#(c and c.hunks or {}), #(c and c.hunks_staged or {}))
end
expect(wait_until(function() return counts() == "2/1" end, 5000), "gitsigns sees two unstaged hunks and one staged (got %s)", counts())
flush()
local HUNK = { "]g", "[g", "<leader>GR", "<leader>gd", "<leader>Gr", "<leader>Gs", "<leader>Gu", "<leader>gb", "<leader>Gd", "<leader>TG" }
local function at(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  return listing(hbuf, HUNK)
end
local ANY = "]g [g <leader>GR "
local ATTACHED = "<leader>gb <leader>Gd <leader>TG"
expect(at(1) == ANY .. ATTACHED, "line 1, no hunk: %s", at(1))
expect(at(2) == ANY .. "<leader>gd <leader>Gs <leader>Gu " .. ATTACHED, "line 2, staged: %s", at(2))
expect(at(5) == ANY .. "<leader>gd <leader>Gr <leader>Gs " .. ATTACHED, "line 5, unstaged change: %s", at(5))
expect(at(6) == ANY .. "<leader>gd <leader>Gr <leader>Gs " .. ATTACHED, "line 6, a deleted line below it: %s", at(6))

-- presses agree: away from a hunk the leader keys say which need fails and change nothing; on one they act
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local said = echoed(function() feed("<leader>Gr") end)
expect(said:find("hunk", 1, true) ~= nil, "<leader>Gr on line 1 says which need fails (said %q)", said)
expect(table.concat(vim.api.nvim_buf_get_lines(hbuf, 0, -1, false), " ") == table.concat(WORK, " "), "<leader>Gr on line 1 changes nothing")
said = echoed(function() feed("<leader>Gu") end)
expect(said:find("hunk", 1, true) ~= nil, "<leader>Gu on line 1 says which need fails (said %q)", said)
expect(vim.trim(git("-C", R, "diff", "--cached", "--name-only").stdout) == "f.txt", "<leader>Gu on line 1 leaves the index alone")
vim.api.nvim_win_set_cursor(0, { 5, 0 })
feed("<leader>Gr")
expect(wait_until(function() return vim.api.nvim_buf_get_lines(hbuf, 4, 5, false)[1] == "e" end, 3000), "<leader>Gr on line 5 resets its hunk")

-- with only the staged hunk left, the unstaged-hunk keys go and the staged ones stay on its line
vim.api.nvim_buf_set_lines(hbuf, 0, -1, false, STAGED)
vim.cmd("silent write")
expect(wait_until(function() return counts() == "0/1" end, 5000), "only the staged hunk is left (got %s)", counts())
flush()
expect(at(1) == ATTACHED, "no unstaged hunk, line 1: %s", at(1))
expect(at(2) == "<leader>gd <leader>Gs <leader>Gu " .. ATTACHED, "no unstaged hunk, line 2: %s", at(2))
vim.cmd.cd(FIX)

-- an in-process server with the given capabilities and answers, attached to buf
local function start_fake(buf, name, caps, answers)
  local function cmd(dispatchers)
    local closing = false
    return {
      request = function(method, _, callback)
        local result = method == "initialize" and { capabilities = caps } or (answers[method] or vim.NIL)
        vim.schedule(function() callback(nil, result) end)
        return true, 1
      end,
      notify = function(method)
        if method == "exit" and not closing then
          closing = true
          vim.schedule(function() dispatchers.on_exit(0, 15) end)
        end
        return true
      end,
      is_closing = function() return closing end,
      terminate = function()
        closing = true
        vim.schedule(function() dispatchers.on_exit(0, 15) end)
      end,
    }
  end
  local id = vim.lsp.start({ name = name, cmd = cmd, root_dir = FIX }, { bufnr = buf, reuse_client = function() return false end })
  wait_until(function()
    local c = id and vim.lsp.get_client_by_id(id)
    return c ~= nil and c.initialized and vim.lsp.buf_is_attached(buf, id)
  end, 3000)
  flush()
  return id
end
local function scratch(name, lines)
  vim.cmd.edit(FIX .. "/.nvr-act-" .. name)
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "sbxact"
  return buf
end

section("grx follows the code lens's line")
local ran = 0
vim.lsp.commands["nvr.act.lens"] = function() ran = ran + 1 end
local lbuf = scratch("lens.txt", { "def a():", "  pass", "def b():" })
local LENS = { { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 3 } }, command = { title = "run", command = "nvr.act.lens" } } }
local lid = start_fake(lbuf, "fake-lens", { codeLensProvider = {} }, { ["textDocument/codeLens"] = LENS })
expect(wait_until(function()
  vim.cmd.redraw()
  return #vim.lsp.codelens.get({ bufnr = lbuf }) == 1
end, 3000), "the lens arrived")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
expect(wk_lists(lbuf, "n", "grx") == nil, "grx is not listed on a line without a lens")
said = echoed(function() feed("grx") end)
expect(ran == 0 and said:find("code lens", 1, true) ~= nil, "grx there runs nothing and says which need fails (ran %d, said %q)", ran, said)
expect(vim.api.nvim_buf_get_lines(lbuf, 1, 2, false)[1] == "  pass", "grx there leaves the text alone (Vim's gr{char} would not)")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
expect(wk_lists(lbuf, "n", "grx") ~= nil, "grx is listed on the lens's line")
feed("grx")
expect(wait_until(function() return ran == 1 end, 3000), "grx there runs the lens")
vim.lsp.get_client_by_id(lid):stop(true)
wait_until(function() return vim.lsp.get_client_by_id(lid) == nil end, 3000)

section("]] and [[ stay listed wherever a server has document highlights (D132)")
local wbuf = scratch("words.txt", { "x = 1", "", "y = 2" })
local wid = start_fake(wbuf, "fake-words", { documentHighlightProvider = true }, { ["textDocument/documentHighlight"] = {} })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
expect(listing(wbuf, { "]]", "[[" }) == "]] [[", "on an empty line, with no references: %s", listing(wbuf, { "]]", "[[" }))
vim.lsp.get_client_by_id(wid):stop(true)
wait_until(function() return vim.lsp.get_client_by_id(wid) == nil end, 3000)

section("Neovim's own ]d, [d and gx are listed by their need though Neovim maps them")
local nbuf = scratch("neovim.txt", { "see https://example.com/x here", "plain words" })
expect(vim.fn.maparg("]d", "n") ~= "" and vim.fn.maparg("gx", "n") ~= "", "precondition: Neovim maps ]d and gx")
vim.api.nvim_win_set_cursor(0, { 2, 2 })
expect(listing(nbuf, { "]d", "[d", "gx" }) == "", "no diagnostic, on a plain word: %s", listing(nbuf, { "]d", "[d", "gx" }))
local ns = vim.api.nvim_create_namespace("nvr.act")
vim.diagnostic.set(ns, nbuf, { { lnum = 0, col = 0, message = "x", severity = vim.diagnostic.severity.WARN } })
vim.api.nvim_win_set_cursor(0, { 1, 8 })
expect(listing(nbuf, { "]d", "[d", "gx" }) == "]d [d gx", "a diagnostic, on a URL: %s", listing(nbuf, { "]d", "[d", "gx" }))
vim.diagnostic.reset(ns, nbuf)
-- a buffer's own map is listed as it always was
vim.keymap.set("n", "]d", "<Nop>", { buf = nbuf, desc = "The buffer's ]d" })
expect(wk_lists(nbuf, "n", "]d") ~= nil, "a buffer's own ]d is listed with no diagnostic")
-- last, once a file has loaded every plugin that adds rows (nvim-lint's at the first file)
section("every row with a need is classified")
-- Each row with a need, by mode and lhs: whether its need answers "would this key act at the cursor now" (cursor),
-- stays a buffer- or cwd-level answer by decision (buffer, with the reason), or is a server's capability, the closest
-- answer knowable without asking it (server, D133). A new row with a need fails here until it is classified.
local CURSOR, BUFFER, SERVER = "cursor", "buffer", "server"
local CLASS = {
  -- the hunk keys, on gitsigns' hunks at the cursor or in the buffer
  ["n ]g"] = CURSOR, ["n [g"] = CURSOR, ["n <leader>gd"] = CURSOR, ["n <leader>Gr"] = CURSOR, ["n <leader>GR"] = CURSOR,
  ["n <leader>Gs"] = CURSOR, ["n <leader>Gu"] = CURSOR,
  -- act anywhere in a buffer gitsigns is attached to: blame any line, diff against HEAD, the sign column
  ["n <leader>gb"] = CURSOR, ["n <leader>Gd"] = CURSOR, ["n <leader>TG"] = CURSOR,
  -- the cwd's repo, the file's repo, its remote, a GitHub remote: what the pickers and commands act on
  ["n <leader>gB"] = CURSOR, ["n <leader>gl"] = CURSOR, ["n <leader>gs"] = CURSOR, ["n <leader>gS"] = CURSOR,
  ["n <leader>gf"] = CURSOR, ["n <leader>GB"] = CURSOR, ["n <leader>p"] = CURSOR, ["x <leader>p"] = CURSOR,
  -- the repo has changes would take a git process per rebuild
  ["n <leader>gD"] = BUFFER,
  -- the picker logs HEAD's line at the cursor's number, not the buffer's line: a check on the buffer's line is no closer
  ["n <leader>gL"] = BUFFER,
  -- diagnostics in the buffer
  ["n <leader>dd"] = CURSOR, ["n <leader>sd"] = CURSOR, ["n ]d"] = CURSOR, ["n [d"] = CURSOR,
  -- the quickfix list, the window's location list: what the Trouble list keys open
  ["n <leader>dq"] = CURSOR, ["n <leader>dl"] = CURSOR,
  -- folds and spelling at the cursor, in the window
  ["n za"] = CURSOR, ["n zA"] = CURSOR, ["n zc"] = CURSOR, ["n zC"] = CURSOR, ["n zo"] = CURSOR, ["n zO"] = CURSOR,
  ["n zd"] = CURSOR, ["n zD"] = CURSOR, ["n zf"] = CURSOR, ["x zf"] = CURSOR, ["n z="] = CURSOR,
  ["n ]z"] = CURSOR, ["n [z"] = CURSOR, ["x ]z"] = CURSOR, ["x [z"] = CURSOR, ["o ]z"] = CURSOR, ["o [z"] = CURSOR,
  -- a misspelled word anywhere would take a spell scan of the buffer: spell checking on
  ["n ]s"] = BUFFER, ["n [s"] = BUFFER, ["x ]s"] = BUFFER, ["x [s"] = BUFFER, ["o ]s"] = BUFFER, ["o [s"] = BUFFER,
  ["n gx"] = CURSOR, ["n grx"] = CURSOR,
  -- the whole buffer: a formatter, a linter, an attached parser
  ["n <leader>lf"] = CURSOR, ["x <leader>lf"] = CURSOR, ["n <leader>Tf"] = CURSOR, ["n <leader>ll"] = CURSOR,
  ["n <leader>li"] = CURSOR, ["n <leader>v"] = CURSOR, ["x +"] = CURSOR, ["x -"] = CURSOR, ["n <leader>TT"] = CURSOR,
  -- D132: references of the word under the cursor read every extmark of the buffer, 2.46 ms per check
  ["n ]]"] = BUFFER, ["n [["] = BUFFER,
  -- D133
  ["n grn"] = SERVER, ["n gra"] = SERVER, ["x gra"] = SERVER, ["n gri"] = SERVER, ["n grt"] = SERVER, ["n gO"] = SERVER,
  ["n gd"] = SERVER, ["n gD"] = SERVER, ["n gI"] = SERVER, ["n gt"] = SERVER, ["n gCi"] = SERVER, ["n gCo"] = SERVER,
  ["n K"] = SERVER, ["n <leader>lr"] = SERVER, ["n grN"] = SERVER, ["n <leader>cs"] = SERVER, ["n <leader>cl"] = SERVER,
  ["n <leader>sS"] = SERVER, ["n grr"] = SERVER, ["n <leader>Th"] = SERVER, ["n <leader>Tc"] = SERVER,
  ["n <leader>Te"] = SERVER,
}
local keys = require("keys")
-- LSP methods by full name and by the name after "textDocument/", as a row names them
local METHODS = {}
for _, m in pairs(vim.lsp.protocol.Methods) do
  if type(m) == "string" then
    METHODS[m] = true
    METHODS[m:match("^textDocument/(.+)$") or m] = true
  end
end
local function method(need) return need:match("^client:") ~= nil or METHODS[need] == true end
local seen, unclassified = {}, {}
for _, row in ipairs(keys.list()) do
  if #row.need > 0 then
    local k = row.mode .. " " .. row.lhs
    seen[k] = true
    local class = CLASS[k]
    if not class then
      unclassified[#unclassified + 1] = ("%s (%s, %s)"):format(k, table.concat(row.need, " "), row.at)
    elseif class == SERVER then
      expect(vim.iter(row.need):all(method), "%s is classified as a server capability but needs %s", k, table.concat(row.need, " "))
    end
  end
end
table.sort(unclassified)
expect(#unclassified == 0, "unclassified rows with a need: %s", table.concat(unclassified, "; "))
local stale = vim.tbl_filter(function(k) return not seen[k] end, vim.tbl_keys(CLASS))
table.sort(stale)
expect(#stale == 0, "classified rows with no need, or gone: %s", table.concat(stale, ", "))

done()
