-- @desc     a buffer that is not a file (a 'buftype' or a scheme:// name, e.g. :checkhealth's health://) takes its tools root from the cwd, never from its name, while a file takes its project root or its own dir
-- @areas    tools
-- @budget   15
-- @fixture  projects
local tools = require("tools")

-- The fixture's top dir has no project marker, so the cwd is the root a non-file buffer must get
local cwd = vim.fs.normalize(FIX)
check("the fixture's top dir is outside any project", tools.project_root(0) == nil, tostring(tools.project_root(0)))

local function root_of(name, buftype)
  local buf = vim.api.nvim_create_buf(true, false)
  if buftype then vim.bo[buf].buftype = buftype end
  vim.api.nvim_buf_set_name(buf, name)
  local root = tools.root(buf)
  vim.api.nvim_buf_delete(buf, { force = true })
  return root
end

local cases = {
  { "health://", "nofile", cwd, "a :checkhealth buffer" },
  { "noproj/scratch", "nofile", cwd, "a nofile buffer named like a path" },
  { "noproj/app.py", "nowrite", cwd, "a nowrite buffer named like a file" },
  { "oil://" .. FIX .. "/noproj/", nil, cwd, "a scheme:// buffer with no buftype" },
  { "fugitive://" .. FIX .. "/.git//0/noproj/app.py", nil, cwd, "a scheme:// buffer named after a file" },
  { "noproj/app.py", nil, cwd .. "/noproj", "a file outside any project" },
  { "withproj/app.py", nil, cwd .. "/withproj", "a file in a project" },
}
for _, c in ipairs(cases) do
  local root = root_of(c[1], c[2])
  check(("%s (%s, buftype %q) has root %s"):format(c[4], c[1], c[2] or "", c[3]), root == c[3], tostring(root))
  check(c[4] .. "'s root is a directory", vim.fn.isdirectory(root) == 1, tostring(root))
end

-- With the cwd in a project, a buffer that isn't a file takes that project's root
vim.cmd.cd("withproj")
for _, c in ipairs({ { "health://", "nofile" }, { "oil://" .. FIX .. "/noproj/", nil } }) do
  local root = root_of(c[1], c[2])
  check(c[1] .. " with the cwd in withproj has root " .. cwd .. "/withproj", root == cwd .. "/withproj", tostring(root))
end
vim.cmd.cd(FIX)

-- The real :checkhealth buffer, as conform's health check sees it
vim.cmd("checkhealth vim.health")
local hbuf = vim.api.nvim_get_current_buf()
check(":checkhealth opened a health buffer", vim.api.nvim_buf_get_name(hbuf):match("^health://") ~= nil, vim.api.nvim_buf_get_name(hbuf))
check(":checkhealth's buffer has the cwd as its tools root", tools.root(hbuf) == cwd, tools.root(hbuf))
