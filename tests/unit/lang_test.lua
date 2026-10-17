-- The language registry's rules on small fixture languages, then validity and completeness over the real language
-- files: nvim --clean --headless -l tests/unit/lang_test.lua
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local h = require("helper")
local lang = require("lang")
local catalog = require("tools.catalog")

-- Two fixture languages. Their tool names are in no catalog, so each tool's binary is its name.
local function fixture()
  return {
    alpha = {
      filetypes = { "alpha", "alphax" },
      parsers = { "alpha", "shared" },
      servers = { aserver = { settings = { x = 1 } }, narrow = { filetypes = { "alpha" } } },
      formatters = { "afmt1", "afmt2" },
      linters = { alint = { covered_by = "aserver" }, zlint = { filetypes = { "alphax" } } },
      options = { shiftwidth = 3 },
      keys = { { "]]", label = "Next alpha" } },
      variants = {
        ["alpha.own"] = {
          about = "names its own server, formatter and linter",
          match = { filename = { "own.alpha" } },
          example = "own.alpha",
          servers = { "bserver" },
          formatters = { "ofmt" },
          linters = { olint = {} },
        },
        ["alpha.kept"] = { about = "keeps its base's", match = { pattern = { [".*/kept/.*%.alpha"] = { priority = 1 } } }, example = "kept/x.alpha" },
      },
    },
    beta = {
      filetypes = { "beta", "betax" },
      parsers = { "shared", "beta" },
      servers = { bserver = {} },
      formatters = { "bfmt", filetypes = { "beta" } },
      linters = { blint = {} },
      options = { tabstop = 5 },
      keys = { { "]]", label = "Next beta" }, filetypes = { "beta" } },
    },
  }
end

---@param a lang.Answer?
local function brief(a) return a and { servers = a.servers, formatters = a.formatters, linters = a.linters, tools = a.tools, options = a.options } end

h.case("each filetype gets its language's tools; an item with filetypes of its own applies only there", function()
  local r = lang._from(fixture())
  h.eq(brief(r.of("alpha")), {
    servers = { "aserver", "narrow" },
    formatters = { "afmt1", "afmt2" },
    linters = { "alint" },
    tools = { "aserver", "narrow", "afmt1", "afmt2", "alint" },
    options = { shiftwidth = 3 },
  }, "alpha")
  h.eq(brief(r.of("alphax")), {
    servers = { "aserver" },
    formatters = { "afmt1", "afmt2" },
    linters = { "alint", "zlint" },
    tools = { "aserver", "afmt1", "afmt2", "alint", "zlint" },
    options = { shiftwidth = 3 },
  }, "alphax")
  h.eq(brief(r.of("betax")), { servers = { "bserver" }, formatters = {}, linters = { "blint" }, tools = { "bserver", "blint" }, options = { tabstop = 5 } }, "betax")
  h.eq(r.of("alpha").covered_by, { alint = "aserver" }, "alpha's covering servers")
  h.eq(r.problems, {}, "problems")
end)

h.case("a variant gets its base's servers, linters and options plus its own, and its own formatters if it names any", function()
  local r = lang._from(fixture())
  h.eq(brief(r.of("alpha.own")), {
    servers = { "aserver", "bserver", "narrow" },
    formatters = { "ofmt" },
    linters = { "alint", "olint" },
    tools = { "aserver", "bserver", "narrow", "ofmt", "alint", "olint" },
    options = { shiftwidth = 3 },
  }, "alpha.own")
  h.eq(brief(r.of("alpha.kept")), {
    servers = { "aserver", "narrow" },
    formatters = { "afmt1", "afmt2" },
    linters = { "alint" },
    tools = { "aserver", "narrow", "afmt1", "afmt2", "alint" },
    options = { shiftwidth = 3 },
  }, "alpha.kept")
  h.eq(r.of("alpha.own").base, "alpha", "alpha.own's base")
end)

h.case("an undeclared dotted filetype gets no servers, its last formatted part's formatters, every part's linters and options", function()
  local r = lang._from(fixture())
  h.eq(brief(r.of("alpha.undeclared")), {
    servers = {},
    formatters = { "afmt1", "afmt2" },
    linters = { "alint" },
    tools = { "afmt1", "afmt2", "alint" },
    options = { shiftwidth = 3 },
  }, "alpha.undeclared")
  h.eq(brief(r.of("beta.alpha")), {
    servers = {},
    formatters = { "afmt1", "afmt2" },
    linters = { "blint", "alint" },
    tools = { "afmt1", "afmt2", "blint", "alint" },
    options = { shiftwidth = 3, tabstop = 5 },
  }, "beta.alpha")
  h.eq(brief(r.of("unknown.alpha.betax")), {
    servers = {},
    formatters = { "afmt1", "afmt2" },
    linters = { "alint", "blint" },
    tools = { "afmt1", "afmt2", "alint", "blint" },
    options = { shiftwidth = 3, tabstop = 5 },
  }, "unknown.alpha.betax")
  h.eq({ r.of("gamma"), r.of("gamma.delta") }, {}, "filetypes no language knows")
end)

h.case("the views are what each plugin needs for every declared filetype", function()
  local v = lang._from(fixture()).views()
  local ab = { "afmt1", "afmt2" }
  h.eq(v.conform, { alpha = ab, alphax = ab, ["alpha.own"] = { "ofmt" }, ["alpha.kept"] = ab, beta = { "bfmt" } }, "conform")
  h.eq(v.lint, { alpha = { "alint" }, alphax = { "alint", "zlint" }, ["alpha.own"] = { "alint", "olint" }, ["alpha.kept"] = { "alint" }, beta = { "blint" }, betax = { "blint" } }, "lint")
  h.eq(v.lsp, {
    aserver = { settings = { x = 1 }, filetypes = { "alpha", "alpha.kept", "alpha.own", "alphax" } },
    narrow = { filetypes = { "alpha", "alpha.kept", "alpha.own" } },
    bserver = { filetypes = { "alpha.own", "beta", "betax" } },
  }, "lsp")
  h.eq(v.parsers, { "alpha", "beta", "shared" }, "parsers")
  h.eq(v.covered_by, { alint = "aserver" }, "covered_by")
  local a, b = { { "]]", label = "Next alpha" } }, { { "]]", label = "Next beta" } }
  h.eq(v.keys, { alpha = a, alphax = a, beta = b }, "keys")
  h.eq(v.filetypes, { filename = { ["own.alpha"] = "alpha.own" }, pattern = { [".*/kept/.*%.alpha"] = { "alpha.kept", { priority = 1 } } } }, "filetype rules")
  h.eq(lang._from(fixture()).filetypes(), { "alpha", "alpha.kept", "alpha.own", "alphax", "beta", "betax" }, "filetypes")
end)

h.case("setup gives the variants' files their filetypes, and sets each filetype's options on FileType", function()
  local r = lang._from(fixture())
  r.setup()
  h.eq(vim.filetype.match({ filename = "/p/own.alpha" }), "alpha.own", "own.alpha")
  h.eq(vim.filetype.match({ filename = "/p/kept/x.alpha" }), "alpha.kept", "kept/x.alpha")
  local function opts(ft)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = ft
    local got = { vim.bo[buf].shiftwidth, vim.bo[buf].tabstop }
    vim.api.nvim_buf_delete(buf, { force = true })
    return got
  end
  h.eq(opts("alpha"), { 3, 8 }, "alpha's shiftwidth and tabstop")
  h.eq(opts("alpha.kept"), { 3, 8 }, "alpha.kept's")
  h.eq(opts("beta.alpha"), { 3, 5 }, "beta.alpha's")
  h.eq(opts("gamma"), { 8, 8 }, "an unknown filetype's")
  vim.api.nvim_del_augroup_by_name("lang")
end)

-- Each case: specs with one mistake, what must still hold, and a word every problem message must name
local mistakes = {
  {
    "a filetype two languages declare stays the first's",
    { a = { filetypes = { "x" }, formatters = { "af" } }, b = { filetypes = { "x", "y" }, formatters = { "bf" } } },
    function(r) return vim.deep_equal({ r.of("x").formatters, r.of("x").lang, r.of("y").formatters }, { { "af" }, "a", { "bf" } }) end,
    "x",
  },
  {
    "a server two languages configure keeps the first's config and filetypes",
    { a = { filetypes = { "x" }, servers = { s = { settings = { a = 1 } } } }, b = { filetypes = { "y" }, servers = { s = { settings = { b = 2 } } } } },
    function(r) return vim.deep_equal(r.views().lsp.s, { settings = { a = 1 }, filetypes = { "x" } }) and #r.of("y").servers == 0 end,
    "s",
  },
  {
    "a linter two languages cover with different servers keeps the first's",
    { a = { filetypes = { "x" }, servers = { s1 = {} }, linters = { l = { covered_by = "s1" } } }, b = { filetypes = { "y" }, servers = { s2 = {} }, linters = { l = { covered_by = "s2" } } } },
    function(r) return r.views().covered_by.l == "s1" and r.of("y").covered_by.l == "s1" end,
    "l",
  },
  {
    "a variant without a dot is skipped",
    { a = { filetypes = { "x" }, variants = { nodot = { about = "" } } } },
    function(r) return r.of("nodot") == nil and r.views().variants.nodot == nil end,
    "nodot",
  },
  {
    "a variant two languages declare stays the first's",
    { a = { filetypes = { "x" }, variants = { ["x.v"] = { about = "", formatters = { "af" } } } }, b = { filetypes = { "y" }, variants = { ["x.v"] = { about = "", formatters = { "bf" } } } } },
    function(r) return vim.deep_equal(r.of("x.v").formatters, { "af" }) and r.views().variants["x.v"].lang == "a" end,
    "x.v",
  },
  {
    "a server a variant names that no language configures is skipped",
    { a = { filetypes = { "x" }, servers = { s = {} }, variants = { ["x.v"] = { about = "", servers = { "nope" } } } } },
    function(r) return vim.deep_equal(r.of("x.v").servers, { "s" }) and r.views().lsp.nope == nil end,
    "nope",
  },
  {
    "a file name or pattern two variants claim stays the first's",
    {
      a = { filetypes = { "x" }, variants = { ["x.v1"] = { about = "", match = { filename = { "f" }, pattern = { ["p"] = {} } } } } },
      b = { filetypes = { "y" }, variants = { ["y.v2"] = { about = "", match = { filename = { "f" }, pattern = { ["p"] = {} } } } } },
    },
    function(r) return r.views().filetypes.filename.f == "x.v1" and r.views().filetypes.pattern.p == "x.v1" and r.of("y.v2") ~= nil end,
    "x.v1",
  },
}
for _, m in ipairs(mistakes) do
  h.case(m[1] .. ", and the mistake is reported", function()
    local r = lang._from(m[2])
    h.ok(m[3](r), "the first declaration does not hold: " .. vim.inspect(r.views(), { newline = " ", indent = "" }))
    h.ok(#r.problems > 0, "no problem reported")
    for _, p in ipairs(r.problems) do
      h.ok(p:find(m[4], 1, true), ("%q does not name %s"):format(p, m[4]))
    end
  end)
end

h.case("setup reports the problems once, as an error", function()
  local r = lang._from(mistakes[1][2])
  local got = {}
  local notify = vim.notify
  vim.notify = function(msg, level) got[#got + 1] = { msg, level } end
  r.setup()
  vim.wait(200, function() return #got > 0 end)
  vim.notify = notify
  vim.api.nvim_del_augroup_by_name("lang")
  h.eq(#got, 1, "notifications")
  h.ok(got[1][1]:find(r.problems[1], 1, true) and got[1][2] == vim.log.levels.ERROR, vim.inspect(got))
end)

-- The real language files

local views = lang.views()

h.case("the language files have no problems", function() h.eq(lang.problems(), {}, "problems") end)

h.case("each variant says what it is, and one with match rules has an example path that gets its filetype", function()
  vim.filetype.add(views.filetypes)
  local broken = {}
  for ft, v in pairs(views.variants) do
    local spec = require("lang." .. v.lang).variants[ft]
    if type(spec.about) ~= "string" or spec.about == "" then
      broken[#broken + 1] = ft .. " has no about"
    end
    if spec.match and not spec.example then
      broken[#broken + 1] = ft .. " has match rules and no example"
    end
    local got = spec.example and vim.filetype.match({ filename = "/project/" .. spec.example })
    if spec.example and got ~= ft then
      broken[#broken + 1] = ("%s is %s, not %s"):format(spec.example, tostring(got), ft)
    end
  end
  h.ok(next(views.variants) ~= nil, "no variants")
  h.eq(broken, {}, "variants")
end)

h.case("every name a language uses has a catalog binary, and every catalog binary is used by a language or what it runs", function()
  local used, broken = {}, {}
  for _, ft in ipairs(lang.filetypes()) do
    local a = lang.of(ft)
    for _, role in ipairs({ { "server", a.servers }, { "formatter", a.formatters }, { "linter", a.linters } }) do
      for _, name in ipairs(role[2]) do
        local bin = catalog.binary(role[1], name)
        if bin then
          used[bin] = true
          for _, required in ipairs(catalog.tools[bin].requires or {}) do
            used[required] = true
          end
        else
          broken[#broken + 1] = ("%s %s (%s) has no catalog binary"):format(role[1], name, ft)
        end
      end
    end
  end
  for linter, server in pairs(views.covered_by) do
    if not views.lsp[server] then
      broken[#broken + 1] = ("%s's covering server %s is named by no language"):format(linter, server)
    end
  end
  for bin in pairs(catalog.tools) do
    if not used[bin] then
      broken[#broken + 1] = ("catalog binary %s is used by no language"):format(bin)
    end
  end
  for _, server in ipairs(catalog.servers()) do
    if not views.lsp[server] then
      broken[#broken + 1] = ("catalog server %s is named by no language"):format(server)
    end
  end
  h.ok(next(used) ~= nil, "no language names a tool")
  h.eq(broken, {}, "catalog and languages")
end)

h.finish()
