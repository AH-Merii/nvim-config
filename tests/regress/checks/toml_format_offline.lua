-- @desc     saving a TOML file formats it without waiting on the network, with no schema cache or a stale one
-- @areas    format
-- @budget   40
-- @needs    tombi
local uv = vim.uv
local BAD, GOOD = { "a=1", "[t]", "b  =  'x'" }, { "a = 1", "", "[t]", 'b = "x"' }

-- A proxy that takes connections and never answers: every request through it hangs, as on a slow or dead network
local held = {}
local proxy = assert(uv.new_tcp())
assert(proxy:bind("127.0.0.1", 0))
assert(proxy:listen(16, function()
  local client = uv.new_tcp()
  proxy:accept(client)
  held[#held + 1] = client
end))
local url = ("http://127.0.0.1:%d"):format(proxy:getsockname().port)
for _, name in ipairs({ "HTTPS_PROXY", "https_proxy", "HTTP_PROXY", "http_proxy", "ALL_PROXY", "all_proxy" }) do
  vim.env[name] = url
end
vim.env.NO_PROXY, vim.env.no_proxy = nil, nil
-- every cached schema is past its time to live, so a schema-fetching formatter would fetch it again
vim.env.TOMBI_CACHE_TTL = "0"

local cases = {
  { name = "no schema cache" },
  -- tombi's cache layout: <cache home>/<scheme>/<host>/<path>
  { name = "a stale schema cache", seed = { "https/www.schemastore.org/api/json/catalog.json", '{"schemas":[]}' } },
}
for i, case in ipairs(cases) do
  local cache = ("%s/schema-cache-%d"):format(FIX, i)
  vim.fn.mkdir(cache, "p")
  if case.seed then
    local path = cache .. "/" .. case.seed[1]
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ case.seed[2] }, path)
  end
  vim.env.TOMBI_CACHE_HOME = cache

  local file = ("toml%d/settings.toml"):format(i)
  vim.fn.mkdir(vim.fs.dirname(file), "p")
  vim.fn.writefile(BAD, file)
  vim.cmd.edit(file)
  -- a formatter that times out or fails leaves the file as it was, and its error fails the check through the harness
  vim.cmd.write()
  check(case.name .. ": the written file is formatted", vim.deep_equal(vim.fn.readfile(file), GOOD), vim.inspect(vim.fn.readfile(file)))
end

for _, client in ipairs(held) do
  client:close()
end
proxy:close()
