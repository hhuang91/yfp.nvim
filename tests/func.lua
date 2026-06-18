-- Functional tests (headless). Run from the repo root:
--   nvim --headless -l tests/func.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local yfp = require("yfp")
local actions = require("yfp.actions")

-- a self-contained sandbox dir with a single known file
local tmp = (vim.fn.tempname():gsub("\\", "/"))
vim.fn.mkdir(tmp, "p")
vim.fn.writefile({ "x" }, tmp .. "/alpha.txt")
local expected = tmp .. "/alpha.txt"

-- 1) yank_and_paste inserts the forward-slash path at the cursor
yfp.setup({ yank = { registers = {} } }) -- don't clobber the clipboard in tests
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
yfp.open({ cwd = tmp })
assert(yfp.is_open(), "float should be open")
actions.yank_and_paste("absolute") -- first entry = alpha.txt
assert(not yfp.is_open(), "float should be closed after the action")
local line = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
print("PASTE    = " .. tostring(line))
assert(not line:find("\\", 1, true), "pasted path must not contain backslashes")
assert(line == expected, "pasted path must equal the forward-slash absolute path")

-- 2) registers-only yank sets the register and does NOT modify the buffer
yfp.setup({ yank = { registers = { '"' } } })
vim.fn.setreg('"', "")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
yfp.open({ cwd = tmp })
actions.yank("absolute")
local after = vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]
print("REGISTER = " .. tostring(vim.fn.getreg('"')))
assert(after == "", "registers-only yank must not modify the buffer")
assert(vim.fn.getreg('"') == expected, "registers-only yank must set the register")

print("yfp: functional yank_and_paste + registers-only tests passed")
