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

local function geometry(w)
  local cols = vim.o.columns
  local lines = vim.o.lines
  local width = (w.width <= 1) and math.floor(cols * w.width) or w.width
  local height = (w.height <= 1) and math.floor(lines * w.height) or w.height
  width = math.max(math.min(width, cols - 2), 20)
  height = math.max(math.min(height, lines - 2), 5)
  local row = math.max(math.floor((lines - height) / 2 - 1), 0)
  local col = math.max(math.floor((cols - width) / 2), 0)
  return width, height, row, col
end

local function set_keymaps(buf)
  local km = config.options.keymaps
  local actions = require("yfp.actions")
  local function map(lhs, fn)
    if not lhs then
      return
    end
    local list = (type(lhs) == "table") and lhs or { lhs }
    for _, l in ipairs(list) do
      vim.keymap.set("n", l, fn, { buffer = buf, nowait = true, silent = true })
    end
  end
  map(km.yank, function()
    actions.yank("default")
  end)
  map(km.yank_register, function()
    actions.yank("default", { insert = false })
  end)
  map(km.yank_menu, actions.yank_menu)
  map(km.enter, actions.enter)
  map(km.up, actions.up)
  map(km.goto_path, actions.goto_path)
  map(km.drives, actions.drives)
  map(km.home, function()
    M.set_cwd(home())
  end)
  map(km.cwd, function()
    M.set_cwd(vim.fn.getcwd())
  end)
  map(km.toggle_hidden, actions.toggle_hidden)
  map(km.close, M.close)
  map(km.help, actions.help)
  -- km.filter is reserved for v1.1; native "/" search works in the meantime.
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
function M.set_cwd(dir)
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
  place_cursor_first(state)
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

  local width, height, row, col = geometry(cfg.window)
  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
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
    origin_win = origin_win,
    origin_buf = origin_buf,
    origin_cursor = origin_cursor,
    origin_mode = origin_mode,
    show_hidden = cfg.show_hidden,
    filter = "",
  }

  set_keymaps(buf)
  M.set_cwd(start)

  local group = api.nvim_create_augroup("yfp", { clear = true })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = function()
      M.cleanup()
    end,
  })
end

--- Close the float (focus returns to the origin window automatically).
function M.close()
  local state = M.state
  if state and state.win and api.nvim_win_is_valid(state.win) then
    pcall(api.nvim_win_close, state.win, true)
  end
  M.cleanup()
end

function M.cleanup()
  M.state = nil
end

return M
