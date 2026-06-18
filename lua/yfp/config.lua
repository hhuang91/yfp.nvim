-- yfp.config — default options and user-option merge.
local M = {}

---@class yfp.Config
M.defaults = {
  window = {
    width = 0.7, -- ratio of columns, or an integer for absolute columns
    height = 0.7, -- ratio of lines, or an integer for absolute lines
    border = "rounded",
    title = " yfp ",
    title_pos = "center",
  },

  default_start = "file_dir", -- "file_dir" | "cwd" | "git_root" | "home"
  show_hidden = true,
  group_dirs_first = true,
  sort = "name", -- "name" | "type"
  resolve_symlinks = false,

  yank = {
    separator = "/", -- "/" force forward slashes | "\\" | "os" (native)
    registers = { '"', "+" }, -- copy to these registers (both yank actions)
    insert_position = "after_cursor", -- "at_cursor" | "after_cursor" (paste action)
    keep_insert = true, -- re-enter insert mode if opened from insert mode
    dir_trailing_slash = false,
    default_mode = "absolute", -- see README for the full list of modes
  },

  source_dir = nil, -- base directory for the "relative_custom" mode

  -- Pinned locations: a toggleable bottom pane of saved files/folders for quick
  -- navigation. Persisted to yfp's OWN state file under stdpath("data") -- the
  -- only thing yfp ever writes (see DESIGN.md D6); the browsed filesystem stays
  -- strictly read-only.
  pins = {
    enabled = true,
    file = nil, -- default: stdpath("data").."/yfp/pins.json" (set a path to override)
    height = 0.25, -- bottom pane height: ratio of the window band, or integer rows
    title = " pinned ",
  },

  icons = { enabled = true }, -- uses mini.icons / nvim-web-devicons if present

  keymaps = {
    yank = "y", -- registers only (Vim-like)
    yank_and_paste = "p", -- insert at the cursor + set registers
    yank_menu = "gy",
    enter = { "<CR>", "l" },
    up = { "-", "h" },
    goto_path = "<C-g>",
    drives = "D",
    home = "~",
    cwd = "=",
    toggle_hidden = ".",
    filter = "/", -- reserved for v1.1; native "/" search works meanwhile
    close = { "q", "<Esc>" },
    help = "g?",
    -- pinned locations
    pin_toggle = "<Tab>", -- main: open/focus the pinned pane; pane: close it
    pin_add = "P", -- main: pin the item under the cursor
    pin_remove = { "x", "dd" }, -- pane: remove the pin under the cursor
  },
}

-- True for tables with only integer keys (including the empty table).
local function is_list(t)
  if type(t) ~= "table" then
    return false
  end
  for k in pairs(t) do
    if type(k) ~= "number" then
      return false
    end
  end
  return true
end

-- Deep-merge maps key-by-key. Whether a value is a "list" (replace wholesale) or a
-- "map" (merge) is decided by the DEFAULTS' shape, not the user's input -- so an empty
-- opts table ({}) keeps all defaults, while keymaps.enter = { "<CR>" } still replaces
-- the default list instead of index-merging with it.
local function deep_merge(base, override)
  if override == nil then
    return base
  end
  if type(base) ~= "table" or type(override) ~= "table" then
    return override
  end
  if is_list(base) then
    return vim.deepcopy(override)
  end
  local out = vim.deepcopy(base)
  for k, v in pairs(override) do
    out[k] = deep_merge(out[k], v)
  end
  return out
end

M.options = vim.deepcopy(M.defaults)

---@param opts table|nil
---@return table
function M.setup(opts)
  M.options = deep_merge(M.defaults, opts or {})
  return M.options
end

return M
