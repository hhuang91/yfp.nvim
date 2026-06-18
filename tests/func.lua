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

-- 3) pinned pane: pin -> toggle the bottom float -> jump -> remove -> persist
local exp = require("yfp.explorer")
local pins = require("yfp.pins")
local sub = tmp .. "/sub"
vim.fn.mkdir(sub, "p")
local pinfile = tmp .. "-pins.json"
yfp.setup({ yank = { registers = {} }, pins = { file = pinfile } })
pins.reset()

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
yfp.open({ cwd = tmp })
-- entries sort dirs-first: row 2 = "sub/", row 3 = "alpha.txt"
vim.api.nvim_win_set_cursor(exp.state.win, { 2, 0 })
actions.pin_add()
assert(#pins.list() == 1, "pin_add must add one pin")
assert(pins.list()[1].path == sub, "must pin the subdir path")

exp.toggle_pins()
assert(exp.state.pin_win and vim.api.nvim_win_is_valid(exp.state.pin_win), "pinned pane must open")
local pline = vim.api.nvim_buf_get_lines(exp.state.pin_buf, 0, 1, false)[1]
assert(not pline:find("\\", 1, true), "pane path must not contain backslashes")

vim.api.nvim_win_set_cursor(exp.state.pin_win, { 1, 0 })
actions.pin_jump()
assert(exp.state.cwd == sub, "pin_jump must navigate the main view into the pin")
assert(vim.api.nvim_get_current_win() == exp.state.win, "focus must return to the main float")

vim.api.nvim_set_current_win(exp.state.pin_win)
vim.api.nvim_win_set_cursor(exp.state.pin_win, { 1, 0 })
actions.pin_remove()
assert(#pins.list() == 0, "pin_remove must empty the list")

yfp.close()
assert(not yfp.is_open(), "the whole UI must close cleanly")
pins.reset()
assert(#pins.list() == 0, "removal must persist across a reload")
pcall(vim.fn.delete, pinfile)
yfp.setup({})
print("yfp: pinned-pane add/toggle/jump/remove + persistence tests passed")

print("yfp: functional yank_and_paste + registers-only tests passed")
