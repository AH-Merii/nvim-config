-- @desc     report only: lists each built-in key (an index.txt command or text object, a --clean default map) that a global or buffer map of ours hides in n, x and o, with NEW and GONE against the version's previous list; red only when the detector, the index.txt parse or the --clean read breaks
-- @areas    keys treesitter lsp git
-- @budget   60
-- @version-sensitive
-- @args     app.py
-- The list and its previous run live in $S/state/<version>/keymap_clashes.txt. Which clashes exist is config: never asserted.

local MODES = { "n", "x", "o" }
local function flush()
  for _ = 1, 2 do
    local ran = false
    vim.schedule(function() ran = true end)
    wait_until(function() return ran end, 1000)
  end
end
local function rawkey(m) return m.lhsraw or vim.keycode(m.lhs) end

-- ---- index.txt -------------------------------------------------------------------------------------
-- section -> modes its table applies to; a normal-mode motion (note 1) also applies in x and o
local SECTIONS = {
  ["2"] = { "n" }, ["2.1"] = { "x", "o" }, ["2.3"] = { "n" }, ["2.4"] = { "n" }, ["2.5"] = { "n" }, ["2.6"] = { "o" }, ["3"] = { "x" },
}
local MOTION_SECTIONS = { ["2"] = true, ["2.3"] = true, ["2.4"] = true, ["2.5"] = true }

-- "g CTRL-A" -> "g<C-A>", "["x]d{motion}" -> "d", "m{A-Za-z}" -> "m" plus the placeholder
local function notation(chars)
  local s = chars:gsub('^"(.+)"$', "%1"):gsub('^%["x%]', ""):gsub("^%[count%]", ""):gsub("^{count}", "")
  local prefix, ph = s:match("^(.-)({[^}]*})")
  if prefix then s = prefix end
  local out = {}
  for tok in s:gmatch("%S+") do
    out[#out + 1] = tok:gsub("^CTRL%-(.+)$", function(k) return "<C-" .. (k:match("^<(.*)>$") or k) .. ">" end)
  end
  return table.concat(out), ph
end

local function parse_index(path)
  local rows, sec, after_rule, in_table, last = {}, nil, false, false, nil
  for line in io.lines(path) do
    if line:match("^=+$") then
      sec, after_rule, in_table, last = nil, true, false, nil
    elseif after_rule then
      after_rule = false
      sec = line:match("^(%d+)%.%s") or line:match("^(%d+%.%d+)%s")
    elseif sec and SECTIONS[sec] and line:match("^%-%-%-%-+ ~$") then
      in_table = true
    elseif in_table then
      local tag, rest = line:match("^|([^|]+)|%s*(.*)$")
      if not tag then tag, rest = line:match("^%*([^*]+)%*%s*(.*)$") end
      if not tag and line:match("^\t\t[^\t]") then tag, rest = "", line:sub(3) end
      if tag then
        local chars, tail = rest:match("^([^\t]+)\t+(.*)$")
        chars, tail = chars or rest, tail or ""
        local note, desc = tail:match("^%s*([12])%s%s+(.*)$")
        last = { tag = tag, chars = vim.trim(chars), note = note, desc = vim.trim(desc or tail), sec = sec }
        rows[#rows + 1] = last
      elseif last and line:match("^\t\t\t") then
        local note, desc = line:match("^%s*([12])%s%s+(.*)$")
        if note and not last.note and last.desc == "" then last.note = note end
        last.desc = vim.trim(last.desc .. " " .. vim.trim(desc or line))
      else
        last = nil
      end
    end
  end
  local native, per_sec = { n = {}, x = {}, o = {} }, {}
  for _, r in ipairs(rows) do
    local unused = r.desc:match("^not used") or r.desc:match("^reserved")
    local key, ph = notation(r.chars)
    if not unused and key ~= "" then
      per_sec[r.sec] = (per_sec[r.sec] or 0) + 1
      -- a char, mark or register argument: a map on the key plus one char hides that use (ma, 'a, @q)
      local arg = ph ~= nil and (ph == "{char}" or ph == "{mark}" or ph == "{register}" or ph:find("%w%-%w") ~= nil)
        and not r.desc:find("see |", 1, true)
      local modes = vim.list_extend({}, SECTIONS[r.sec])
      if MOTION_SECTIONS[r.sec] and r.note == "1" then vim.list_extend(modes, { "x", "o" }) end
      local raw = vim.keycode(key)
      for _, m in ipairs(modes) do
        native[m][raw] = native[m][raw] or { key = key, desc = r.desc, arg = arg }
      end
    end
  end
  return native, per_sec
end

local INDEX = vim.env.VIMRUNTIME .. "/doc/index.txt"
local native, per_sec = parse_index(INDEX)
local SEC_MIN = { ["2"] = 100, ["2.1"] = 20, ["2.3"] = 25, ["2.4"] = 30, ["2.5"] = 25, ["2.6"] = 1, ["3"] = 40 }
for s, min in vim.spairs(SEC_MIN) do
  check(("index.txt: section %s has at least %d commands"):format(s, min), (per_sec[s] or 0) >= min, per_sec[s] or 0)
end
local MODE_MIN = { n = 250, x = 120, o = 80 }
for _, m in ipairs(MODES) do
  check(("index.txt: %s mode has at least %d built-in keys"):format(m, MODE_MIN[m]), vim.tbl_count(native[m]) >= MODE_MIN[m], vim.tbl_count(native[m]))
end
-- key notation and mode spread: present since Vim 7
local KNOWN = { n = { "w", "gg", "zz", "<C-A>", "[<C-D>", "g<C-G>", "<C-W>", "'" }, x = { "iw", "w", "<C-\\><C-N>", "o" }, o = { "iw", "w", "v", "<C-V>" } }
local absent = {}
for m, keys in pairs(KNOWN) do
  for _, k in ipairs(keys) do
    if not native[m][vim.keycode(k)] then absent[#absent + 1] = m .. " " .. k end
  end
end
table.sort(absent)
check("index.txt: long-standing keys parse into their modes", #absent == 0, #absent > 0 and ("missing: " .. table.concat(absent, ", ")) or nil)

-- ---- fixtures ------------------------------------------------------------------------------------
vim.fn.writefile({ "Plain prose for the text filetype.", "", "A second paragraph." }, FIX .. "/notes.txt")
local FILES = { "app.py", "main.lua", "notes.md", "main.go", "notes.txt", "script.sh" }

-- ---- --clean: the same nvim's defaults, and the runtime's own buffer maps for the same files -------
local CLEAN_DUMP = [[
local out = vim.env.NVR_KC_OUT
local ok, err = pcall(function()
  local function dump(buf)
    local r = {}
    for _, m in ipairs({ "n", "x", "o" }) do
      r[m] = {}
      for _, k in ipairs(buf and vim.api.nvim_buf_get_keymap(buf, m) or vim.api.nvim_get_keymap(m)) do
        k.callback = k.callback ~= nil or nil
        table.insert(r[m], k)
      end
    end
    return r
  end
  local res = { global = dump(), buffers = {}, version = tostring(vim.version()) }
  for _, f in ipairs(vim.split(vim.env.NVR_KC_FILES, "\n")) do
    vim.cmd.edit(vim.fn.fnameescape(f))
    res.buffers[f] = dump(vim.api.nvim_get_current_buf())
  end
  local fh = assert(io.open(out, "wb"))
  fh:write(vim.mpack.encode(res))
  fh:close()
end)
if not ok then io.stderr:write("dump failed: " .. tostring(err) .. "\n") end
vim.cmd("qa!")
]]
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")
vim.fn.writefile(vim.split(CLEAN_DUMP, "\n"), tmp .. "/dump.lua")
local res = vim.system({ vim.v.progpath, "--clean", "--headless", "-n", "-c", "luafile " .. tmp .. "/dump.lua" }, {
  cwd = FIX,
  timeout = 20000,
  env = {
    NVR_KC_OUT = tmp .. "/clean.mpack",
    NVR_KC_FILES = table.concat(FILES, "\n"),
    XDG_CONFIG_HOME = tmp, XDG_DATA_HOME = tmp, XDG_STATE_HOME = tmp, XDG_CACHE_HOME = tmp,
  },
}):wait()
local fh = io.open(tmp .. "/clean.mpack", "rb")
local clean = fh and vim.mpack.decode(fh:read("*a"))
if fh then fh:close() end
local clean_ok = clean ~= nil and clean.version == tostring(vim.version())
  and vim.iter(MODES):all(function(m) return #clean.global[m] > 0 end)
if not check("--clean nvim of this version dumped its default maps in n, x and o", clean_ok,
  clean and ("version " .. tostring(clean.version)) or ("exit " .. res.code .. " " .. (res.stderr or ""):sub(1, 200))) then
  return
end

local function sig(m)
  return table.concat({ rawkey(m), (m.rhs or ""):gsub("<SNR>%d+_", "<SNR>_"), m.desc or "", tostring(m.expr), tostring(m.noremap), tostring(m.callback ~= nil) }, "\31")
end
local function sigset(...)
  local s = { n = {}, x = {}, o = {} }
  for _, dump in ipairs({ ... }) do
    for _, m in ipairs(MODES) do
      for _, k in ipairs(dump[m] or {}) do s[m][sig(k)] = true end
    end
  end
  return s
end
local clean_global = sigset(clean.global)
local defaults = { n = {}, x = {}, o = {} } -- mode -> raw lhs -> default map
for _, m in ipairs(MODES) do
  for _, k in ipairs(clean.global[m]) do
    for _, r in ipairs({ k.lhsraw, k.lhsrawalt }) do defaults[m][r] = defaults[m][r] or k end
  end
end

-- ---- the detector --------------------------------------------------------------------------------
-- a map of ours: not a which-key trigger, not <Plug>/<SNR>, and not identical to a map the --clean nvim has
local function ours_of(m, maps, runtime)
  local out = {}
  for _, k in ipairs(maps) do
    if k.desc ~= "which-key-trigger" and not k.lhs:match("^<Plug>") and not k.lhs:match("^<SNR>") and not runtime[m][sig(k)] then
      out[#out + 1] = k
    end
  end
  return out
end

-- built-ins that map k hides in mode m: the --clean default with its lhs, else index.txt commands it equals,
-- prefixes, or gives a char/mark/register argument to
local function hidden_by(m, k)
  local hits = {}
  for _, r in ipairs({ k.lhsraw or vim.keycode(k.lhs), k.lhsrawalt }) do
    local d = defaults[m][r]
    if d then return { { src = "default", key = d.lhs, desc = d.desc or d.rhs or "" } } end
  end
  local raw = rawkey(k)
  local prefixed = {}
  for nraw, e in pairs(native[m]) do
    if nraw == raw then
      hits[#hits + 1] = { src = "index", key = e.key, desc = e.desc }
    elseif #nraw > #raw and nraw:sub(1, #raw) == raw then
      prefixed[#prefixed + 1] = e.key
    elseif e.arg and #raw > #nraw and raw:sub(1, #nraw) == nraw then
      hits[#hits + 1] = { src = "index", key = e.key .. "{arg}", desc = e.desc }
    end
  end
  if #prefixed > 0 then
    table.sort(prefixed)
    hits[#hits + 1] = { src = "index", key = k.lhs .. "*", desc = #prefixed .. " commands it prefixes: " .. table.concat(prefixed, " ") }
  end
  return hits
end

local function our_label(k)
  if k.desc and k.desc ~= "" then return k.desc end
  if k.rhs and k.rhs ~= "" then return "rhs " .. k.rhs end
  if k.sid and k.sid > 0 then
    local info_ = vim.fn.getscriptinfo({ sid = k.sid })[1]
    if info_ then return "from " .. vim.fn.fnamemodify(info_.name, ":~") end
  end
  return "Lua callback"
end

-- clashes[id] = { mode, lhs, ours, where = set, src, key, desc }
local function detect(clashes, where, m, maps, runtime)
  for _, k in ipairs(ours_of(m, maps, runtime)) do
    for _, h in ipairs(hidden_by(m, k)) do
      local id = ("%s %s %s:%s"):format(m, k.lhs, h.src, h.key)
      local c = clashes[id] or { mode = m, lhs = k.lhs, ours = our_label(k), where = {}, src = h.src, key = h.key, desc = h.desc }
      c.where[where] = true
      clashes[id] = c
    end
  end
end

-- ---- our maps: global after startup, buffer-local in each fixture once its servers and gitsigns attached -
local bufs = {}
for _, f in ipairs(FILES) do
  vim.cmd.edit(vim.fn.fnameescape(f))
  bufs[f] = vim.api.nvim_get_current_buf()
end
for _, f in ipairs(FILES) do
  local want = lsp_expected(bufs[f])
  local missing = wait_attach(bufs[f], want, 15000)
  if #missing > 0 then info(("%s: servers not attached, their maps are absent: %s"):format(f, table.concat(missing, ", "))) end
end
if not wait_until(function()
  return vim.iter(FILES):all(function(f) return vim.b[bufs[f]].gitsigns_status_dict ~= nil end)
end, 5000) then
  info("gitsigns did not attach to every fixture; its maps may be absent")
end
flush()

local clashes, n_ours = {}, { n = 0, x = 0, o = 0 }
for _, m in ipairs(MODES) do
  local g = vim.api.nvim_get_keymap(m)
  n_ours[m] = n_ours[m] + #ours_of(m, g, clean_global)
  detect(clashes, "global", m, g, clean_global)
end
for _, f in ipairs(FILES) do
  local b = bufs[f]
  local runtime = sigset(clean.buffers[f] or {}, clean.global)
  for _, m in ipairs(MODES) do
    local bm = vim.api.nvim_buf_get_keymap(b, m)
    n_ours[m] = n_ours[m] + #ours_of(m, bm, runtime)
    detect(clashes, vim.bo[b].filetype, m, bm, runtime)
  end
end
check("found maps of ours in n, x and o", n_ours.n > 0 and n_ours.x > 0 and n_ours.o > 0, vim.inspect(n_ours, { newline = "" }))

-- ---- the detector on known keys, in a scratch buffer --------------------------------------------------
vim.cmd.enew()
local scratch = vim.api.nvim_get_current_buf()
vim.bo[scratch].buftype = "nofile"
local PROBE = "nvr keymap_clashes probe"
vim.keymap.set("o", "ip", "<Nop>", { buf = scratch, desc = PROBE .. " native" })
vim.keymap.set("o", "<F35>", "<Nop>", { buf = scratch, desc = PROBE .. " unused" })
local probe = {}
detect(probe, "scratch", "o", vim.api.nvim_buf_get_keymap(scratch, "o"), sigset({}))
local native_hit, unused_hit = false, false
for _, c in pairs(probe) do
  if c.ours == PROBE .. " native" and c.lhs == "ip" and c.src == "index" and c.key == "ip" then native_hit = true end
  if c.ours == PROBE .. " unused" then unused_hit = true end
end
check("detector: a map of ours on the native o-mode ip is reported", native_hit)
check("detector: a map of ours on an unused key is not", not unused_hit)
vim.keymap.del("o", "ip", { buf = scratch })
vim.keymap.del("o", "<F35>", { buf = scratch })
check("detector: the probe maps are gone", vim.fn.maparg("ip", "o", false, true).desc ~= PROBE .. " native" and vim.fn.maparg("<F35>", "o") == "")
vim.cmd("bwipeout! " .. scratch)

-- ---- report and diff against the previous run ------------------------------------------------------
local ORDER = { n = 1, x = 2, o = 3 }
local ids = vim.tbl_keys(clashes)
table.sort(ids, function(a, b)
  local ca, cb = clashes[a], clashes[b]
  if ca.mode ~= cb.mode then return ORDER[ca.mode] < ORDER[cb.mode] end
  return a < b
end)
local function line(id)
  local c = clashes[id]
  local where = vim.tbl_keys(c.where)
  table.sort(where)
  return ("%s  %-8s ours: %s [%s]  hides %s %s: %s"):format(c.mode, c.lhs, c.ours, table.concat(where, " "),
    c.src == "default" and "default map" or "index.txt", c.key, c.desc)
end

local STATE = (vim.env.S or vim.fn.fnamemodify(vim.env.CHECK, ":h:h:h")) .. "/state/" .. VERSION
local FILE = STATE .. "/keymap_clashes.txt"
local prev, had_prev = {}, vim.uv.fs_stat(FILE) ~= nil
if had_prev then
  for l in io.lines(FILE) do
    local id, text = l:match("^([^#][^\t]*)\t(.*)$")
    if id then prev[id] = text end
  end
end
local new, gone, per_mode = {}, {}, { n = 0, x = 0, o = 0 }
for _, id in ipairs(ids) do
  per_mode[clashes[id].mode] = per_mode[clashes[id].mode] + 1
  if had_prev and not prev[id] then new[#new + 1] = line(id) end
end
for id, text in vim.spairs(prev) do
  if not clashes[id] then gone[#gone + 1] = text end
end

local out = {
  ("# keymap clashes, nvim %s, %s"):format(tostring(vim.version()), os.date("%Y-%m-%d %H:%M")),
  "# config " .. tostring(vim.env.CFG),
  ("# %d clashes: n %d, x %d, o %d"):format(#ids, per_mode.n, per_mode.x, per_mode.o),
}
for _, id in ipairs(ids) do out[#out + 1] = id .. "\t" .. line(id) end
vim.fn.mkdir(STATE, "p")
local wrote = vim.fn.writefile(out, FILE .. ".tmp") == 0 and os.rename(FILE .. ".tmp", FILE)
check("clash list written to the state dir", wrote == true, FILE)

info(("==== keymap clashes on %s: %d (n %d, x %d, o %d); %s; list in %s"):format(VERSION, #ids, per_mode.n, per_mode.x, per_mode.o,
  had_prev and (#new .. " NEW, " .. #gone .. " GONE") or "first run, no previous list", FILE))
for _, l in ipairs(new) do info("NEW  " .. l) end
for _, l in ipairs(gone) do info("GONE " .. l) end
for _, id in ipairs(ids) do info("clash " .. line(id)) end
