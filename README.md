# yfp.nvim

> **Y**ank **F**ile **P**ath — a floating, **read-only** file browser for Neovim whose only job is to
> drop a file or folder's path into the buffer you're editing, always with forward slashes (`/`),
> even on Windows.

No more *Alt-tab → Explorer → right-click "Copy as path" → paste → fix the backslashes*. Open a
float, move with the keyboard, press `y`. Done.

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
| Alt-tab back, paste | Navigate with `j`/`k`/`l`/`h`, press `y` |
| Hand-fix every `\` → `/` | Already `/`, dropped at your cursor **and** in your clipboard |

---

## Features

- 🪟 **Floating explorer** — opens over your editor, closes back to exactly where you were.
- 🌍 **Browse anywhere** — not limited to cwd or git root; jump to any folder or **another drive**
  (`D:/`, UNC shares) without leaving the float.
- 🔒 **Strictly read-only — by construction.** `yfp` *cannot* create, rename, move, delete, or chmod
  anything. It only ever calls read-only filesystem APIs, and a CI test enforces it. Safe to poke at.
- 📋 **One job, done well:** press `y` on a file/folder and its full path is **both** inserted at your
  cursor **and** copied to your registers (`"` and `+`) — always normalized to `/`.
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
3. Jump elsewhere: `<C-g>` to type any path (e.g. `D:/projects`), `<C-d>` to list drives (Windows).
4. Press **`y`** on a file or folder. The float closes, the `/`-normalized path appears at your
   cursor, and it's in your `"`/`+` registers too.

---

## Keymaps (inside the float)

| Key | Action |
|---|---|
| `y` | **Yank** path → insert at cursor **and** set registers (`"`, `+`) |
| `Y` | Yank to registers only (no insert) |
| `gy` | Pick a path format (absolute / relative…) then yank |
| `<CR>` / `l` | Enter directory |
| `-` / `h` | Go up (drives view at a drive root) |
| `<C-g>` | Go to a typed path (any folder / drive / `~`) |
| `<C-d>` | List drives (Windows) |
| `~` | Jump to home |
| `=` | Jump to original working directory |
| `.` | Toggle hidden files |
| `/` | Fuzzy-filter the current listing *(v1.1)* |
| `q` / `<Esc>` | Close |
| `g?` | Help |

All keys are remappable — see `keymaps` in Configuration.

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
    insert = true,             -- insert at cursor in the buffer you came from
    registers = { '"', '+' },  -- also copy to these registers
    insert_position = "at_cursor",  -- "at_cursor" | "after_cursor"
    keep_insert = true,        -- re-enter insert mode if opened from insert mode
    dir_trailing_slash = false,
    default_mode = "absolute", -- "absolute" | "relative_cwd" | "relative_buffer"
                               -- | "relative_git" | "relative_custom"
  },

  source_dir = nil,            -- base directory for "relative_custom"

  icons = { enabled = true },  -- uses mini.icons / nvim-web-devicons if present; text fallback else

  keymaps = {
    yank          = "y",
    yank_register = "Y",
    yank_menu     = "gy",
    enter         = { "<CR>", "l" },
    up            = { "-", "h" },
    goto_path     = "<C-g>",
    drives        = "<C-d>",
    home          = "~",
    cwd           = "=",
    toggle_hidden = ".",
    filter        = "/",
    close         = { "q", "<Esc>" },
    help          = "g?",
  },
})
```

### Path output modes

`yank.default_mode` (and the `gy` menu) control what gets written:

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
2. A single module is allowed to touch the filesystem, and only via **read-only** `vim.uv`
   functions (`fs_scandir`, `fs_stat`, `fs_lstat`, `fs_realpath`, `fs_readlink`, `fs_access`).
3. A **CI test** greps the source and fails the build if any mutating call
   (`fs_unlink`, `fs_rename`, `fs_mkdir`, `fs_rmdir`, `fs_write`, …) ever appears.
4. It **never shells out** for filesystem work.

So there is no path — UI or code — through which `yfp` can change your files.

---

## FAQ

**Does it work without snacks/telescope/plenary?**
Yes. Zero runtime dependencies — it's pure Neovim stdlib.

**Why not just `:%s/\\/\//g` after pasting?**
Because that also rewrites any *legitimate* backslashes in your buffer. `yfp` only converts the path
it inserts, leaving the rest of your file untouched.

**Can it open/edit the file I select?**
No — by design. It's a *path* picker, not a file manager. That keeps it minimal and guarantees it
can't modify anything.

**Does `y` overwrite my clipboard?**
It sets the `"` and `+` registers by default (configurable via `yank.registers`). Set it to `{}` to
insert-only, or to `{ '"' }` to leave the system clipboard alone.

**It inserted in the wrong place / not in insert mode.**
`yfp` captures your cursor position the moment it opens and inserts there. Tune with
`yank.insert_position` and `yank.keep_insert`.

---

## Roadmap

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
2. **Read-only** — no mutating `vim.uv` calls (the CI grep will reject them).

Run `stylua` and `luacheck` before submitting. See [CLAUDE.md](./CLAUDE.md) for the developer map.

## License

MIT © hhuang91

## Acknowledgements

Prior art that informed the design: `kiyoon/telescope-insert-path.nvim` (insert-into-buffer with
relative modes), `folke/snacks.nvim` (path-copy actions), and `stevearc/oil.nvim` (floating file
UX). `yfp` is the read-only, zero-dependency, slash-normalizing intersection of these ideas.
