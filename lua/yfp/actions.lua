-- yfp.actions — user-facing handlers. No direct filesystem writes.
local api = vim.api
local config = require("yfp.config")
local path = require("yfp.path")

local M = {}

local function explorer()
  return require("yfp.explorer")
end

local function notify(msg, level)
  vim.notify("yfp: " .. msg, level or vim.log.levels.INFO)
end

-- Build the final output string for an entry in the given mode.
local function build_path(entry, mode)
  local cfg = config.options
  local state = explorer().state
  if mode == nil or mode == "default" then
    mode = cfg.yank.default_mode
  end
  local ctx = {
    cwd = state.cwd,
    buf_path = api.nvim_buf_get_name(state.origin_buf),
    source_dir = cfg.source_dir,
  }
  local out = path.transform(entry.path, mode, ctx)
  out = path.apply_separator(out, cfg.yank.separator) -- guaranteed final slash normalize (D3)
  if entry.is_dir and cfg.yank.dir_trailing_slash then
    local last = out:sub(-1)
    if last ~= "/" and last ~= "\\" then
      out = out .. ((cfg.yank.separator == "\\") and "\\" or "/")
    end
  end
  return out
end

-- Worker: yank to the configured registers, optionally pasting at the origin cursor.
local function do_yank(mode, insert)
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  local row = exp.current_row()
  if not row or row.kind ~= "entry" then
    notify("nothing to yank on this line")
    return
  end
  local cfg = config.options
  local out = build_path(row.entry, mode)

  -- capture origin before closing (state is cleared on close)
  local origin_win = state.origin_win
  local origin_buf = state.origin_buf
  local origin_cursor = state.origin_cursor
  local origin_mode = state.origin_mode

  for _, r in ipairs(cfg.yank.registers) do
    pcall(vim.fn.setreg, r, out)
  end

  exp.close()

  if not insert then
    notify("yanked: " .. out)
    return
  end

  if
    not (
      api.nvim_buf_is_valid(origin_buf)
      and api.nvim_get_option_value("modifiable", { buf = origin_buf })
    )
  then
    notify("origin buffer not writable — copied to registers")
    return
  end

  if origin_win and api.nvim_win_is_valid(origin_win) then
    pcall(api.nvim_set_current_win, origin_win)
  end

  local r0 = origin_cursor[1] - 1
  local c0 = origin_cursor[2]
  if cfg.yank.insert_position == "after_cursor" then
    local line = api.nvim_buf_get_lines(origin_buf, r0, r0 + 1, false)[1] or ""
    c0 = math.min(c0 + 1, #line)
  end
  pcall(api.nvim_buf_set_text, origin_buf, r0, c0, r0, c0, { out })
  if origin_win and api.nvim_win_is_valid(origin_win) then
    pcall(api.nvim_win_set_cursor, origin_win, { r0 + 1, c0 + #out })
  end
  if cfg.yank.keep_insert and origin_mode:sub(1, 1) == "i" then
    vim.schedule(function()
      vim.cmd("startinsert")
    end)
  end
  notify("inserted: " .. out)
end

--- Yank the path under the cursor to the configured registers (Vim-like; no paste).
---@param mode string|nil
function M.yank(mode)
  do_yank(mode, false)
end

--- Yank the path under the cursor AND paste it at the origin cursor.
---@param mode string|nil
function M.yank_and_paste(mode)
  do_yank(mode, true)
end

-- Pick a path format via vim.ui.select, then run the chosen yank (registers
-- only when insert=false, registers + paste when insert=true).
local function do_menu(insert)
  local modes = { "absolute", "relative_cwd", "relative_buffer", "relative_git", "relative_custom" }
  local prompt = insert and "yfp: paste path as" or "yfp: yank path as"
  vim.ui.select(modes, { prompt = prompt }, function(choice)
    if choice then
      do_yank(choice, insert)
    end
  end)
end

--- Pick a path format, then yank to registers (no paste) -- the menu form of `y`.
function M.yank_menu()
  do_menu(false)
end

--- Pick a path format, then yank AND paste at the cursor -- the menu form of `p`.
function M.yank_and_paste_menu()
  do_menu(true)
end

function M.enter()
  local exp = explorer()
  local row = exp.current_row()
  if not row then
    return
  end
  if row.kind == "up" then
    return M.up()
  end
  if row.entry.is_dir then
    exp.set_cwd(row.entry.path)
  else
    notify("not a directory — press the yank key to copy its path")
  end
end

function M.up()
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  local parent = path.parent(state.cwd)
  if parent then
    exp.set_cwd(parent)
  elseif vim.fn.has("win32") == 1 then
    M.drives()
  else
    notify("already at the filesystem root")
  end
end

function M.drives()
  if vim.fn.has("win32") ~= 1 then
    notify("drive view is Windows-only")
    return
  end
  local drives = require("yfp.fs").drives()
  if #drives == 0 then
    notify("no drives found")
    return
  end
  vim.ui.select(drives, { prompt = "yfp: select drive" }, function(choice)
    if choice then
      explorer().set_cwd(choice)
    end
  end)
end

function M.goto_path()
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  vim.ui.input(
    { prompt = "yfp: go to path: ", default = state.cwd, completion = "dir" },
    function(input)
      if not input or input == "" then
        return
      end
      local p = path.slashify(vim.fn.expand(input))
      if require("yfp.fs").is_dir(p) then
        exp.set_cwd(p)
      else
        notify("not a directory: " .. p, vim.log.levels.WARN)
      end
    end
  )
end

function M.toggle_hidden()
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  state.show_hidden = not state.show_hidden
  exp.set_cwd(state.cwd)
  notify("hidden files " .. (state.show_hidden and "shown" or "hidden"))
end

--- Pin the entry under the cursor in the main view (the cwd itself on "../").
function M.pin_add()
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  if not config.options.pins.enabled then
    notify("pins are disabled (set pins.enabled = true)")
    return
  end
  -- Adding is only allowed while the pinned panel is open (see DESIGN §7.4).
  if not (state.pin_win and api.nvim_win_is_valid(state.pin_win)) then
    local km = config.options.keymaps
    local k = (type(km.pin_toggle) == "table") and km.pin_toggle[1] or km.pin_toggle
    notify("open the pinned panel first (" .. tostring(k) .. ")")
    return
  end
  local pins = require("yfp.pins")
  local row = exp.current_row()
  local target
  if not row or row.kind == "up" then
    target = { path = state.cwd, is_dir = true }
  else
    target = { path = row.entry.path, is_dir = row.entry.is_dir }
  end
  if pins.add(target) then
    notify("pinned: " .. path.slashify(target.path))
  else
    notify("already pinned: " .. path.slashify(target.path))
  end
  exp.refresh_pins()
end

--- Remove the pin under the cursor in the pinned pane.
function M.pin_remove()
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  local row, lnum = exp.current_pin_row()
  if not row or row.kind ~= "pin" then
    notify("no pin on this line")
    return
  end
  local pins = require("yfp.pins")
  local removed = pins.remove(lnum)
  if removed then
    notify("unpinned: " .. path.slashify(removed.path))
    exp.refresh_pins()
    local n = math.max(#pins.list(), 1)
    if state.pin_win and api.nvim_win_is_valid(state.pin_win) then
      pcall(api.nvim_win_set_cursor, state.pin_win, { math.min(lnum, n), 0 })
    end
  end
end

--- Jump the main view to the pin under the cursor, then focus the main float.
--- Directory pins cd into them; file pins cd to the parent and land on the file.
function M.pin_jump()
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  local row = exp.current_pin_row()
  if not row or row.kind ~= "pin" then
    return
  end
  local fs = require("yfp.fs")
  local p = row.pin.path
  if row.pin.is_dir then
    if not fs.is_dir(p) then
      notify("pinned folder is gone: " .. p, vim.log.levels.WARN)
      return
    end
    exp.set_cwd(p)
  else
    local parent = path.parent(p) or vim.fs.dirname(p)
    if not (parent and fs.is_dir(parent)) then
      notify("pinned file's folder is gone: " .. p, vim.log.levels.WARN)
      return
    end
    exp.set_cwd(parent, vim.fs.basename(p))
  end
  if state.win and api.nvim_win_is_valid(state.win) then
    pcall(api.nvim_set_current_win, state.win)
  end
end

-- Close the float and :edit `abspath` in the window yfp was launched from
-- (picker-style). Opening is a read -- yfp still never writes the filesystem.
local function do_open(abspath)
  local exp = explorer()
  local state = exp.state
  local origin_win = state and state.origin_win
  exp.close()
  if origin_win and api.nvim_win_is_valid(origin_win) then
    pcall(api.nvim_set_current_win, origin_win)
  end
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(abspath))
  if not ok then
    notify("could not open: " .. tostring(err), vim.log.levels.WARN)
    return
  end
  notify("opened: " .. abspath)
end

--- Open the selected entry in the origin window. Works from the main view and
--- the pinned panel; only files open (folders/`../` just say so).
function M.open_entry()
  local exp = explorer()
  local state = exp.state
  if not state then
    return
  end
  local fs = require("yfp.fs")
  -- pinned panel side (focus is in the pane)
  if
    state.pin_win
    and api.nvim_win_is_valid(state.pin_win)
    and api.nvim_get_current_win() == state.pin_win
  then
    local row = exp.current_pin_row()
    if not row or row.kind ~= "pin" then
      return
    end
    if row.pin.is_dir then
      notify("that pin is a folder, not a file")
      return
    end
    if not fs.exists(row.pin.path) then
      notify("file no longer exists: " .. row.pin.path, vim.log.levels.WARN)
      return
    end
    do_open(row.pin.path)
    return
  end
  -- main view side
  local row = exp.current_row()
  if not row or row.kind ~= "entry" then
    notify("nothing to open on this line")
    return
  end
  if row.entry.is_dir then
    notify("that's a folder, not a file")
    return
  end
  do_open(row.entry.path)
end

function M.filter()
  notify("in-float fuzzy filter arrives in v1.1 (use / for native search for now)")
end

function M.help()
  local km = config.options.keymaps
  local function f(x)
    return (type(x) == "table") and table.concat(x, " / ") or tostring(x)
  end
  local lines = {
    "yfp — keys inside the float:",
    ("  %-12s yank to registers only"):format(f(km.yank)),
    ("  %-12s yank AND paste at the cursor"):format(f(km.yank_and_paste)),
    ("  %-12s yank (registers), pick a format"):format(f(km.yank_menu)),
    ("  %-12s yank AND paste, pick a format"):format(f(km.yank_and_paste_menu)),
    ("  %-12s enter directory"):format(f(km.enter)),
    ("  %-12s open the file (origin window)"):format(f(km.open)),
    ("  %-12s go up"):format(f(km.up)),
    ("  %-12s go to a typed path"):format(f(km.goto_path)),
    ("  %-12s list drives (Windows)"):format(f(km.drives)),
    ("  %-12s home / working dir"):format(f(km.home) .. " / " .. f(km.cwd)),
    ("  %-12s toggle hidden"):format(f(km.toggle_hidden)),
    ("  %-12s toggle the pinned panel"):format(f(km.pin_toggle)),
    ("  %-12s switch focus: main <-> panel"):format(f(km.pin_focus)),
    ("  %-12s pin the item (panel must be open)"):format(f(km.pin_add)),
    ("  %-12s remove the pin (in the panel)"):format(f(km.pin_remove)),
    ("  %-12s close"):format(f(km.close)),
  }
  vim.notify(table.concat(lines, "\n"))
end

return M
