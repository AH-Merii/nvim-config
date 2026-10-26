-- features/hover_docstring: pyrefly's hover markdown in, the docstring cleaned (docs/hover-docstrings-decisions.md,
-- D166). Each fixture in fixtures/hover_docstring/ is an excerpt of a real pyrefly 1.4.0 hover, byte for byte after
-- its first line (the library, version and corpus lines it came from); the expected output is the rewrite the
-- findings give for that construct (FINDINGS.md §1.x, in the hover-docstrings corpus).
local here = vim.fs.dirname(vim.fs.abspath(debug.getinfo(1, "S").source:sub(2)))
package.path = table.concat({ here .. "/../../nvim/lua/?.lua", here .. "/../../nvim/lua/?/init.lua", here .. "/?.lua", package.path }, ";")

local t = require("helper")
local docstring = require("features.hover_docstring")

local SIG = { "```python", "(class) X: type[X]", "```", "---" }
local FOOTER = "Go to [X](file:///site-packages/x.py#L1,7)"

--- A pyrefly hover around docstring lines, as pyrefly/lib/lsp/wasm/hover.rs builds one
---@param doc string[]
local function hover(doc) return table.concat(vim.list_extend(vim.list_extend(vim.list_slice(SIG), doc), { "", FOOTER }), "\n") end

--- The fixture's docstring lines, its provenance line left out
---@param name string
local function fixture(name)
  local lines = vim.fn.readfile(here .. "/fixtures/hover_docstring/" .. name .. ".md", "b")
  t.ok(#lines > 1 and lines[1]:match("^<!%-%- "), name .. ": no provenance line")
  return vim.list_slice(lines, 2)
end

--- The docstring lines of the cleaned hover, after checking the signature and footer were kept as they are
---@param doc string[]
local function clean(doc)
  local out = vim.split(docstring.clean(hover(doc)), "\n", { plain = true })
  t.eq(vim.list_slice(out, 1, #SIG), SIG, "the signature and its rule")
  t.eq(vim.list_slice(out, #out - 1), { "", FOOTER }, "the footer")
  return vim.list_slice(out, #SIG + 1, #out - 2)
end

local NB = "\194\160"

t.case("§1.4 a Google section is a bold header over a list of `name` (type): entries, wrapped lines under each", function()
  t.eq(clean(fixture("google_args")), {
    "**Args:**",
    "- `tensors` (sequence of Tensors): Non-empty tensors provided must have the same shape,",
    "  except in the cat dimension.",
    "",
    "- `dim` (int, optional): the dimension over which the tensors are concatenated",
    "",
    "**Keyword args:**",
    "- `out` (Tensor, optional): the output tensor.",
  })
end)

t.case("§1.3 a doctest's output goes in its fence, dedented, and the next doctest joins the same fence", function()
  t.eq(clean(fixture("doctest_output")), {
    "**Example:**",
    "",
    "```python",
    ">>> x = torch.randn(2, 3)",
    ">>> x",
    "tensor([[ 0.6580, -1.0969, -0.4614],",
    "        [-0.1034, -0.5790,  0.1497]])",
    ">>> torch.cat((x, x, x), 0)",
    "tensor([[ 0.6580, -1.0969, -0.4614],",
    "        [-0.1034, -0.5790,  0.1497],",
    "        [ 0.6580, -1.0969, -0.4614],",
    "        [-0.1034, -0.5790,  0.1497],",
    "        [ 0.6580, -1.0969, -0.4614],",
    "        [-0.1034, -0.5790,  0.1497]])",
    "```",
  })
end)

t.case("§1.3 a doctest whose last line is blank is followed by prose, which stays outside; output after one goes in", function()
  local out = clean(fixture("doctest_prose_after"))
  t.eq(vim.list_slice(out, 8, 12), { "... )", "", "```", "Filter rows matching a condition:", "" })
  t.eq(vim.list_slice(out, 13, 16), { "```python", '>>> df.filter(pl.col("foo") > 1)', "shape: (3, 3)", "┌─────┬──────┬─────┐" })
  t.eq(out[#out - 1], "└─────┴──────┴─────┘")
  t.eq(out[#out], "```")
end)

t.case("§1.5 a directive with no argument: its fenced prose body becomes a titled callout, set apart from what follows", function()
  t.eq(vim.list_slice(clean(fixture("directive_fenced")), 1, 4), {
    "> [!NOTE] See also",
    "> `torch.stack` concatenates the given sequence along a new dimension.",
    "",
    "**Args:**",
  })
end)

t.case("§1.5 a directive with an argument: its indented body becomes a callout titled from it", function()
  t.eq(clean(fixture("directive_arg")), {
    "> [!NOTE] Changed in 1.24",
    "> The `join_nulls` parameter was renamed `nulls_equal`.",
    "",
    "Parameters",
  })
end)

t.case("§1.5 math becomes a latex fence; §1.15 a reST link becomes a markdown link", function()
  t.eq(vim.list_slice(clean(fixture("rst_link_math")), 1, 7), {
    "This layer implements the operation as described in",
    "the paper [Layer Normalization](https://arxiv.org/abs/1607.06450)",
    "",
    "```latex",
    [[y = \frac{x - \mathrm{E}[x]}{ \sqrt{\mathrm{Var}[x] + \epsilon}} * \gamma + \beta]],
    "```",
    "The mean and standard-deviation are calculated over the last `D` dimensions, where `D`",
  })
end)

t.case("§1.5 a list-table and a note inside a NumPy entry stay in it, and the next entry isn't read into the note", function()
  t.eq(clean(fixture("directive_in_entry")), {
    "**Parameters**",
    "- **validate** : {'m:m', 'm:1', '1:m', '1:1'}",
    "  Checks if join is of specified type.",
    "",
    "  - **m:m**: *(Default)* Many-to-many (default). Does not result in checks.",
    "  - **1:1**: One-to-one. Checks if join keys are unique in both left and right datasets.",
    "  - **1:m**: One-to-many. Checks if join keys are unique in left dataset.",
    "  - **m:1**: Many-to-one. Check if join keys are unique in right dataset.",
    "",
    "  > [!NOTE]",
    "  > This is currently not supported by the streaming engine.",
    "",
    "- **nulls_equal**",
    "  Join on null values. By default null values will never produce matches.",
  })
end)

t.case("§1.5 a method directive shows its signature as code, without :noindex:; a wrapped entry line stays in its entry", function()
  t.eq(clean(fixture("method_directive")), {
    "`to(dtype, non_blocking=False, copy=False, memory_format=torch.preserve_format) -> Tensor`",
    "",
    "**Args:**",
    "- `memory_format` (`torch.memory_format`, optional): the desired memory format of",
    "  returned Tensor. Default: ``torch.preserve_format``.",
  })
end)

t.case("§1.6 an author's fence indented under a section is dedented into a real fence", function()
  t.eq(clean(fixture("indented_fence")), {
    "**Example:**",
    "```python",
    "from typing import Annotated",
    "",
    "from pydantic.types import StringConstraints",
    "",
    "ConstrainedStr = Annotated[str, StringConstraints(min_length=1, max_length=10)]",
    "```",
  })
end)

t.case("§1.7 &nbsp; inside an author's column-0 fence becomes spaces", function()
  local out = clean(fixture("fence_nbsp"))
  t.eq(out[#out - 1], '    return [{"name": "Empanada"}, {"name": "Arepa"}]')
  t.eq(out[#out], "```")
end)

t.case("§1.8 a doctest inside an author's fence loses pyrefly's inner fences, and the author's closer stays a closer", function()
  t.eq(clean(fixture("doctest_in_fence")), {
    "**Example:**",
    "",
    "```python",
    ">>> from huggingface_hub import HfApi",
    "",
    ">>> api = HfApi()",
    "",
    "# List all models",
    "# List models with 6B to 128B parameters",
    '>>> api.list_models(num_parameters="min:6B,max:128B", sort="likes")',
    "```",
  })
end)

t.case("§1.9 a NumPy section loses its underline (no ─ rule) and its parameters become `- **name**` entries", function()
  t.eq(clean(fixture("numpy")), {
    "**Parameters**",
    "- **predicates**",
    "  Expression(s) that evaluate to a boolean Series.",
    "- **constraints**",
    "  Column filters; use `name = value` to filter columns by the supplied value.",
    "  Each constraint will behave the same as `pl.col(name).eq(value)`, and",
    "  be implicitly joined with the other filter conditions using `&`.",
    "",
    "**Notes**",
  })
end)

t.case("§1.10 brackets that are no link are escaped; doc-builder refs and reference links are kept", function()
  t.eq(clean(fixture("brackets")), {
    "**Args:**",
    "- `round_trip`: If True, dumped values should be valid as input for non-idempotent types such as Json\\[T\\].",
    '- `warnings`: How to handle serialization errors. False/"none" ignores them, True/"warn" logs errors,',
    '  "error" raises a [`PydanticSerializationError`][pydantic_core.PydanticSerializationError].',
  })
end)

t.case("§1.11 a GitHub callout whose > pyrefly dropped is quoted again, to the next blank line", function()
  t.eq(clean(fixture("gh_callout")), {
    "> [!WARNING]",
    "> The input list of `CommitOperation` will be mutated during the commit process. Do not reuse the same objects",
    "> for multiple commits.",
    "",
    "> [!WARNING]",
  })
end)

t.case("§1.12 <Tip> becomes a TIP callout inside the entry it belongs to, </Tip> dropped", function()
  local out = clean(fixture("tip"))
  t.eq(vim.list_slice(out, 4, 9), {
    "",
    "  > [!TIP]",
    "  > [`Trainer`] is optimized to work with the [`PreTrainedModel`] provided by the library. You can still use",
    "  > your own models defined as `torch.nn.Module` as long as they work the same way as the 🤗 Transformers",
    "  > models.",
    "",
  })
  t.eq(out[10], "- `args` ([`TrainingArguments`], *optional*):")
end)

t.case("§1.13 an MkDocs admonition becomes a callout with its title, its body quoted", function()
  t.eq(clean(fixture("admonition")), {
    "> [!ABSTRACT] Usage Documentation",
    "> [String types](./standard_library_types.md#strings)",
    "",
    "A field metadata class to apply constraints to `str` types.",
  })
end)

t.case("§1.14 a __dunder__ in prose goes in a code span; one already in a code span stays", function()
  t.eq(vim.list_slice(clean(fixture("dunder")), 2, 4), {
    "- `__class_vars__`: The names of the class variables defined on the model.",
    "- `__private_attributes__`: Metadata about the private attributes of the model.",
    "- `__signature__`: The synthesized `__init__` [`Signature`][inspect.Signature] of the model.",
  })
  t.eq(clean({ "The __init__ method, see [x](file:///a/__init__.pyi)." }), { "The `__init__` method, see [x](file:///a/__init__.pyi)." })
end)

t.case("§1.1 indent no rule places keeps its width as U+00A0, never as spaces", function()
  t.eq(clean({ "Some prose.", "", "&nbsp;&nbsp;&nbsp;&nbsp;indented    four" }), { "Some prose.", "", NB:rep(4) .. "indented    four" })
end)

t.case("§2 links, ``literals``, doc-builder refs, *optional* and column-0 lists are left as they are", function()
  local doc = fixture("leave_alone")
  local want = vim.tbl_map(function(l) return (l:gsub("  $", "")) end, doc)
  t.eq(clean(doc), want)
end)

t.case("R5 a fence that never closes leaves the whole hover as it came; closed, the same hover is cleaned", function()
  local doc = { "Args:  ", "&nbsp;&nbsp;&nbsp;&nbsp;x: the x.  ", "  ", "```python  ", "print(1)  " }
  t.eq(docstring.clean(hover(doc)), hover(doc))
  table.insert(doc, "```")
  t.ok(docstring.clean(hover(doc)) ~= hover(doc), "the closed version was not cleaned")
end)

t.case("a hover with no docstring, or not shaped as pyrefly's, comes back as it was; with a docstring it changes", function()
  local bare = table.concat({ "```python", "(function) f: def f() -> None: ...", "```", "", FOOTER }, "\n")
  t.eq(docstring.clean(bare), bare)
  local other = "Some **markdown** from another server\n&nbsp;&nbsp;indented"
  t.eq(docstring.clean(other), other)
  local with = table.concat({ "```python", "(function) f: def f() -> None: ...", "```", "---", "Args:  ", "&nbsp;&nbsp;x: y", "", FOOTER }, "\n")
  t.ok(docstring.clean(with) ~= with, "a docstring was not cleaned")
end)

-- The whole corpus, when it is on this machine (it isn't in CI): every hover comes out as markdown that holds
local CORPUS = vim.fs.normalize("~/.cache/nvim-config/hover-docstrings/corpus")

--- Lines inside fenced code blocks, by treesitter's markdown parser (row, 0-based -> true), and how many of those
--- blocks have no closing fence
local function code_rows(text)
  -- ended as a buffer's last line is: without the newline the parser doesn't read a closing fence on the last line
  text = text .. "\n"
  local parser = vim.treesitter.get_string_parser(text, "markdown")
  local root = parser:parse()[1]:root()
  local rows, open = {}, 0
  local query = vim.treesitter.query.parse("markdown", "(fenced_code_block) @c")
  for _, node in query:iter_captures(root, text) do
    local sr, _, er = node:range()
    for r = sr, er do
      rows[r] = true
    end
    local delimiters = 0
    for child in node:iter_children() do
      delimiters = delimiters + (child:type() == "fenced_code_block_delimiter" and 1 or 0)
    end
    open = open + (delimiters < 2 and 1 or 0)
  end
  return rows, root, open
end

--- Lines Neovim would draw as a rule: three or more of one of - * _ and nothing else but spaces
local function rule(l)
  local s = l:gsub("%s", "")
  return #s >= 3 and (s:match("^%-+$") or s:match("^%*+$") or s:match("^_+$")) ~= nil
end

t.case("every corpus hover: balanced fences, parses, no &nbsp; outside code, footer outside code, no new rules", function()
  if not vim.uv.fs_stat(CORPUS) then
    print("SKIP the corpus property check: no corpus at " .. CORPUS)
    return
  end
  local files = vim.fn.glob(CORPUS .. "/*__*.md", false, true)
  t.ok(#files >= 60, "corpus has " .. #files .. " hovers")
  local changed, problems = 0, {}
  for _, f in ipairs(files) do
    local input = table.concat(vim.fn.readfile(f, "b"), "\n")
    local out = docstring.clean(input)
    changed = changed + (out ~= input and 1 or 0)
    local lines = vim.split(out, "\n", { plain = true })
    local rows, root, open = code_rows(out)
    local name = vim.fs.basename(f)
    local function bad(what) table.insert(problems, name .. ": " .. what) end
    if open > 0 then
      bad(open .. " fences never close")
    end
    if root:has_error() then
      bad("treesitter markdown has an error")
    end
    local rules_in = vim.iter(vim.split(input, "\n", { plain = true })):filter(rule):totable()
    local rules_out = vim.iter(lines):filter(rule):totable()
    if #rules_out > #rules_in then
      bad(("%d rules, %d in the input"):format(#rules_out, #rules_in))
    end
    for r, l in ipairs(lines) do
      if not rows[r - 1] and l:match("^[%s>]*&nbsp;") then
        bad("&nbsp; outside code at line " .. r)
        break
      end
    end
    if lines[#lines]:match("^Go to %[") and rows[#lines - 1] then
      bad("the Go to footer is inside a fence")
    end
  end
  t.eq(problems, {}, "corpus hovers")
  -- 50 of the 68 carry a docstring (FINDINGS.md); one, a single line of prose, needs nothing
  t.ok(changed >= 45, ("only %d of %d corpus hovers changed"):format(changed, #files))
end)

t.finish()
