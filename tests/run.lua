-- Smoke + pure-logic tests. Run from the repo root:
--   nvim --headless -l tests/run.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- 1) every module loads and parses cleanly
require("yfp")
require("yfp.config")
require("yfp.fs")
require("yfp.explorer")
require("yfp.actions")

-- 2) pure path logic
local path = require("yfp.path")

local fails = 0
local function eq(got, want, msg)
  if got ~= want then
    fails = fails + 1
    local fmt = "FAIL %s: expected %q, got %q\n"
    io.stderr:write(fmt:format(msg or "eq", tostring(want), tostring(got)))
  end
end

eq(path.slashify([[C:\Users\me\f.lua]]), "C:/Users/me/f.lua", "slashify")
eq(path.join("C:/", "Users"), "C:/Users", "join at drive root")
eq(path.join("C:/Users", "me"), "C:/Users/me", "join")
eq(path.apply_separator("C:/a/b", "/"), "C:/a/b", "separator forward")
eq(path.apply_separator("C:/a/b", "\\"), [[C:\a\b]], "separator back")
eq(path.parent("C:/Users/me"), "C:/Users", "parent")
eq(path.parent("C:/Users"), "C:/", "parent to drive root")
eq(path.parent("C:/"), nil, "parent of drive root is nil")
eq(path.parent("/home"), "/", "parent on unix")
eq(path.is_root("C:/"), true, "drive root is root")
eq(path.is_root("/"), true, "unix root is root")
eq(path.is_root("C:/Users"), false, "non-root")

-- config merge
local config = require("yfp.config")

-- regression: setup({}) must keep ALL defaults (it used to wipe them to {})
config.setup({})
eq(type(config.options.window), "table", "setup({}) keeps window defaults")
eq(config.options.window.width, 0.7, "setup({}) keeps nested window default")
eq(#config.options.yank.registers, 2, "setup({}) keeps default registers")
eq(config.options.yank.default_mode, "absolute", "setup({}) keeps yank defaults")

-- list options replace wholesale rather than index-merge
config.setup({ yank = { registers = { "+" } } })
eq(#config.options.yank.registers, 1, "registers replaced, not merged")
eq(config.options.yank.registers[1], "+", "registers value")
eq(config.options.yank.insert, true, "sibling defaults preserved")

-- an explicit empty list still clears (e.g. disable registers)
config.setup({ yank = { registers = {} } })
eq(#config.options.yank.registers, 0, "empty registers list clears them")
eq(type(config.options.window), "table", "window intact alongside a nested empty list")

-- keymap list overrides replace, they don't append
config.setup({ keymaps = { enter = { "<CR>" } } })
eq(#config.options.keymaps.enter, 1, "keymap list replaced, not appended")
eq(config.options.keymaps.up[1], "-", "other keymap defaults preserved")

config.setup({}) -- reset to defaults

if fails > 0 then
  io.stderr:write(("yfp: %d test(s) failed\n"):format(fails))
  os.exit(1)
end
print("yfp: all modules loaded; all path/config tests passed")
