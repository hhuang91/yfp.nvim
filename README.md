# yfp.nvim

> **Y**ank **F**ile **P**ath — a floating, **read-only** file browser for Neovim whose only job is to
> drop a file or folder's path into the buffer you're editing, always with forward slashes (`/`),
> even on Windows.

No more *Alt-tab → Explorer → right-click "Copy as path" → paste → fix the backslashes*. Open a
float, move with the keyboard, press `p`. Done.

<!-- TODO: drop a demo GIF here once recorded -->
<!-- ![demo](./assets/demo.gif) -->

---

## Why

Pasting a real path into your buffer is a multi-step, mouse-dependent chore — especially on Windows,
where the path comes back full of `\` and a blind `:%s/\\/\//g` is unsafe if your buffer uses
backslashes for anything else. `yfp` fixes the whole loop without leaving the keyboard:

| Before | With `yfp` |
|---|---|
| Open Explorer, find the file, right-click → *Copy as path* | `<leader>fy` opens a float |
| Alt-tab back, paste | Navigate with `j`/`k`/`l`/`h`, press `p` |
| Hand-fix every `\` → `/` | Already `/`, dropped at your cursor **and** in your clipboard |

---

## Features

- 🪟 **Floating explorer** — opens over your editor, closes back to exactly where you were.
- 🌍 **Browse anywhere** — not limited to cwd or git root; jump to any folder or **another drive**
  (`D:/`, UNC shares) without leaving the float.
- 🔒 **Strictly read-only — by construction.** `yfp` *cannot* create, rename, move, delete, or chmod
  the files you browse. It only ever calls read-only filesystem APIs, and a CI test enforces it. (The
  one thing it writes is its own pinned-locations list under your Neovim data dir — never your files.)
- 📋 **One job, done well:** press `p` on a file/folder to **paste** its path at your cursor *and*
  set the `"`/`+` registers, or `y` to set the registers only (Vim-style) — always `/`-normalized.
- 📌 **Pinned locations.** Bookmark files/folders in a toggleable bottom panel, jump straight back to
  any of them, and have the list persist across sessions.
- 📂 **Open in place.** Press `o` on a file to edit it in the window you came from — handy when you
  know *where* a file is but not its name. (Opening is a `:edit` read; yfp still never writes a thing.)
- 🧩 **Zero dependencies.** No telescope, no snacks, no plenary. Pure Neovim stdlib.
- ⌨️ **Keyboard-only.** The mouse stays untouched.

---

## Requirements

- **Neovim ≥ 0.10** (0.11+ recommended; relative-path modes use `vim.fs.relpath` from 0.11 with a
  fallback).
- Works on **Windows, macOS, and Linux**. The `\`→`/` normalization is most useful on Windows but is
  applied everywhere for consistency.
- Optional: [`mini.icons`](https://github.com/echasnovski/mini.icons) or
  [`nvim-web-devicons`](https://github.com/nvim-tree/nvim-web-devicons) for filetype icons — used
  only if already installed; never required.

---

## Installation

### lazy.nvim (plain Neovim)

```lua
{
  "hhuang91/yfp.nvim",
  cmd = "YFP",
  keys = {
    { "<leader>fy", function() require("yfp").open() end, desc = "Yank file path (yfp)" },
  },
  opts = {}, -- see Configuration below; defaults are sensible
}
```

### LazyVim

Drop the spec above into `lua/plugins/yfp.lua`. `<leader>f…` is LazyVim's "find/file" group, so
`<leader>fy` ("**f**ind → **y**ank path") slots in naturally and shows up in which-key.

### Local development

Clone, then point lazy.nvim at the local copy:

```lua
{ dir = "C:/Users/you/Lib/yfp", cmd = "YFP", opts = {} }
```

---

## Quick start

1. `<leader>fy` (or `:YFP`) opens the float at the directory of the current file.
2. Move: `j`/`k` to move, `l`/`<CR>` to enter a folder, `h`/`-` to go up.
3. Jump elsewhere: `<C-g>` to type any path (e.g. `D:/projects`), `D` to list drives (Windows).
4. Press **`p`** ("paste the path") on a file or folder. The float closes, the `/`-normalized path
   appears at your cursor and is set in your `"`/`+` registers. (Or **`y`** to set the registers
   only, Vim-style — no paste.)

---

## Keymaps (inside the float)

| Key | Action |
|---|---|
| `y` | **Yank** path to registers (`"`, `+`) — Vim-style, no paste |
| `p` | **Yank and paste** the path at your cursor (also sets registers) |
| `gy` | Pick a path format (absolute / relative…), then **yank** to registers |
| `gp` | Pick a path format, then **yank and paste** at the cursor |
| `<CR>` / `l` | Enter directory |
| `o` | Open the selected **file** in the window you launched yfp from |
| `-` / `h` | Go up (drives view at a drive root) |
| `<C-g>` | Go to a typed path (any folder / drive / `~`) |
| `D` | List drives (Windows) |
| `~` | Jump to home |
| `=` | Jump to original working directory |
| `.` | Toggle hidden files |
| `P` | Toggle the **pinned locations** panel (open / close) |
| `<Tab>` | Switch focus between the main view and the panel |
| `a` | **Pin** the item under the cursor *(while the panel is open)* |
| `d` | Remove the pin under the cursor *(in the panel)* |
| `<CR>` / `l` | *(in the panel)* jump the main view to that pin |
| `/` | Fuzzy-filter the current listing *(v1.1)* |
| `q` / `<Esc>` | Close |
| `g?` | Help |

`<C-d>` / `<C-u>` keep their native half-page scroll inside the float. All keys are remappable — see
`keymaps` in Configuration.

---

## Pinned locations

Keep a short list of folders (and files) you reach for often, and jump back to them without
re-navigating:

1. Press **`P`** to toggle the **pinned** panel along the bottom of the float. `P` both opens it
   (leaving focus in the main view) and closes it — it's the only key that controls the panel's
   visibility.
2. With the panel open, put the cursor on a file or folder in the main view and press **`a`** to pin
   it (on the `../` row, `a` pins the current folder). Pinning works only while the panel is open.
3. Press **`<Tab>`** to switch focus between the main view and the panel — it never opens or closes
   the panel (that's `P`'s job).
4. In the panel, press **`<CR>`** / **`l`** on a pin to send the main view there — a folder opens, a
   file opens its folder with the cursor on the file — and focus hops back to the main view (the panel
   stays open). Press **`o`** on a *file* pin to open it in your origin window instead of jumping, or
   **`d`** to remove the pin under the cursor.

The list is saved to `stdpath("data")/yfp/pins.json` (e.g. `~/AppData/Local/nvim-data/yfp/pins.json`
on Windows) and reloaded on the next session — it's the **only** file `yfp` ever writes, and it's
yfp's own state, never your project files. Set `pins.file` to relocate it, or `pins.enabled = false`
to turn the feature off. Stale pins (deleted/unmounted paths) are shown with a `[missing]` tag and
left alone until you remove them.

---

## Configuration

Defaults shown; pass only what you want to override.

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

  show_hidden = true,
  group_dirs_first = true,
  sort = "name",               -- "name" | "type"
  resolve_symlinks = false,    -- yank the symlink path, not its target

  yank = {
    separator = "/",           -- "/" force forward slashes | "\\" | "os" (native)
    registers = { '"', '+' },  -- registers set by BOTH yank actions
    insert_position = "after_cursor",  -- "at_cursor" | "after_cursor" (paste action)
    keep_insert = true,        -- re-enter insert mode if opened from insert mode
    dir_trailing_slash = false,
    default_mode = "absolute", -- "absolute" | "relative_cwd" | "relative_buffer"
                               -- | "relative_git" | "relative_custom"
  },

  source_dir = nil,            -- base directory for "relative_custom"

  pins = {                     -- pinned locations (toggleable bottom pane)
    enabled = true,
    file    = nil,             -- default: stdpath("data").."/yfp/pins.json"
    height  = 0.25,            -- pane height: ratio of the window, or integer rows
    title   = " pinned ",
  },

  icons = { enabled = true },  -- uses mini.icons / nvim-web-devicons if present; text fallback else

  keymaps = {
    yank                = "y",    -- registers only (Vim-like)
    yank_and_paste      = "p",    -- insert at the cursor + set registers
    yank_menu           = "gy",   -- pick a path format, then yank to registers
    yank_and_paste_menu = "gp",   -- pick a path format, then yank + paste
    enter               = { "<CR>", "l" },
    up                  = { "-", "h" },
    open                = "o",      -- open the selected file in the origin window
    goto_path           = "<C-g>",
    drives              = "D",
    home                = "~",
    cwd                 = "=",
    toggle_hidden       = ".",
    filter              = "/",
    close               = { "q", "<Esc>" },
    help                = "g?",
    pin_toggle          = "P",      -- toggle the pinned panel open/closed
    pin_focus           = "<Tab>",  -- switch focus between the main view and the panel
    pin_add             = "a",      -- pin the item under the cursor (panel must be open)
    pin_remove          = "d",      -- remove the pin under the cursor (in the panel)
  },
})
```

### Path output modes

`yank.default_mode` (and the `gy` / `gp` menus) control what gets written:

| Mode | Result | Status |
|---|---|---|
| `absolute` | `C:/Users/you/project/src/main.lua` | v1.0 |
| `relative_cwd` | path relative to Neovim's working directory | v1.2 |
| `relative_buffer` | path relative to the file you're editing | v1.2 |
| `relative_git` | path relative to the nearest `.git` root | v1.2 |
| `relative_custom` | path relative to `source_dir` / `set_source_dir()` | v1.2 |

Whatever the mode, the result is **always** run through the separator rule last, so a relative path
can never sneak a `\` back in.

---

## Commands & API

```vim
:YFP            " open at default_start
:YFP D:/projects  " open at a specific path
```

```lua
local yfp = require("yfp")
yfp.open({ cwd = "D:/projects" })  -- open somewhere specific
yfp.toggle()
yfp.is_open()
yfp.set_source_dir("C:/Users/you/project")  -- base for relative_custom
```

---

## How it stays read-only & safe

`yfp` is read-only *by construction*, not by hiding buttons:

1. The explorer buffer is **non-modifiable** (`buftype=nofile`, `modifiable=false`).
2. A single module is allowed to touch the **browsed** filesystem, and only via **read-only** `vim.uv`
   functions (`fs_scandir`, `fs_stat`, `fs_lstat`, `fs_realpath`, `fs_readlink`, `fs_access`).
3. A **CI test** greps the source and fails the build if any mutating call
   (`fs_unlink`, `fs_rename`, `fs_mkdir`, `fs_rmdir`, `fs_write`, …) ever appears.
4. It **never shells out** for filesystem work.

So there is no path — UI or code — through which `yfp` can change **your files**.

The one and only thing `yfp` writes is its own pinned-locations list at
`stdpath("data")/yfp/pins.json` — the same kind of private state Neovim keeps for sessions and shada.
That write lives entirely in one module (`persist.lua`), uses ordinary `writefile`/`mkdir` (never a
mutating `vim.uv` call), and the same CI test asserts it can only ever target a path under
`stdpath("data")`. Your project files stay untouched.

---

## FAQ

**Does it work without snacks/telescope/plenary?**
Yes. Zero runtime dependencies — it's pure Neovim stdlib.

**Why not just `:%s/\\/\//g` after pasting?**
Because that also rewrites any *legitimate* backslashes in your buffer. `yfp` only converts the path
it inserts, leaving the rest of your file untouched.

**Can it open the file I select?**
Yes — press `o` to open it in the window you launched yfp from (files only; on a folder it just says
so). That's a normal `:edit` (a read), so yfp *still* can't modify anything on disk — you edit and
save through your own buffer as usual. yfp stays a navigator, not a file *manager* (no
create/rename/move/delete).

**Do the yank keys overwrite my clipboard?**
Both `y` and `p` set the `"` and `+` registers by default (configurable via `yank.registers`). Set
it to `{ '"' }` to leave the system clipboard alone, or `{}` so only `p`'s paste happens.

**`p` pasted in the wrong place / not in insert mode.**
`yfp` captures your cursor position the moment it opens and pastes there. Tune with
`yank.insert_position` (`at_cursor` vs `after_cursor`) and `yank.keep_insert`.

---

## Roadmap

- **Recently added** — pinned locations: a toggleable bottom pane, persisted across sessions.
- **v1.1** — in-float fuzzy filter (`/`) — the "find sprinkled on top."
- **v1.2** — relative path modes + the `gy` format menu.
- **v1.3** — recursive find (async, still read-only).
- Optional — delegate content-grep to an external picker (snacks / grug-far) **if** present; never a
  hard dependency.

See [DESIGN.md](./DESIGN.md) for the full design and rationale.

---

## Contributing

Issues and PRs welcome. Please keep the two invariants intact:

1. **Zero runtime dependencies.**
2. **Read-only over the browsed filesystem** — no mutating `vim.uv` calls and no shell-outs (the CI
   grep will reject them). The sole permitted write is yfp's own `pins.json`, confined to
   `persist.lua` and `stdpath("data")` — the CI grep enforces that too.

Run `stylua` and `luacheck` before submitting. See [CLAUDE.md](./CLAUDE.md) for the developer map.

## License

MIT © hhuang91

## Acknowledgements

Prior art that informed the design: `kiyoon/telescope-insert-path.nvim` (insert-into-buffer with
relative modes), `folke/snacks.nvim` (path-copy actions), and `stevearc/oil.nvim` (floating file
UX). `yfp` is the read-only, zero-dependency, slash-normalizing intersection of these ideas.
