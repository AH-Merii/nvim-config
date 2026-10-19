-- A fake parser backend (parsers.Backend) for unit tests: what nvim-treesitter has and what Neovim loads without it
-- come from a table, and an install only records the call and marks the languages installed. It supports only what the unit
-- tests use.
--
--   local backend = fake({
--     available = { "python", "regex" },               -- parsers nvim-treesitter can install
--     loadable = { "lua", "vimdoc" },                  -- parsers Neovim loads before any install (its own)
--     installed = { "python" },                        -- parsers it installed before
--     injections = { python = '(#set! injection.language "regex")' }, -- each language's injections query
--     fail = { toml = true },                          -- installs that fail
--   })
--   parsers.setup({ backend = backend })
--   backend.calls                                      -- { { "python", "regex" }, ... }, one list per install
--   backend.hold = true                                -- installs wait until backend.land() is called

---@param opts { available?: string[], loadable?: string[], installed?: string[], injections?: table<string, string>, fail?: table<string, true> }
return function(opts)
  local installed = {} ---@type table<string, true>
  for _, lang in ipairs(opts.installed or {}) do
    installed[lang] = true
  end
  local held = {} ---@type fun()[]
  local B = { calls = {}, hold = false } ---@type parsers.Backend|{ calls: string[][], hold: boolean, land: fun() }

  function B.available(lang) return vim.list_contains(opts.available or {}, lang) end
  function B.installed(lang) return installed[lang] == true end
  function B.loadable(lang) return installed[lang] == true or vim.list_contains(opts.loadable or {}, lang) end
  function B.injections(lang) return (opts.injections or {})[lang] end

  function B.install(langs, _, cb)
    table.insert(B.calls, vim.deepcopy(langs))
    local function finish()
      local failed = {}
      for _, lang in ipairs(langs) do
        if (opts.fail or {})[lang] then
          table.insert(failed, lang)
        else
          installed[lang] = true
        end
      end
      cb(failed)
    end
    if B.hold then
      table.insert(held, finish)
    else
      vim.schedule(finish)
    end
  end

  function B.update(langs, cb)
    table.insert(B.calls, vim.list_extend({ "update" }, langs))
    vim.schedule(function() cb({}) end)
  end

  --- Finishes the installs held so far.
  function B.land()
    local now = held
    held = {}
    for _, finish in ipairs(now) do
      finish()
    end
  end

  return B
end
