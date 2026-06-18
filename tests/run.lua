-- Smoke + pure-logic tests. Run from the repo root:
--   nvim --headless -l tests/run.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- 1) every module loads and parses cleanly
require("yfp")
require("yfp.config")
require("yfp.fs")
require("yfp.explorer")
require("yfp.actions")
require("yfp.persist")
require("yfp.pins")

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
eq(config.options.keymaps.yank, "y", "default yank key")
eq(config.options.keymaps.yank_and_paste, "p", "default yank_and_paste key")
eq(config.options.keymaps.yank_menu, "gy", "default yank_menu key (registers only)")
eq(config.options.keymaps.yank_and_paste_menu, "gp", "default yank_and_paste_menu key")
eq(config.options.keymaps.drives, "D", "default drives key")
eq(config.options.keymaps.open, "o", "default open key")
eq(config.options.keymaps.pin_toggle, "P", "default pin_toggle key")
eq(config.options.keymaps.pin_focus, "<Tab>", "default pin_focus key")
eq(config.options.keymaps.pin_add, "a", "default pin_add key")
eq(config.options.keymaps.pin_remove, "d", "default pin_remove key")

-- list options replace wholesale rather than index-merge
config.setup({ yank = { registers = { "+" } } })
eq(#config.options.yank.registers, 1, "registers replaced, not merged")
eq(config.options.yank.registers[1], "+", "registers value")
eq(config.options.yank.keep_insert, true, "sibling defaults preserved")

-- an explicit empty list still clears (e.g. disable registers)
config.setup({ yank = { registers = {} } })
eq(#config.options.yank.registers, 0, "empty registers list clears them")
eq(type(config.options.window), "table", "window intact alongside a nested empty list")

-- keymap list overrides replace, they don't append
config.setup({ keymaps = { enter = { "<CR>" } } })
eq(#config.options.keymaps.enter, 1, "keymap list replaced, not appended")
eq(config.options.keymaps.up[1], "-", "other keymap defaults preserved")

config.setup({}) -- reset to defaults

-- pins: add / dedupe / remove / persistence round-trip.
-- Use a temp file, NOT the real stdpath("data") pins file.
local pins = require("yfp.pins")
local pinfile = (vim.fn.tempname():gsub("\\", "/")) .. "-pins.json"
config.setup({ pins = { file = pinfile } })
pins.reset()
eq(#pins.list(), 0, "pins start empty")
eq(pins.add({ path = "C:/tmp/a", is_dir = true }), true, "add a new pin")
eq(pins.add({ path = "C:/tmp/a", is_dir = true }), false, "dedupe an identical pin")
eq(pins.add({ path = [[C:\tmp\a\]], is_dir = true }), false, "dedupe across separators")
eq(#pins.list(), 1, "still one pin after dedupe")
pins.add({ path = "C:/tmp/b.txt", is_dir = false })
eq(#pins.list(), 2, "second pin added")
eq(pins.list()[1].path, "C:/tmp/a", "stored path is slash-normalized")
pins.reset() -- force a reload from disk
eq(#pins.list(), 2, "pins persisted and reloaded")
eq(pins.list()[2].is_dir, false, "is_dir flag round-trips")
eq(pins.remove(1) ~= nil, true, "remove returns the item")
eq(#pins.list(), 1, "one pin left after remove")
pins.reset()
eq(#pins.list(), 1, "removal persisted")
eq(pins.list()[1].path, "C:/tmp/b.txt", "the surviving pin is correct")
pcall(vim.fn.delete, pinfile)
config.setup({}) -- reset to defaults
pins.reset()

if fails > 0 then
  io.stderr:write(("yfp: %d test(s) failed\n"):format(fails))
  os.exit(1)
end
print("yfp: all modules loaded; all path/config tests passed")
