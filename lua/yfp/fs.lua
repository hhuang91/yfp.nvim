-- yfp.fs — the ONLY module that touches the filesystem, and only via read-only
-- libuv calls. Never add a mutating call here (see CLAUDE.md, Golden Rule #2).
local uv = vim.uv or vim.loop
local path = require("yfp.path")

local M = {}

---@class yfp.Entry
---@field name string
---@field path string
---@field type "file"|"directory"|"link"
---@field is_dir boolean

--- Read a directory. Returns (entries, nil) on success or (nil, errmsg) on failure.
---@param dir string
---@param opts table|nil  { show_hidden: boolean }
---@return yfp.Entry[]|nil, string|nil
function M.scandir(dir, opts)
  opts = opts or {}
  dir = path.slashify(dir)
  local handle, err = uv.fs_scandir(dir)
  if not handle then
    return nil, err or ("cannot read directory: " .. dir)
  end
  local entries = {}
  while true do
    local name, t = uv.fs_scandir_next(handle)
    if not name then
      break
    end
    if opts.show_hidden or name:sub(1, 1) ~= "." then
      local full = path.join(dir, name)
      local is_dir, kind
      if t == "directory" then
        is_dir, kind = true, "directory"
      elseif t == "file" then
        is_dir, kind = false, "file"
      else
        local st = uv.fs_stat(full) -- resolve link / unknown (read-only)
        is_dir = st ~= nil and st.type == "directory"
        kind = (t == "link") and "link" or (st and st.type) or "file"
      end
      entries[#entries + 1] = {
        name = name,
        path = full,
        type = is_dir and "directory" or kind,
        is_dir = is_dir,
      }
    end
  end
  return entries, nil
end

--- Windows: existing drive roots, found by probing A:/ .. Z:/ with read-only fs_stat.
---@return string[]
function M.drives()
  local out = {}
  for i = string.byte("A"), string.byte("Z") do
    local root = string.char(i) .. ":/"
    if uv.fs_stat(root) then
      out[#out + 1] = root
    end
  end
  return out
end

--- True if `p` exists and is a directory.
---@param p string
---@return boolean
function M.is_dir(p)
  local st = uv.fs_stat(path.slashify(p))
  return st ~= nil and st.type == "directory"
end

return M
