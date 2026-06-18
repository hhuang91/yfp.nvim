-- yfp — Yank File Path. Public API.
-- A floating, read-only file browser that drops a path into your buffer with
-- forward slashes (and into your registers), even on Windows.
local M = {}

---@param opts table|nil
function M.setup(opts)
  require("yfp.config").setup(opts)
end

---@param opts table|nil  { cwd?: string, mode?: string }
function M.open(opts)
  require("yfp.explorer").open(opts)
end

function M.close()
  require("yfp.explorer").close()
end

function M.toggle()
  local exp = require("yfp.explorer")
  if exp.is_open() then
    exp.close()
  else
    exp.open()
  end
end

---@return boolean
function M.is_open()
  return require("yfp.explorer").is_open()
end

--- Set the base directory used by the "relative_custom" yank mode.
---@param dir string
function M.set_source_dir(dir)
  require("yfp.config").options.source_dir = dir
end

--- Programmatic yank of the entry under the cursor to registers (only valid while open).
---@param mode string|nil
function M.yank_under_cursor(mode)
  require("yfp.actions").yank(mode or "default")
end

--- Programmatic yank-and-paste of the entry under the cursor (only valid while open).
---@param mode string|nil
function M.yank_and_paste_under_cursor(mode)
  require("yfp.actions").yank_and_paste(mode or "default")
end

return M
