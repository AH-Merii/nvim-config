-- @desc     before VeryLazy, requiring a module of a deferred plugin loads that plugin and returns that module (the member its caller uses), for the four cross-plugin requires (snacks to which-key and conform, blink to lazydev, the picker to trouble)
-- @areas    startup completion ui which-key
-- @budget   20
-- A headless nvim with no harness never gets VeryLazy (lua/app/init.lua), so its deferred plugins stay unloaded
-- until something requires them (lua/app/plugins.lua, the package loader).
-- member: what the caller uses from the module (keys/which_key.lua:134, format/conform.lua:65, blink's source
-- constructor lazydev/integrations/blink.lua:10, the picker actions trouble/sources/snacks.lua:102), so a loader that
-- returns some other module (its top-level one) fails
local CASES = {
  { module = "which-key", plugin = "which-key.nvim", member = "show" },
  { module = "conform", plugin = "conform.nvim", member = "format" },
  { module = "lazydev.integrations.blink", plugin = "lazydev.nvim", member = "new" },
  { module = "trouble.sources.snacks", plugin = "trouble.nvim", member = "actions" },
}
local out = vim.fn.tempname()
local probe = vim.fn.tempname() .. ".lua"
vim.fn.writefile({
  "local cases, rows = vim.json.decode(vim.env.NVR_CASES), {}",
  "local function loaded(name)",
  "  for _, p in ipairs(require('app.plugins').list()) do if p.name == name then return p.loaded end end",
  "end",
  "for _, c in ipairs(cases) do",
  "  local before = loaded(c.plugin)",
  "  local ok, mod = pcall(require, c.module)",
  "  rows[#rows + 1] = vim.json.encode({ module = c.module, before = before, ok = ok,",
  "    member = ok and type(mod) == 'table' and mod[c.member] ~= nil,",
  "    err = not ok and tostring(mod) or nil, after = loaded(c.plugin) })",
  "end",
  "vim.fn.writefile(rows, vim.env.NVR_OUT)",
}, probe)
local child = vim.system({ vim.env.NV, vim.env.V, "--headless", "-c", "luafile " .. probe, "-c", "qa!" }, {
  stdin = false,
  env = { NVR_CASES = vim.json.encode(CASES), NVR_OUT = out },
}):wait(15000)
local rows = vim.fn.filereadable(out) == 1 and vim.fn.readfile(out) or {}
os.remove(out)
os.remove(probe)
if not check("the probe reported every case", #rows == #CASES, ("exit %s, %d rows"):format(tostring(child.code), #rows)) then
  return
end
for i, line in ipairs(rows) do
  local r = vim.json.decode(line)
  local c = CASES[i]
  check(("precondition: %s is not loaded before VeryLazy"):format(c.plugin), r.before == false, vim.inspect(r.before))
  check(("require(%q) loads %s and returns its module (with %s)"):format(c.module, c.plugin, c.member),
    r.ok and r.member and r.after == true,
    r.err or vim.inspect(r))
end
