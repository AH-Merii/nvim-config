-- @desc     which-key lists <leader>li wherever the filetype's language names a linter, and a press shows them with the covered ones marked; it lists <leader>ll only while one of them runs uncovered by an attached server, through attach, detach and filetype changes
-- @areas    lint lsp keys which-key
-- @budget   60
-- @args     notes.md
-- @needs    ruff
-- The rename key, also under <leader>l, is keys_lsp_gate's. Judged by the popup and a press, never by the maps
-- (README, "Rules for what goes in").
local lint = require("lint")

local function listed(buf, lhs)
  vim.cmd.buffer(buf)
  return wk_lists(buf, "n", lhs) ~= nil
end
-- what a press of <leader>li prints in buf
local function li_output(buf)
  vim.cmd.buffer(buf)
  local out, real = {}, _G.print
  _G.print = function(...) out[#out + 1] = table.concat(vim.tbl_map(tostring, { ... }), " ") end
  local ok, err = pcall(feed, "<leader>li")
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

vim.fn.writefile({ "plain words" }, FIX .. "/plain.txt")
vim.cmd.edit(FIX .. "/plain.txt")
local txt = vim.api.nvim_get_current_buf()
check("plain.txt is filetype text", vim.bo[txt].filetype == "text", vim.bo[txt].filetype)
check("text: neither <leader>ll nor <leader>li is listed", not listed(txt, "<leader>ll") and not listed(txt, "<leader>li"))
check("text: a press of <leader>li prints no linters", li_output(txt) == "")

vim.cmd.edit(FIX .. "/app.py")
local py = vim.api.nvim_get_current_buf()
if check("app.py: no server attached yet", #vim.lsp.get_clients({ bufnr = py }) == 0) then
  check("app.py before its servers attach: <leader>ll and <leader>li listed", listed(py, "<leader>ll") and listed(py, "<leader>li"))
end

-- the ruff server reports what the ruff linter would, and python names no other linter (lua/lang/python.lua)
local ruff
wait_until(function()
  ruff = vim.lsp.get_clients({ bufnr = py, name = "ruff" })[1]
  return ruff ~= nil
end, 20000)
if check("ruff server attached to app.py", ruff ~= nil) then
  check("python's only linter is ruff", vim.deep_equal(lint._resolve_linter_by_ft("python"), { "ruff" }), vim.inspect(lint._resolve_linter_by_ft("python")))
  check("<leader>ll not listed while the ruff server covers ruff", not listed(py, "<leader>ll"))
  check("<leader>li stays listed while ruff is covered", listed(py, "<leader>li"))
  local out = li_output(py)
  check("<leader>li marks ruff as covered by its server", out:find("ruff %(.-ruff.-%)") ~= nil, out)
  vim.lsp.buf_detach_client(py, ruff.id)
  check("<leader>ll listed again once the ruff server detaches", wait_until(function() return listed(py, "<leader>ll") end, 3000))
  out = li_output(py)
  check("<leader>li lists ruff unmarked after the detach", lists(out, { "ruff" }) and not out:find("%("), out)
end

-- filetype changes, on a filetype whose linter (yamllint) no server covers
for _, step in ipairs({ { "yaml", true }, { "text", false }, { "yaml", true }, { "", false } }) do
  vim.bo[txt].filetype = step[1]
  check(("filetype -> %q: <leader>ll and <leader>li %s"):format(step[1], step[2] and "listed" or "not listed"),
    listed(txt, "<leader>ll") == step[2] and listed(txt, "<leader>li") == step[2])
end

-- a variant gets its base's linters
vim.fn.writefile({ "services: {}" }, FIX .. "/docker-compose.yml")
vim.cmd.edit(FIX .. "/docker-compose.yml")
local dc = vim.api.nvim_get_current_buf()
check("docker-compose.yml is yaml.docker-compose", vim.bo[dc].filetype == "yaml.docker-compose", vim.bo[dc].filetype)
check("yaml.docker-compose: <leader>li listed", listed(dc, "<leader>li"))
local dc_out = li_output(dc)
check("<leader>li on yaml.docker-compose lists yamllint", lists(dc_out, { "yamllint" }), dc_out)
