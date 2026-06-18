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
local function pane_open()
  return exp.state.pin_win and vim.api.nvim_win_is_valid(exp.state.pin_win)
end

-- P toggles the panel open; focus stays in the main view
exp.toggle_pins()
assert(pane_open(), "pinned panel must open")
assert(vim.api.nvim_get_current_win() == exp.state.win, "opening keeps focus in main")

-- a pins the selection (entries sort dirs-first: row 2 = "sub/", row 3 = "alpha.txt")
vim.api.nvim_win_set_cursor(exp.state.win, { 2, 0 })
actions.pin_add()
assert(#pins.list() == 1, "pin_add must add one pin while the panel is open")
assert(pins.list()[1].path == sub, "must pin the subdir path")
local pline = vim.api.nvim_buf_get_lines(exp.state.pin_buf, 0, 1, false)[1]
assert(not pline:find("\\", 1, true), "pane path must not contain backslashes")

-- <Tab> only switches focus, it does not close the panel
exp.focus_pins()
assert(vim.api.nvim_get_current_win() == exp.state.pin_win, "focus_pins enters the panel")
assert(pane_open(), "focus_pins must not close the panel")
exp.focus_pins()
assert(vim.api.nvim_get_current_win() == exp.state.win, "focus_pins toggles back to main")

-- <CR>/l in the panel jumps the main view to the pin, focus returns to main, panel stays open
vim.api.nvim_set_current_win(exp.state.pin_win)
vim.api.nvim_win_set_cursor(exp.state.pin_win, { 1, 0 })
actions.pin_jump()
assert(exp.state.cwd == sub, "pin_jump must navigate the main view into the pin")
assert(vim.api.nvim_get_current_win() == exp.state.win, "focus returns to main after jump")
assert(pane_open(), "panel stays open after a jump")

-- d removes the pin under the cursor
vim.api.nvim_set_current_win(exp.state.pin_win)
vim.api.nvim_win_set_cursor(exp.state.pin_win, { 1, 0 })
actions.pin_remove()
assert(#pins.list() == 0, "pin_remove must empty the list")

-- with the panel closed, a no longer pins (the add is gated). cwd is now the
-- empty sub/, so the "../" row (line 1) is the only valid cursor target.
exp.toggle_pins()
assert(not pane_open(), "P closes the panel")
vim.api.nvim_win_set_cursor(exp.state.win, { 1, 0 })
actions.pin_add()
assert(#pins.list() == 0, "pin_add is a no-op while the panel is closed")

yfp.close()
assert(not yfp.is_open(), "the whole UI must close cleanly")
pins.reset()
assert(#pins.list() == 0, "removal must persist across a reload")
pcall(vim.fn.delete, pinfile)
yfp.setup({})
print("yfp: pinned-panel toggle/focus/add(gated)/jump/remove + persistence tests passed")

-- 4) open (`o`): edits a file in the origin window from either side; refuses folders
vim.o.hidden = true -- let :edit replace a modified scratch buffer without erroring
yfp.setup({ yank = { registers = {} }, pins = { file = pinfile } })
pins.reset()
yfp.open({ cwd = tmp })
local origin = exp.state.origin_win

-- buffer-local maps carry a description (so which-key shows something, not blank)
local desc_a
for _, mp in ipairs(vim.api.nvim_buf_get_keymap(exp.state.buf, "n")) do
  if mp.lhs == "a" then
    desc_a = mp.desc
  end
end
assert(desc_a and desc_a ~= "", "keymaps must set a non-empty desc (for which-key)")

-- main view: a folder (row 2 = "sub/") is refused, the float stays open
vim.api.nvim_win_set_cursor(exp.state.win, { 2, 0 })
actions.open_entry()
assert(yfp.is_open(), "open on a folder keeps the float open")

-- main view: a file (row 3 = "alpha.txt") opens in the origin window
vim.api.nvim_win_set_cursor(exp.state.win, { 3, 0 })
actions.open_entry()
assert(not yfp.is_open(), "open on a file closes the float")
local got = (vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin)):gsub("\\", "/"))
assert(got == expected, "the file is loaded in the origin window")

-- pinned panel: `o` on a file pin opens it too
vim.fn.writefile({ "y" }, tmp .. "/beta.txt")
pins.reset()
pins.add({ path = tmp .. "/beta.txt", is_dir = false })
yfp.open({ cwd = tmp })
origin = exp.state.origin_win
exp.toggle_pins()
vim.api.nvim_set_current_win(exp.state.pin_win)
vim.api.nvim_win_set_cursor(exp.state.pin_win, { 1, 0 })
actions.open_entry()
assert(not yfp.is_open(), "open from the panel closes the UI")
local got2 = (vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(origin)):gsub("\\", "/"))
assert(got2 == tmp .. "/beta.txt", "the pinned file opens in the origin window")
pins.reset()
pcall(vim.fn.delete, pinfile)
yfp.setup({})
print("yfp: open-in-origin-window (main + pinned panel) tests passed")

print("yfp: functional yank_and_paste + registers-only tests passed")
