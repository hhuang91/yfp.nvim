-- yfp.pins — the user's pinned locations: an in-memory list plus add/remove and
-- dedupe. All persistence is delegated to yfp.persist (the only module that
-- writes). This module performs NO filesystem access of its own.
local persist = require("yfp.persist")
local path = require("yfp.path")

local M = {}

---@type table[]|nil  -- list of { path = string, is_dir = boolean }; nil until loaded
local items = nil

-- Comparison key: forward slashes, trailing slashes stripped, case-folded so
-- "C:/Tmp" and "c:\\tmp\\" pin the same location (matters on Windows).
local function key(p)
  return (path.slashify(p):gsub("/+$", "")):lower()
end

--- Load from disk once (lazy). Safe to call repeatedly.
---@return table[]
function M.ensure_loaded()
  if items == nil then
    items = persist.load()
  end
  return items
end

--- The current pin list (loads on first use). Do not mutate the result directly.
---@return table[]
function M.list()
  return M.ensure_loaded()
end

--- Is this path already pinned?
---@param p string
---@return boolean
function M.contains(p)
  local k = key(p)
  for _, it in ipairs(M.list()) do
    if key(it.path) == k then
      return true
    end
  end
  return false
end

--- Add a pin. No-op (returns false) if the path is already pinned.
---@param entry { path: string, is_dir: boolean }
---@return boolean added
function M.add(entry)
  M.ensure_loaded()
  local p = path.slashify(entry.path)
  if M.contains(p) then
    return false
  end
  items[#items + 1] = { path = p, is_dir = entry.is_dir == true }
  persist.save(items)
  return true
end

--- Remove the pin at list index `i`. Returns the removed item, or nil if out of range.
---@param i integer
---@return table|nil
function M.remove(i)
  M.ensure_loaded()
  if i < 1 or i > #items then
    return nil
  end
  local removed = table.remove(items, i)
  persist.save(items)
  return removed
end

--- Drop the in-memory cache so the next access reloads from disk (tests / reload).
function M.reset()
  items = nil
end

return M
