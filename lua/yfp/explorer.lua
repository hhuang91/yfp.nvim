-- yfp.explorer — floating window + scratch buffer lifecycle, rendering, keymaps.
-- Never writes to the filesystem. Owns the singleton state.
local api = vim.api
local uv = vim.uv or vim.loop
local config = require("yfp.config")
local fs = require("yfp.fs")
local path = require("yfp.path")

local M = {}

---@type table|nil
M.state = nil

local ns = api.nvim_create_namespace("yfp")

local function home()
  return uv.os_homedir() or vim.fn.expand("~")
end

local function ensure_highlights()
  local set = api.nvim_set_hl
  set(0, "YFPHeader", { link = "Title", default = true })
  set(0, "YFPDir", { link = "Directory", default = true })
  set(0, "YFPFile", { link = "Normal", default = true })
  set(0, "YFPLink", { link = "Question", default = true })
end

-- Optional icon provider, detected at runtime (keeps the zero-dependency promise).
local _provider = nil
local function provider()
  if _provider ~= nil then
    return _provider
  end
  if not config.options.icons.enabled then
    _provider = false
    return false
  end
  local ok, mini = pcall(require, "mini.icons")
  if ok then
    _provider = { kind = "mini", mod = mini }
    return _provider
  end
  local ok2, dev = pcall(require, "nvim-web-devicons")
  if ok2 then
    _provider = { kind = "dev", mod = dev }
    return _provider
  end
  _provider = false
  return false
end

local function icon_for(entry)
  local p = provider()
  if not p then
    return ""
  end
  if p.kind == "mini" then
    local i = p.mod.get(entry.is_dir and "directory" or "file", entry.name)
    return i or ""
  else
    if entry.is_dir then
      return ""
    end
    local ext = entry.name:match("%.([%w_-]+)$")
    local i = p.mod.get_icon(entry.name, ext, { default = true })
    return i or ""
  end
end

local function sort_entries(entries)
  local cfg = config.options
  table.sort(entries, function(a, b)
    if cfg.group_dirs_first and a.is_dir ~= b.is_dir then
      return a.is_dir
    end
    if cfg.sort == "type" and a.type ~= b.type then
      return a.type < b.type
    end
    return a.name:lower() < b.name:lower()
  end)
  return entries
end

local function set_winbar(state)
  if state.win and api.nvim_win_is_valid(state.win) then
    local cwd = (state.cwd:gsub("%%", "%%%%"))
    pcall(api.nvim_set_option_value, "winbar", "%#YFPHeader# " .. cwd .. " ", { win = state.win })
  end
end

local function render(state)
  local rows = { { kind = "up" } }
  for _, e in ipairs(state.entries) do
    rows[#rows + 1] = { kind = "entry", entry = e }
  end
  state.rows = rows

  local lines = {}
  for _, r in ipairs(rows) do
    if r.kind == "up" then
      lines[#lines + 1] = "../"
    else
      local e = r.entry
      local ic = icon_for(e)
      local prefix = (ic ~= "" and (ic .. " ")) or ""
      lines[#lines + 1] = prefix .. e.name .. (e.is_dir and "/" or "")
    end
  end

  api.nvim_set_option_value("modifiable", true, { buf = state.buf })
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = state.buf })

  api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  for i, r in ipairs(rows) do
    local grp
    if r.kind == "up" then
      grp = "YFPDir"
    elseif r.entry.is_dir then
      grp = "YFPDir"
    elseif r.entry.type == "link" then
      grp = "YFPLink"
    end
    if grp then
      pcall(api.nvim_buf_set_extmark, state.buf, ns, i - 1, 0, {
        line_hl_group = grp,
        hl_mode = "combine",
      })
    end
  end
end

local function place_cursor_first(state)
  local target = math.min(2, api.nvim_buf_line_count(state.buf))
  pcall(api.nvim_win_set_cursor, state.win, { math.max(target, 1), 0 })
end

-- Put the cursor on the entry named `name` in the main listing (used after
-- jumping to a pinned file so the file itself is highlighted). Falls back to the
-- first entry if it isn't present (e.g. hidden, or removed since pinning).
local function place_cursor_on(state, name)
  for i, r in ipairs(state.rows) do
    if r.kind == "entry" and r.entry.name == name then
      pcall(api.nvim_win_set_cursor, state.win, { i, 0 })
      return
    end
  end
  place_cursor_first(state)
end

local function key_label(k)
  if type(k) == "table" then
    return tostring(k[1] or "?")
  end
  return tostring(k)
end

-- Render the pinned-locations pane (its own buffer). Each pin shows its full
-- forward-slash path; missing paths are tagged so stale pins are obvious.
local function render_pins(state)
  if not (state.pin_buf and api.nvim_buf_is_valid(state.pin_buf)) then
    return
  end
  local pins = require("yfp.pins").list()
  local rows, lines = {}, {}
  for _, it in ipairs(pins) do
    rows[#rows + 1] = { kind = "pin", pin = it }
    local ic = icon_for({ name = vim.fs.basename(it.path), is_dir = it.is_dir })
    local prefix = (ic ~= "" and (ic .. " ")) or ""
    local missing = fs.exists(it.path) and "" or "  [missing]"
    lines[#lines + 1] = prefix .. path.slashify(it.path) .. (it.is_dir and "/" or "") .. missing
  end
  state.pin_rows = rows

  if #lines == 0 then
    local addkey = key_label(config.options.keymaps.pin_add)
    lines = { "  (empty) press " .. addkey .. " on an item to pin it" }
  end

  api.nvim_set_option_value("modifiable", true, { buf = state.pin_buf })
  api.nvim_buf_set_lines(state.pin_buf, 0, -1, false, lines)
  api.nvim_set_option_value("modifiable", false, { buf = state.pin_buf })

  api.nvim_buf_clear_namespace(state.pin_buf, ns, 0, -1)
  for i, it in ipairs(pins) do
    pcall(api.nvim_buf_set_extmark, state.pin_buf, ns, i - 1, 0, {
      line_hl_group = it.is_dir and "YFPDir" or "YFPFile",
      hl_mode = "combine",
    })
  end
end

local function ratio_or_abs(v, total)
  if v <= 1 then
    return math.floor(total * v)
  end
  return v
end

-- Compute the main float rect and, when the pinned pane is open, the bottom pane
-- rect. The two floats are stacked and centered as a single block; opening the
-- pane shortens the main listing rather than growing the overall footprint.
---@param cfg table
---@param pins_open boolean
---@return table main, table|nil pin   -- rects { width, height, row, col } (content top-left)
local function compute_layout(cfg, pins_open)
  local cols, lines = vim.o.columns, vim.o.lines
  local bt = (cfg.window.border and cfg.window.border ~= "none") and 1 or 0
  local gap = 0 -- blank rows between the two floats (0 = stacked borders touch)

  local width = ratio_or_abs(cfg.window.width, cols)
  width = math.max(math.min(width, cols - 2 * (bt + 1)), 20)

  local band = ratio_or_abs(cfg.window.height, lines)
  band = math.max(math.min(band, lines - 2 - 2 * bt), 5)

  local main_h, pin_h
  if pins_open then
    pin_h = ratio_or_abs(cfg.pins.height, band)
    pin_h = math.max(math.min(pin_h, band - 3 - 2 * bt - gap), 1)
    main_h = math.max(band - pin_h - 2 * bt - gap, 3)
  else
    pin_h, main_h = 0, band
  end

  local total = pins_open and (main_h + pin_h + 4 * bt + gap) or (main_h + 2 * bt)
  local top = math.max(math.floor((lines - total) / 2), 0)
  local col = math.max(math.floor((cols - width) / 2), 0)

  local main = { width = width, height = main_h, row = top + bt, col = col }
  local pin = nil
  if pins_open then
    pin = { width = width, height = pin_h, row = top + 3 * bt + main_h + gap, col = col }
  end
  return main, pin
end

-- Re-position the main float (and the pinned pane, if open) for the current
-- `pins_open` state and terminal size. Used on toggle and on VimResized.
local function relayout(state, pins_open)
  local main, pin = compute_layout(config.options, pins_open)
  if state.win and api.nvim_win_is_valid(state.win) then
    pcall(api.nvim_win_set_config, state.win, {
      relative = "editor",
      row = main.row,
      col = main.col,
      width = main.width,
      height = main.height,
    })
  end
  if pins_open and pin and state.pin_win and api.nvim_win_is_valid(state.pin_win) then
    pcall(api.nvim_win_set_config, state.pin_win, {
      relative = "editor",
      row = pin.row,
      col = pin.col,
      width = pin.width,
      height = pin.height,
    })
  end
  return main, pin
end

local function set_keymaps(buf)
  local km = config.options.keymaps
  local actions = require("yfp.actions")
  -- `desc` is what which-key (and :map) display, so every mapping gets one.
  local function map(lhs, fn, desc)
    if not lhs then
      return
    end
    local list = (type(lhs) == "table") and lhs or { lhs }
    for _, l in ipairs(list) do
      vim.keymap.set("n", l, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end
  end
  map(km.yank, function()
    actions.yank("default")
  end, "Yank path to registers")
  map(km.yank_and_paste, function()
    actions.yank_and_paste("default")
  end, "Yank + paste path")
  map(km.yank_menu, actions.yank_menu, "Yank path (pick format)")
  map(km.yank_and_paste_menu, actions.yank_and_paste_menu, "Yank + paste (pick format)")
  map(km.enter, actions.enter, "Enter directory")
  map(km.open, actions.open_entry, "Open file in origin window")
  map(km.up, actions.up, "Go up a directory")
  map(km.goto_path, actions.goto_path, "Go to a typed path")
  map(km.drives, actions.drives, "List drives (Windows)")
  map(km.home, function()
    M.set_cwd(home())
  end, "Go to home directory")
  map(km.cwd, function()
    M.set_cwd(vim.fn.getcwd())
  end, "Go to working directory")
  map(km.toggle_hidden, actions.toggle_hidden, "Toggle hidden files")
  map(km.pin_toggle, M.toggle_pins, "Toggle pinned panel")
  map(km.pin_focus, M.focus_pins, "Focus main / pinned panel")
  map(km.pin_add, actions.pin_add, "Pin item under cursor")
  map(km.close, M.close, "Close yfp")
  map(km.help, actions.help, "Show key help")
  -- km.filter is reserved for v1.1; native "/" search works in the meantime.
end

-- Buffer-local keymaps for the pinned-locations pane. <CR>/l jumps the main view
-- to the pin, `open` (o) edits a file pin, the remove key drops it, pin_toggle (P)
-- closes the panel, pin_focus (<Tab>) switches focus back to the main view, and
-- q/<Esc> closes everything.
local function set_pin_keymaps(buf)
  local km = config.options.keymaps
  local actions = require("yfp.actions")
  local function map(lhs, fn, desc)
    if not lhs then
      return
    end
    local list = (type(lhs) == "table") and lhs or { lhs }
    for _, l in ipairs(list) do
      vim.keymap.set("n", l, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end
  end
  map(km.enter, actions.pin_jump, "Jump to pinned location")
  map(km.open, actions.open_entry, "Open file pin in origin window")
  map(km.pin_remove, actions.pin_remove, "Remove pin")
  map(km.pin_toggle, M.toggle_pins, "Toggle pinned panel")
  map(km.pin_focus, M.focus_pins, "Focus main / pinned panel")
  map(km.close, M.close, "Close yfp")
  map(km.help, actions.help, "Show key help")
end

---@param mode string
---@param origin_buf integer
---@return string
function M.resolve_start(mode, origin_buf)
  local name = api.nvim_buf_get_name(origin_buf)
  if mode == "cwd" then
    return vim.fn.getcwd()
  elseif mode == "home" then
    return home()
  elseif mode == "git_root" then
    local base = (name ~= "") and vim.fs.dirname(name) or vim.fn.getcwd()
    return vim.fs.root(base, { ".git" }) or base
  end
  -- file_dir (default)
  if name ~= "" then
    local d = vim.fs.dirname(name)
    if d and fs.is_dir(d) then
      return d
    end
  end
  return vim.fn.getcwd()
end

--- Navigate the open explorer to `dir` (rescan + render).
---@param dir string
---@param focus_name string|nil  place the cursor on this entry instead of the first
function M.set_cwd(dir, focus_name)
  local state = M.state
  if not state then
    return
  end
  dir = path.slashify(dir)
  local entries, err = fs.scandir(dir, { show_hidden = state.show_hidden })
  if not entries then
    vim.notify("yfp: " .. tostring(err), vim.log.levels.WARN)
    return
  end
  sort_entries(entries)
  state.cwd = dir
  state.entries = entries
  render(state)
  set_winbar(state)
  if focus_name then
    place_cursor_on(state, focus_name)
  else
    place_cursor_first(state)
  end
end

--- The row under the cursor in the float, plus its line number.
---@return table|nil, integer|nil
function M.current_row()
  local state = M.state
  if not state or not (state.win and api.nvim_win_is_valid(state.win)) then
    return nil
  end
  local lnum = api.nvim_win_get_cursor(state.win)[1]
  return state.rows[lnum], lnum
end

--- The pin row under the cursor in the pinned pane, plus its line number. The
--- line number equals the pin's index in the list (1:1, in order).
---@return table|nil, integer|nil
function M.current_pin_row()
  local state = M.state
  if not state or not (state.pin_win and api.nvim_win_is_valid(state.pin_win)) then
    return nil
  end
  local lnum = api.nvim_win_get_cursor(state.pin_win)[1]
  return (state.pin_rows or {})[lnum], lnum
end

--- Re-render the pinned pane if it is currently open (after add/remove).
function M.refresh_pins()
  local state = M.state
  if state and state.pin_buf and api.nvim_buf_is_valid(state.pin_buf) then
    render_pins(state)
  end
end

---@return boolean
function M.is_open()
  return M.state ~= nil and M.state.win ~= nil and api.nvim_win_is_valid(M.state.win)
end

---@param opts table|nil  { cwd?: string }
function M.open(opts)
  opts = opts or {}
  if M.is_open() then
    api.nvim_set_current_win(M.state.win)
    return
  end
  ensure_highlights()
  local cfg = config.options

  -- capture origin before we steal focus
  local origin_win = api.nvim_get_current_win()
  local origin_buf = api.nvim_get_current_buf()
  local origin_cursor = api.nvim_win_get_cursor(origin_win)
  local origin_mode = api.nvim_get_mode().mode

  local start = opts.cwd or M.resolve_start(cfg.default_start, origin_buf)
  start = path.slashify(start)
  if not fs.is_dir(start) then
    local d = vim.fs.dirname(start)
    start = (d and fs.is_dir(d)) and path.slashify(d) or path.slashify(vim.fn.getcwd())
  end

  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  api.nvim_set_option_value("swapfile", false, { buf = buf })
  api.nvim_set_option_value("filetype", "yfp", { buf = buf })

  local main = compute_layout(cfg, false)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = main.width,
    height = main.height,
    row = main.row,
    col = main.col,
    style = "minimal",
    border = cfg.window.border,
    title = cfg.window.title,
    title_pos = cfg.window.title_pos,
  })
  api.nvim_set_option_value("cursorline", true, { win = win })
  api.nvim_set_option_value("wrap", false, { win = win })

  M.state = {
    cwd = start,
    entries = {},
    rows = {},
    win = win,
    buf = buf,
    pin_win = nil,
    pin_buf = nil,
    pin_rows = nil,
    closing = false,
    origin_win = origin_win,
    origin_buf = origin_buf,
    origin_cursor = origin_cursor,
    origin_mode = origin_mode,
    show_hidden = cfg.show_hidden,
    filter = "",
  }

  set_keymaps(buf)
  M.set_cwd(start)

  -- One handler watches every window close while yfp is open (the pinned pane is
  -- created later, so we can't pin a pattern to it up front). Closing the MAIN
  -- float tears everything down; closing just the PANE restores the main float.
  local group = api.nvim_create_augroup("yfp", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local st = M.state
      if not st then
        return
      end
      local closed = tonumber(args.match)
      if st.closing then
        if closed == st.win then
          M.cleanup()
        end
        return
      end
      if closed == st.win then
        M.cleanup()
      elseif closed == st.pin_win then
        st.pin_win, st.pin_buf, st.pin_rows = nil, nil, nil
        if st.win and api.nvim_win_is_valid(st.win) then
          relayout(st, false)
          pcall(api.nvim_set_current_win, st.win)
        end
      end
    end,
  })
  api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      local st = M.state
      if not st then
        return
      end
      relayout(st, st.pin_win ~= nil and api.nvim_win_is_valid(st.pin_win))
    end,
  })
end

--- Open the pinned-locations pane beneath the main float. Focus stays in the
--- main view unless `focus` is true; opening/closing is driven by `pin_toggle`
--- and switching focus by `pin_focus`, so the two concerns stay separate.
---@param focus boolean|nil
function M.open_pins(focus)
  local state = M.state
  if not state or not M.is_open() then
    return
  end
  if not config.options.pins.enabled then
    vim.notify("yfp: pins are disabled (set pins.enabled = true)", vim.log.levels.INFO)
    return
  end
  if state.pin_win and api.nvim_win_is_valid(state.pin_win) then
    if focus then
      api.nvim_set_current_win(state.pin_win)
    end
    return
  end
  local cfg = config.options
  local _, pin = relayout(state, true) -- shrink the main float to make room
  local buf = api.nvim_create_buf(false, true)
  api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  api.nvim_set_option_value("swapfile", false, { buf = buf })
  api.nvim_set_option_value("filetype", "yfp-pins", { buf = buf })
  local win = api.nvim_open_win(buf, focus == true, {
    relative = "editor",
    width = pin.width,
    height = pin.height,
    row = pin.row,
    col = pin.col,
    style = "minimal",
    border = cfg.window.border,
    title = cfg.pins.title,
    title_pos = cfg.window.title_pos,
  })
  api.nvim_set_option_value("cursorline", true, { win = win })
  api.nvim_set_option_value("wrap", false, { win = win })
  state.pin_win = win
  state.pin_buf = buf
  set_pin_keymaps(buf)
  render_pins(state)
  pcall(api.nvim_win_set_cursor, win, { 1, 0 })
end

--- Close the pinned pane (keeping the main float open) and restore its height.
function M.close_pins()
  local state = M.state
  if not state then
    return
  end
  local win = state.pin_win
  state.pin_win, state.pin_buf, state.pin_rows = nil, nil, nil
  if win and api.nvim_win_is_valid(win) then
    pcall(api.nvim_win_close, win, true)
  end
  if state.win and api.nvim_win_is_valid(state.win) then
    relayout(state, false)
    pcall(api.nvim_set_current_win, state.win)
  end
end

--- Toggle the pinned pane open/closed. Opening keeps focus in the main view.
function M.toggle_pins()
  local state = M.state
  if not state then
    return
  end
  if state.pin_win and api.nvim_win_is_valid(state.pin_win) then
    M.close_pins()
  else
    M.open_pins(false)
  end
end

--- Switch focus between the main view and the pinned pane. No-op if the pane is
--- closed -- opening/closing is `pin_toggle`'s job, not this one's.
function M.focus_pins()
  local state = M.state
  if not state or not (state.pin_win and api.nvim_win_is_valid(state.pin_win)) then
    return
  end
  local cur = api.nvim_get_current_win()
  local target = (cur == state.pin_win) and state.win or state.pin_win
  if target and api.nvim_win_is_valid(target) then
    api.nvim_set_current_win(target)
  end
end

--- Close the float (focus returns to the origin window automatically). Tears down
--- the pinned pane too.
function M.close()
  local state = M.state
  if state then
    state.closing = true
    if state.pin_win and api.nvim_win_is_valid(state.pin_win) then
      pcall(api.nvim_win_close, state.pin_win, true)
    end
    if state.win and api.nvim_win_is_valid(state.win) then
      pcall(api.nvim_win_close, state.win, true)
    end
  end
  M.cleanup()
end

function M.cleanup()
  local st = M.state
  if not st then
    return
  end
  st.closing = true
  if st.pin_win and api.nvim_win_is_valid(st.pin_win) then
    pcall(api.nvim_win_close, st.pin_win, true)
  end
  M.state = nil
end

return M
