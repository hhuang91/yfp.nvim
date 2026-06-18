-- yfp.path — pure path helpers. No filesystem access, no side effects.
local M = {}

local is_win = vim.fn.has("win32") == 1

--- Replace every backslash with a forward slash.
---@param p string
---@return string
function M.slashify(p)
  return (p:gsub("\\", "/"))
end

--- Apply the configured separator to a path (input may use either separator).
---@param p string
---@param sep string  "/" | "\\" | "os"
---@return string
function M.apply_separator(p, sep)
  if sep == "\\" then
    return (p:gsub("/", "\\"))
  elseif sep == "os" then
    if is_win then
      return (p:gsub("/", "\\"))
    end
    return (p:gsub("\\", "/"))
  end
  -- default "/": force forward slashes
  return (p:gsub("\\", "/"))
end

--- Join a directory and a child name with a single forward slash.
---@param dir string  absolute, forward-slash
---@param name string
---@return string
function M.join(dir, name)
  if dir == "" then
    return name
  end
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

--- Is this absolute path a filesystem root (drive root, UNC share root, or "/")?
---@param p string
---@return boolean
function M.is_root(p)
  p = M.slashify(p)
  if p == "/" then
    return true
  end
  if p:match("^%a:/?$") then -- C:  or  C:/
    return true
  end
  if p:match("^//[^/]+/[^/]+/?$") then -- //server/share
    return true
  end
  return false
end

--- Parent directory, or nil if `p` is already a root.
---@param p string
---@return string|nil
function M.parent(p)
  p = M.slashify(p)
  if M.is_root(p) then
    return nil
  end
  local trimmed = (p:gsub("/+$", ""))
  local parent = (trimmed:gsub("/[^/]*$", ""))
  if parent == "" then
    return "/" -- e.g. "/home" -> "/"
  end
  if parent:match("^%a:$") then -- "C:" -> "C:/"
    parent = parent .. "/"
  end
  return parent
end

--- Path of `target` relative to `base` (both absolute). Forward-slash result.
---@param target string
---@param base string
---@return string
function M.relative(target, base)
  target = M.slashify(target)
  base = M.slashify(base)
  if vim.fs.relpath then
    local ok, rel = pcall(vim.fs.relpath, base, target)
    if ok and rel then
      return M.slashify(rel)
    end
  end
  -- fallback: naive prefix strip
  local b = (base:gsub("/+$", "")) .. "/"
  if target:sub(1, #b):lower() == b:lower() then
    return target:sub(#b + 1)
  end
  return target
end

--- Transform an absolute path into the requested output mode (forward-slash).
--- The caller still applies the separator preference afterwards.
---@param abspath string
---@param mode string
---@param ctx table  { cwd, buf_path, source_dir }
---@return string
function M.transform(abspath, mode, ctx)
  local out
  if mode == "relative_cwd" then
    out = M.relative(abspath, ctx.cwd or vim.fn.getcwd())
  elseif mode == "relative_buffer" then
    local base = (ctx.buf_path and ctx.buf_path ~= "") and vim.fs.dirname(ctx.buf_path)
      or (ctx.cwd or vim.fn.getcwd())
    out = M.relative(abspath, base)
  elseif mode == "relative_git" then
    local root = vim.fs.root(abspath, { ".git" }) or ctx.cwd or vim.fn.getcwd()
    out = M.relative(abspath, root)
  elseif mode == "relative_custom" then
    out = ctx.source_dir and M.relative(abspath, ctx.source_dir) or abspath
  else
    out = abspath
  end
  return M.slashify(out)
end

return M
