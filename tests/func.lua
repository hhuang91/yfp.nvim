-- Functional open -> yank test (headless). Run from the repo root:
--   nvim --headless -l tests/func.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local yfp = require("yfp")
yfp.setup({ yank = { registers = {} } }) -- don't clobber the system clipboard in tests

-- a self-contained sandbox dir with a single known file
local tmp = (vim.fn.tempname():gsub("\\", "/"))
vim.fn.mkdir(tmp, "p")
vim.fn.writefile({ "x" }, tmp .. "/alpha.txt")
local expected = tmp .. "/alpha.txt"

-- empty origin buffer, cursor at the very start
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })

yfp.open({ cwd = tmp })
assert(yfp.is_open(), "float should be open")

require("yfp.actions").yank("absolute") -- yanks the first entry (alpha.txt)
assert(not yfp.is_open(), "float should be closed after yank")

local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
print("RESULT_LINE=" .. tostring(line))
print("EXPECTED  =" .. expected)
assert(not line:find("\\", 1, true), "inserted path must not contain backslashes")
assert(line == expected, "inserted path must equal the forward-slash absolute path")
print("yfp: functional open/yank test passed")
