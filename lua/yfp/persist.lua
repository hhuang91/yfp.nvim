-- yfp.persist — the ONLY module that WRITES to disk, and it writes exactly one
-- thing: yfp's own pins state file under stdpath("data"). It never touches the
-- filesystem you browse (that stays strictly read-only -- see CLAUDE.md Golden
-- Rule #2 and DESIGN.md D6). No mutating vim.uv calls and no shell-outs; writes
-- go through vim.fn.writefile, the directory is created with vim.fn.mkdir, and
-- the path is always rooted at stdpath("data"). The CI invariant grep allows
-- those host-write calls ONLY in this file (scripts/check_no_writes.sh).
local M = {}

local config = require("yfp.config")

-- Resolve (dir, file) for the pins state file. Always rooted at stdpath("data")
-- unless the user explicitly overrides config.pins.file (handy for tests). We
-- never derive this path from a browsed/yanked path.
---@return string dir, string file
local function locate()
  local override = config.options.pins and config.options.pins.file
  if override and override ~= "" then
    local file = (override:gsub("\\", "/"))
    return vim.fs.dirname(file), file
  end
  local data = (vim.fn.stdpath("data"):gsub("\\", "/"))
  local dir = data .. "/yfp"
  return dir, dir .. "/pins.json"
end

--- The resolved pins file path (for messages / tests).
---@return string
function M.path()
  local _, file = locate()
  return file
end

--- Load the persisted pin list. Returns {} if missing, unreadable, or malformed.
---@return table[]  -- list of { path = string, is_dir = boolean }
function M.load()
  local _, file = locate()
  if vim.fn.filereadable(file) == 0 then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or type(lines) ~= "table" or #lines == 0 then
    return {}
  end
  local decoded
  ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok or type(decoded) ~= "table" then
    return {}
  end
  local out = {}
  for _, item in ipairs(decoded) do
    if type(item) == "table" and type(item.path) == "string" and item.path ~= "" then
      out[#out + 1] = { path = item.path, is_dir = item.is_dir == true }
    end
  end
  return out
end

--- Persist the pin list (whole-file write). Best-effort; notifies on failure.
---@param pins table[]
---@return boolean ok
function M.save(pins)
  local dir, file = locate()
  if vim.fn.isdirectory(dir) == 0 then
    pcall(vim.fn.mkdir, dir, "p")
  end
  local ok, encoded = pcall(vim.json.encode, pins or {})
  if not ok then
    return false
  end
  if not pcall(vim.fn.writefile, { encoded }, file) then
    vim.notify("yfp: could not write pins to " .. file, vim.log.levels.WARN)
    return false
  end
  return true
end

return M
