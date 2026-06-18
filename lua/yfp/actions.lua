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

--- Yank the path under the cursor: set registers and (optionally) insert at the origin cursor.
---@param mode string|nil
---@param override table|nil  { insert: boolean }
function M.yank(mode, override)
  override = override or {}
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

  local do_insert = cfg.yank.insert and override.insert ~= false
  if not do_insert then
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

function M.yank_menu()
  local modes =
    { "absolute", "relative_cwd", "relative_buffer", "relative_git", "relative_custom" }
  vim.ui.select(modes, { prompt = "yfp: path format" }, function(choice)
    if choice then
      M.yank(choice)
    end
  end)
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
    ("  %-12s yank: insert at cursor + set registers"):format(f(km.yank)),
    ("  %-12s yank to registers only"):format(f(km.yank_register)),
    ("  %-12s yank, choosing a path format"):format(f(km.yank_menu)),
    ("  %-12s enter directory"):format(f(km.enter)),
    ("  %-12s go up"):format(f(km.up)),
    ("  %-12s go to a typed path"):format(f(km.goto_path)),
    ("  %-12s list drives (Windows)"):format(f(km.drives)),
    ("  %-12s home / working dir"):format(f(km.home) .. " / " .. f(km.cwd)),
    ("  %-12s toggle hidden"):format(f(km.toggle_hidden)),
    ("  %-12s close"):format(f(km.close)),
  }
  vim.notify(table.concat(lines, "\n"))
end

return M
