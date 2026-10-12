-- @desc     <leader>ll only while a configured linter would run, <leader>li wherever linters are configured (covered ones marked), <leader>lr only with a rename-capable client
-- @areas    lint lsp keys
-- @budget   60
-- @version-sensitive
-- @args     notes.md
local lint = require("lint")
local function has(lhs, buf)
  -- maparg in the buffer's context sees global and buffer-local maps alike
  return vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(lhs, "n") ~= "" end)
end
local function li_output(buf)
  local out, real = {}, _G.print
  _G.print = function(...) out[#out + 1] = table.concat(vim.tbl_map(tostring, { ... }), " ") end
  local ok, err = pcall(vim.api.nvim_buf_call, buf, function() vim.fn.maparg("<leader>li", "n", false, true).callback() end)
  _G.print = real
  return ok and table.concat(out, "\n") or ("error: " .. tostring(err))
end
local function lists(text, names)
  if #names == 0 or text:find("No linters", 1, true) then return false end
  for _, n in ipairs(names) do
    if not text:find(n, 1, true) then return false end
  end
  return true
end

local at_filetype = {}
vim.api.nvim_create_autocmd("FileType", {
  pattern = "python",
  callback = function(ev)
    at_filetype[ev.buf] = at_filetype[ev.buf] or {
      lr = has("<leader>lr", ev.buf), ll = has("<leader>ll", ev.buf), li = has("<leader>li", ev.buf),
      clients = #vim.lsp.get_clients({ bufnr = ev.buf }),
    }
  end,
})

vim.fn.writefile({ "plain words" }, FIX .. "/plain.txt")
vim.cmd.edit(FIX .. "/plain.txt")
local txt = vim.api.nvim_get_current_buf()
check("plain.txt is filetype text", vim.bo[txt].filetype == "text", vim.bo[txt].filetype)
check("text buffer has no <leader>ll, <leader>li or <leader>lr", not has("<leader>ll", txt) and not has("<leader>li", txt) and not has("<leader>lr", txt))

vim.cmd.edit(FIX .. "/app.py")
local py = vim.api.nvim_get_current_buf()
local f = at_filetype[py]
check("python buffer at FileType: no client yet", f ~= nil and f.clients == 0, f and vim.inspect(f))
check("python buffer has <leader>ll and <leader>li before its servers attach", f ~= nil and f.ll and f.li)
check("no <leader>lr before any client attached", f ~= nil and not f.lr)

local renamer
wait_until(function()
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = py })) do
    if c:supports_method("textDocument/rename", py) then renamer = c.name return true end
  end
end, 20000)
check("a rename-capable client attached to app.py", renamer ~= nil, tostring(renamer))
check("<leader>lr once a rename-capable client attached", wait_until(function() return has("<leader>lr", py) end, 3000))
check("text buffer still has no <leader>lr", not has("<leader>lr", txt))

-- ruff the server reports what ruff the linter would; lint_buffer() skips the linter while it is attached
local ruff
wait_until(function() ruff = vim.lsp.get_clients({ bufnr = py, name = "ruff" })[1] return ruff ~= nil end, 20000)
if check("ruff server attached to app.py", ruff ~= nil) then
  if vim.deep_equal(lint._resolve_linter_by_ft("python"), { "ruff" }) then
    check("<leader>ll gone while the ruff server covers python's only linter", not has("<leader>ll", py))
  else
    info("python has linters besides ruff; <leader>ll removal not judged")
  end
  check("<leader>li stays while ruff is covered", has("<leader>li", py))
  local out = li_output(py)
  check("<leader>li marks ruff as covered by its server", out:find("ruff %(.-ruff.-%)") ~= nil, out)
  vim.lsp.buf_detach_client(py, ruff.id)
  check("<leader>ll back once the ruff server detaches", wait_until(function() return has("<leader>ll", py) end, 3000))
  out = li_output(py)
  check("<leader>li lists python's linters unmarked after detach", lists(out, lint.linters_by_ft.python or {}) and not out:find("%("), out)
end

-- filetype changes, on a filetype whose linter no server covers
for _, step in ipairs({ { "sh", true }, { "text", false }, { "sh", true }, { "", false } }) do
  vim.bo[txt].filetype = step[1]
  check(("filetype -> %q: <leader>ll and <leader>li %s"):format(step[1], step[2] and "present" or "absent"),
    has("<leader>ll", txt) == step[2] and has("<leader>li", txt) == step[2])
end

vim.fn.writefile({ "services: {}" }, FIX .. "/docker-compose.yml")
vim.cmd.edit(FIX .. "/docker-compose.yml")
local dc = vim.api.nvim_get_current_buf()
if vim.bo[dc].filetype ~= "yaml.docker-compose" then vim.bo[dc].filetype = "yaml.docker-compose" end
check("compose buffer has <leader>li", has("<leader>li", dc))
local dc_out = li_output(dc)
check("<leader>li on yaml.docker-compose lists yaml's linters", lists(dc_out, lint.linters_by_ft.yaml or {}), dc_out)
