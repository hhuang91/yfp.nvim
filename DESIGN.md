# yfp.nvim — Design

> **yfp** = **Y**ank **F**ile **P**ath. A floating, **read-only** file browser for Neovim whose
> only job is to drop a file/folder's path into the buffer you were editing — always with forward
> slashes (`/`), even on Windows.

---

## 1. Problem statement

Inserting a real filesystem path into the buffer you're editing is needlessly painful on Windows:

1. Leave the editor, open Explorer, find the file, right-click → *Copy as path*.
2. Return to Neovim, paste — you're now holding the mouse and you've lost your place.
3. The pasted path uses `\`, so you hand-fix every separator (and a blind `:%s/\\/\//g` is unsafe
   when the buffer legitimately contains backslashes for other reasons).

`yfp` collapses all three steps into: open a float, navigate with the keyboard, press `p`. The path
lands at your cursor with `/` separators and is also copied to your registers — no mouse, no manual
slash surgery, no leaving the keyboard.

---

## 2. Goals and non-goals

### Goals
- **Floating file explorer** that browses **anywhere** on the machine — not limited to cwd or git
  root — including other drives (`D:/`, UNC shares) on Windows.
- **Strictly read-only.** The plugin must be *incapable* of modifying the filesystem, by
  construction (not merely by disabling commands).
- **Core action:** press `p` on a file or folder → its full path goes **both** into the origin
  buffer at the cursor **and** into registers (or `y` for registers only), always normalized to `/`.
- **Zero runtime dependencies.** No telescope, no snacks, no plenary. Pure Neovim stdlib.
- **Keyboard-only.** Never requires the mouse.

### Non-goals (v1)
- No create / rename / move / delete / chmod — ever. (See §8, Read-only guarantee.)
- No file *preview* or *opening* files for editing (it's a path picker, not a file manager).
- No tree view with persistent expand/collapse state — it's a single-directory pane you navigate
  in/out of (simpler, faster, predictable).
- No fuzzy *grep* of file contents in core (may be delegated to an external picker later — §10).

---

## 3. Prior art & gap analysis

The pieces exist in the ecosystem, but nothing combines them for a snacks-based Windows setup:

| Tool | Floats | Browse anywhere | Read-only | Inserts into buffer | `\`→`/` | Verdict |
|---|:--:|:--:|:--:|:--:|:--:|---|
| `snacks.explorer` `copy_file_path` | ✅ | ✅ | ❌ (editable) | ❌ (register only) | ❌ (`fnamemodify` keeps `\`) | Copies, doesn't insert; not read-only |
| `kiyoon/telescope-insert-path.nvim` | ✅ | ✅ | ✅ | ✅ | ❌ | Closest in spirit, but **needs telescope** & no slash fix |
| `oil.nvim --float` | ✅ | ✅ | ❌ (edit-as-buffer) | ❌ | ❌ | Editable file manager |
| `neo-tree` float / `mini.files` | ✅ | ✅ | ❌ | ❌ | ❌ | Editable file managers |

**Gap:** browse-anywhere **+** read-only-by-construction **+** insert-into-buffer **+** forced `/`.
`yfp` fills exactly that gap with no dependencies.

---

## 4. Design decisions (locked)

| # | Decision | Choice | Rationale |
|---|---|---|---|
| D1 | Architecture | **Standalone, zero-dependency** | Read-only *by construction*; cleanest public repo; works in any Neovim 0.10+ config; full control over yank semantics and slash handling. |
| D2 | Yank actions | `p` = paste at cursor **and** set registers; `y` = registers only (Vim-like) | `p` matches "yanks its full path into your buffer" (no extra paste step); `y` mirrors native Vim yank and composes with yanky.nvim. Split from an earlier single `y`=both during keymap tuning, which also retired the redundant `yank.insert` flag. |
| D3 | Slash handling | Explicit final `gsub("\\","/")` on output | Predictable and literal — does exactly what the user asked. We deliberately do **not** rely on `vim.fs.normalize` for output (it *also* expands `~`/`$VAR` and collapses `..`, which can surprise). |
| D4 | Read-only enforcement | Whitelist of read-only `vim.uv` calls + non-modifiable buffer + CI grep | "Safe to toy around" is a headline feature, so it's guaranteed and tested, not assumed. |
| D5 | Min Neovim | **0.10** (0.11+ recommended) | `vim.uv`, `nvim_open_win`, scratch buffers exist in 0.10. Relative modes that use `vim.fs.relpath` (0.11+) degrade gracefully with a manual fallback. (User is on 0.12.2.) |

---

## 5. Architecture overview

A single active explorer instance (singleton — you never need two open for this task). Pure Lua,
split for clarity; can be collapsed if desired.

```
                       :YFP [path]   /   require("yfp").open()
                                 │
                                 ▼
   ┌──────────────────────────────────────────────────────────────┐
   │  init.lua        public API + setup(); owns the singleton      │
   └───────┬───────────────┬───────────────┬───────────────┬───────┘
           │               │               │               │
           ▼               ▼               ▼               ▼
   ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
   │ config.lua   │ │ explorer.lua │ │ actions.lua  │ │ path.lua     │
   │ defaults +   │ │ float win +  │ │ yank / nav   │ │ slash + rel  │
   │ user merge   │ │ buffer + draw│ │ handlers     │ │ transforms   │
   └──────────────┘ └──────┬───────┘ └──────┬───────┘ └──────────────┘
                           │                │
                           ▼                ▼
                    ┌──────────────┐  (reads origin buf/cursor captured at open)
                    │ fs.lua       │
                    │ READ-ONLY    │
                    │ vim.uv scan  │
                    └──────────────┘

   plugin/yfp.lua  → defines :YFP, guards double-load
   doc/yfp.txt     → :help yfp
```

| Module | Responsibility | May touch the filesystem? |
|---|---|---|
| `init.lua` | `setup`, `open`, `close`, `toggle`, `is_open`, `set_source_dir`, holds singleton state | No |
| `config.lua` | Default options table + deep-merge of user opts; type annotations | No |
| `explorer.lua` | Create/destroy the float window + scratch buffer; render lines; manage cursor; install buffer-local keymaps; capture origin (win/buf/cursor/mode) | No |
| `actions.lua` | `yank` (registers), `yank_and_paste` (paste + registers), `yank_menu`, `enter`, `up`, `goto_path`, `drives`, `toggle_hidden` | No (delegates reads to `fs`) |
| `fs.lua` | The **only** module that calls `vim.uv` — and only its **read** functions | **Read-only** |
| `path.lua` | Pure functions: join, slash-normalize, relative-to-X computation | No |

---

## 6. Data model

```lua
---@class yfp.Entry
---@field name string          -- basename for display, e.g. "init.lua"
---@field path string          -- absolute, forward-slash, e.g. "C:/Users/me/init.lua"
---@field type "file"|"directory"|"link"
---@field is_dir boolean

---@class yfp.State
---@field cwd string           -- current directory (absolute, forward-slash)
---@field entries yfp.Entry[]  -- sorted: dirs first, then files; case-insensitive
---@field win integer|nil      -- floating window id
---@field buf integer|nil      -- scratch buffer id
---@field origin_win integer   -- window to return focus to
---@field origin_buf integer   -- buffer to insert the path into
---@field origin_cursor integer[]  -- {row(1-based), col(0-based byte)} at open time
---@field origin_mode string   -- "i"|"n"... the mode YFP was launched from
---@field filter string        -- in-float fuzzy filter (v1.1)
---@field show_hidden boolean  -- runtime toggle
```

**Internal path invariant:** every path stored in state is **absolute and forward-slash**. Paths are
canonicalized once on entry (join cwd + name, then `gsub("\\","/")`). Output re-applies the slash
rule as a guaranteed last step (D3) so relative computations can never reintroduce `\`.

The `../` row is a synthetic pseudo-entry: selecting it goes up; it is **not** yankable.

---

## 7. Key flows

### 7.1 Open
1. Capture origin: `origin_win`, `origin_buf`, `origin_cursor = nvim_win_get_cursor(0)`,
   `origin_mode = nvim_get_mode().mode`.
2. Resolve start dir: explicit arg → else `config.default_start` (`"file_dir"` by default → the
   directory of the current file; falls back to cwd).
3. `fs.scandir(cwd)` → entries; sort.
4. Create scratch buffer (`buftype=nofile`, `bufhidden=wipe`, `swapfile=false`, `modifiable=false`,
   `filetype=yfp`); render; open float via `nvim_open_win`; install buffer-local keymaps; place
   cursor on first real entry.

### 7.2 Navigate
- **Enter dir** (`<CR>`/`l`): if entry is a directory → set `cwd`, rescan, re-render, cursor to top.
- **Up** (`-`/`h`): `cwd = dirname(cwd)`; at a drive root, show the **drives view** instead.
- **Goto** (`<C-g>`): `vim.ui.input` → type any absolute path / `~` / `D:/projects` → normalize → cd.
- **Drives** (`D`, Windows): probe `A:/`…`Z:/` with `vim.uv.fs_stat`; list the ones that exist.
  (`<C-d>`/`<C-u>` are left unmapped so they keep their native half-page scroll.)
- **Toggle hidden** (`.`): flip `show_hidden`, rescan view.

### 7.3 Yank — `y` (registers) and `p` (registers + paste)

Both keys share one worker, `do_yank(mode, insert)`: `y` calls it with `insert=false`, `p` with
`insert=true`.
```
entry = entry_under_cursor()           -- ignore the "../" pseudo-row
abspath = entry.path                   -- already absolute + forward-slash
out = path.transform(abspath, cfg.yank.default_mode, cfg)   -- relative if configured...
out = path.apply_separator(out, cfg.yank.separator)   -- GUARANTEED slash normalize (D3)
if entry.is_dir and cfg.yank.dir_trailing_slash then out = out .. "/" end

-- (1) registers  (both actions)
for _, r in ipairs(cfg.yank.registers) do vim.fn.setreg(r, out) end   -- default {'"','+'}

-- `y` ends here (registers only); only `p` continues to paste:
if not insert then close_float() return end

-- (2) `p`: paste at the ORIGIN cursor
close_float()                          -- restores focus to origin_win
if nvim_buf_is_valid(origin_buf) and buf_is_modifiable(origin_buf) then
  local row = origin_cursor[1] - 1
  local col = origin_cursor[2]
  nvim_buf_set_text(origin_buf, row, col, row, col, { out })   -- single line, no newline
  nvim_win_set_cursor(origin_win, { row + 1, col + #out })     -- cursor after the path
else
  notify("yfp: origin buffer not writable — path copied to registers only")
end
```
- **Insert position** is configurable: `at_cursor` (drops exactly where the cursor was,
  as if typed) or `after_cursor` (default — paste-like, mimics `p`).
- If launched from **insert mode**, optionally `startinsert` afterward (`cfg.yank.keep_insert`).
- `gy` = pick a path mode via `vim.ui.select`, then yank-and-paste.

---

## 8. Read-only guarantee (a headline feature)

Three independent layers make modification *impossible*, not merely *disabled*:

1. **Non-modifiable buffer.** The explorer buffer is `modifiable=false`, `buftype=nofile`. There is
   no path through the UI to edit the filesystem the way oil/mini.files intentionally allow.
2. **Read-only `vim.uv` whitelist.** `fs.lua` is the *only* module permitted to call `vim.uv`, and
   only these **read** functions:
   `fs_scandir`, `fs_scandir_next`, `fs_stat`, `fs_lstat`, `fs_realpath`, `fs_readlink`, `fs_access`.
   It **must never** call any mutating call:
   `fs_open`(write), `fs_write`, `fs_unlink`, `fs_mkdir`, `fs_mkdtemp`, `fs_rmdir`, `fs_rename`,
   `fs_ftruncate`, `fs_chmod`, `fs_fchmod`, `fs_chown`, `fs_link`, `fs_symlink`, `fs_copyfile`,
   `fs_utime`, `fs_sendfile`.
3. **CI enforcement.** A test greps the source tree and fails if any mutating call appears, so a
   future change can't silently break the invariant. (See §13.)

We also never shell out (`system`/`jobstart`) for filesystem work — drive enumeration uses `fs_stat`
probing, not `wmic`/`fsutil` — so there is no escape hatch around the whitelist.

---

## 9. Configuration schema (defaults)

```lua
require("yfp").setup({
  window = {
    width = 0.7,            -- ratio of columns (or integer for absolute cols)
    height = 0.7,           -- ratio of lines  (or integer for absolute lines)
    border = "rounded",
    title = " yfp ",
    title_pos = "center",
  },

  default_start = "file_dir",  -- "file_dir" | "cwd" | "git_root" | "home"

  -- filesystem (display only — all reads are read-only)
  show_hidden = true,
  group_dirs_first = true,
  sort = "name",               -- "name" | "type"
  resolve_symlinks = false,    -- yank the symlink path, not its target

  -- the yank actions (y = registers; p = registers + paste)
  yank = {
    separator = "/",           -- "/" force forward slashes | "\\" | "os" (native)
    registers = { '"', '+' },  -- D2: registers set by both actions (unnamed + system clipboard)
    insert_position = "at_cursor",  -- "at_cursor" | "after_cursor" (paste action)
    keep_insert = true,        -- re-enter insert mode if YFP was opened from insert mode
    dir_trailing_slash = false,
    default_mode = "absolute", -- "absolute" | "relative_cwd" | "relative_buffer"
                               -- | "relative_git" | "relative_custom"
  },

  source_dir = nil,            -- base for "relative_custom" (also via set_source_dir())

  icons = { enabled = true },  -- uses mini.icons / nvim-web-devicons IF present; text fallback else

  keymaps = {                  -- buffer-local, active only inside the float
    yank           = "y",      -- registers only (Vim-like)
    yank_and_paste = "p",      -- insert at cursor + set registers
    yank_menu      = "gy",
    enter          = { "<CR>", "l" },
    up             = { "-", "h" },
    goto_path      = "<C-g>",
    drives         = "D",
    home           = "~",
    cwd            = "=",
    toggle_hidden  = ".",
    filter         = "/",      -- v1.1 in-float fuzzy filter
    close          = { "q", "<Esc>" },
    help           = "g?",
  },
})
```

`icons.enabled` does runtime feature-detection (`pcall(require, "mini.icons")` then
`nvim-web-devicons`); if neither is installed it falls back to plain glyphs — preserving the
zero-dependency promise.

---

## 10. Roadmap (post-v1)

| Stage | Feature | Notes |
|---|---|---|
| v1.0 | Read-only float explorer · browse anywhere · `y`=registers / `p`=paste · `/` normalize · drives view | Core. No deps. |
| v1.1 | **In-float fuzzy filter** (`/`) | "find sprinkled on top." Filters the current dir listing in-place; pure Lua, no deps. |
| v1.2 | **Relative path modes** + `gy` menu | `relative_cwd` / `relative_buffer` / `relative_git` / `relative_custom`. Uses `vim.fs.relpath` (0.11+) with a manual fallback. This is the user's "advanced" feature. |
| v1.3 | **Recursive find** | Async `vim.uv` walk under cwd → flat filtered list, still read-only, still `y`. Guard with max depth/results to stay snappy. |
| opt. | **External picker / grep delegation** | If `snacks.nvim` (or `grug-far`, both already installed in this config) is detected, optionally hand off content-grep. Strictly optional; never a hard dep (D1). |

---

## 11. Risks & edge cases

| Case | Handling |
|---|---|
| Permission-denied directory | `fs.scandir` returns an error → notify, stay in current dir. |
| Huge directory (10k+ entries) | v1 renders synchronously with a soft cap + notice; v1.3 moves to async chunked scan. |
| UNC paths `//server/share` | `vim.fs.dirname`/join handle them; drive view is Windows-local only. Documented as best-effort. |
| Symlinks / junctions | Shown; followed only if `resolve_symlinks`. Recursive find tracks realpaths to avoid loops. |
| Origin buffer not modifiable (terminal, help, another float) | Skip insert, set registers, notify. |
| Launched from insert mode | Cursor captured pre-command; insert at captured col; `startinsert` if `keep_insert`. |
| Paths with spaces / multibyte | `nvim_buf_set_text` is byte-safe; optional quoting is a future config, not v1. |
| yanky.nvim history | `setreg` doesn't push to yanky's ring; optional enhancement to fire `TextYankPost` or call yanky API (documented, not v1). |
| `../` pseudo-row | Not yankable; `y`/`p` on it is a no-op + hint. |

---

## 12. Public API & commands

```lua
local yfp = require("yfp")
yfp.setup(opts?)            -- optional; sane defaults
yfp.open(opts?)             -- opts: { cwd?, mode? }  e.g. yfp.open({ cwd = "D:/projects" })
yfp.close()
yfp.toggle()
yfp.is_open()               -- boolean
yfp.set_source_dir(dir)     -- base for relative_custom
yfp.yank_under_cursor(mode?)           -- programmatic yank to registers
yfp.yank_and_paste_under_cursor(mode?) -- programmatic yank + paste
```

Command: `:YFP [path]` — open at `path`, else `default_start`.

Suggested LazyVim mapping (add in `lua/plugins/yfp.lua`):
```lua
{ "<leader>fy", function() require("yfp").open() end, desc = "Yank file path (yfp)" }
```

---

## 13. Testing strategy

- **Pure unit tests** (`path.lua`) with plenary/busted in headless Neovim: slash normalization,
  join at drive roots (`C:/` not `C://`), each relative mode, trailing-slash rule.
- **Read-only invariant test:** grep the `lua/` tree; fail if any mutating `vim.uv` call (§8 list)
  appears outside an allow-comment. Runs in CI on every push.
- **Integration smoke test:** headless Neovim opens a temp dir, drives the keymaps, asserts the
  origin buffer received the expected `/`-normalized text and the registers were set.
- **CI:** `stylua --check`, `luacheck`, the invariant grep, headless tests. Matrix includes Windows.

---

## 14. Open questions (non-blocking)

1. Default `<leader>fy` vs. a `<leader>` + which-key group of its own (`<leader>y…`)? — pick at install.
2. Should `y` on a directory default to a trailing slash? Currently `false`; revisit after dogfooding.
3. yanky.nvim ring integration — worth the coupling, or leave as registers only? Lean: leave it.

---

## 15. Decisions log

- **2026-06-17** — D1 *standalone, zero-dependency* chosen over a snacks layer: read-only by
  construction and a clean public repo outweigh getting find/grep "for free." Find/grep becomes an
  optional built-in (v1.1) with optional external delegation (never a hard dep).
- **2026-06-17** — D2 yank actions: `p` = paste at cursor *and* set `{'"','+'}` registers; `y` =
  registers only (Vim-like). Split from an earlier single `y`=both during keymap tuning; drives moved
  off `<C-d>` (LazyVim scroll) to `D`; the now-redundant `yank.insert` flag was removed.
- **2026-06-17** — D3 output slash handling is an explicit final `gsub("\\","/")`, not
  `vim.fs.normalize`, to stay literal and avoid surprising `~`/`$VAR`/`..` expansion.
