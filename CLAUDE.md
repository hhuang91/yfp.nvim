# CLAUDE.md

Guidance for Claude Code (and human contributors) working in this repository.

## What this is

`yfp.nvim` (**Y**ank **F**ile **P**ath) is a **floating, read-only file browser** for Neovim. Its
single purpose: let the user browse the filesystem from a float and press `p` on a file/folder to
drop that path **both** into the buffer they came from (at the cursor) **and** into registers (or `y`
for registers only) — always normalized to forward slashes (`/`), even on Windows.

It is **standalone and zero-dependency** (pure Neovim stdlib). Full rationale and the locked design
decisions are in [DESIGN.md](./DESIGN.md); the user-facing docs are in [README.md](./README.md).

## Golden rules (do not break these)

1. **Zero runtime dependencies.** Never `require` snacks/telescope/plenary/nui at load time. Optional
   integrations (icons, external pickers) must be `pcall`-detected at runtime and degrade to a
   built-in fallback. If you're about to add a `dependencies = {...}` entry, stop.
2. **Read-only by construction — over the filesystem you browse.** Only `lua/yfp/fs.lua` may call
   `vim.uv`, and only these **read** functions: `fs_scandir`, `fs_scandir_next`, `fs_stat`,
   `fs_lstat`, `fs_realpath`, `fs_readlink`, `fs_access`. **Never** add a mutating call (`fs_open` for
   write, `fs_write`, `fs_unlink`, `fs_mkdir`, `fs_mkdtemp`, `fs_rmdir`, `fs_rename`, `fs_ftruncate`,
   `fs_chmod`, `fs_fchmod`, `fs_chown`, `fs_link`, `fs_symlink`, `fs_copyfile`, `fs_utime`,
   `fs_sendfile`). The explorer buffer stays `modifiable=false`. **Never shell out** (`vim.fn.system`,
   `jobstart`) for filesystem work. **The ONE permitted write** is yfp's own pins state file, and it
   lives entirely in `lua/yfp/persist.lua`: it may call `vim.fn.writefile`/`vim.fn.mkdir`, but **only**
   on a path rooted at `stdpath("data")` (decision D6). No other module may write, and `persist.lua`
   may never touch a browsed path. CI greps for all of this — see "Testing".
3. **Output is always slash-normalized as the final step.** Every path written to a buffer or
   register passes through `gsub("\\", "/")` **last** (after any relative computation). Do **not**
   replace this with `vim.fs.normalize` for output — normalize also expands `~`/`$VAR` and collapses
   `..`, which would silently change paths the user didn't ask to change (decision D3).
4. **Internal paths are absolute + forward-slash.** Canonicalize on entry; never store a `\` path in
   `state`.
5. **Cross-platform.** Guard Windows-only logic (drive view, `C:` roots) behind
   `vim.fn.has("win32") == 1`. Don't assume `/` *or* `\` when parsing — use `vim.fs.dirname`,
   `vim.fs.basename`, and the project's `path.join`.

## Architecture map

```
lua/yfp/
  init.lua       Public API (setup/open/close/toggle/is_open/set_source_dir) + singleton state.
  config.lua     Default options + deep-merge of user opts. Type annotations (---@class yfp.Config).
  explorer.lua   Float window(s) + scratch buffer lifecycle; render; cursor; buffer-local keymaps;
                 captures origin (win/buf/cursor/mode) at open; owns the bottom "pinned" pane
                 (second float). NO filesystem writes.
  actions.lua    Handlers: yank (registers), yank_and_paste (paste + registers),
                 yank_menu/yank_and_paste_menu (gy/gp format pickers), enter, open_entry (o, :edit),
                 up, goto_path, drives, toggle_hidden, pin_add/pin_remove/pin_jump. Reads via fs.lua.
  fs.lua         THE ONLY module that calls vim.uv — read-only functions only.
  path.lua       Pure functions: join, slash-normalize, relative-to-{cwd,buffer,git,custom}.
  pins.lua       In-memory pinned-locations list: add/remove/dedupe. NO direct I/O (delegates).
  persist.lua    THE ONLY module that WRITES — and only yfp's own pins.json under stdpath("data").
plugin/yfp.lua   Defines :YFP, guards double-load (vim.g.loaded_yfp).
doc/yfp.txt      :help yfp.
```

State shape and flows are documented in DESIGN.md §6–§7. Key fields: `cwd`, `entries`, `win`, `buf`,
`pin_win`, `pin_buf`, `pin_rows`, `closing`, `origin_win`, `origin_buf`,
`origin_cursor` (`{row(1-based), col(0-based byte)}`), `origin_mode`. The pinned pane is a second
float beneath the main one; closing the main float tears both down, closing only the pane restores
the main float to full height (a single `WinClosed` handler arbitrates by window id).

## The yank flow (most important code path)

Both yank keys share one worker, `do_yank(mode, insert)` in `actions.lua`: `y` → `insert=false`
(registers only), `p` → `insert=true` (registers + paste). It must, in order: resolve the entry's
absolute path → apply the configured path mode → **then** `gsub("\\","/")` → set each register in
`cfg.yank.registers` → close the float (restoring focus to `origin_win`) → if `insert` and the origin
buffer is valid+modifiable, paste via `nvim_buf_set_text(origin_buf, row, col, row, col, { out })`
and move the cursor to `col + #out`. If the origin buffer isn't writable, skip the paste, keep the
registers, and `notify`. The `../` pseudo-row is never yankable. See DESIGN.md §7.3 for the reference
pseudocode.

## Local development

There is no build step — it's Lua loaded by Neovim.

- **Run it against this checkout** with lazy.nvim: `{ dir = "<abs path to repo>", cmd = "YFP", opts = {} }`.
- **Minimal repro** (headless or `nvim -u`): a tiny init that `prepend`s `lua/` to `runtimepath` and
  calls `require("yfp").setup({})`, then `:YFP`.
- After Lua changes, `:Lazy reload yfp.nvim` or restart Neovim (no recompile).

## Testing & CI

- **Pure unit tests** target `path.lua` (slash normalization; join at drive root → `C:/` not `C://`;
  each relative mode; trailing-slash rule). Headless Neovim + plenary/busted.
- **Read-only invariant test** (`scripts/check_no_writes.sh`, must stay green): greps `lua/` for the
  mutating `vim.uv` calls listed in Golden Rule #2 and for shell-outs (banned everywhere); bans
  host-side writes (`vim.fn.writefile`/`mkdir`/`delete`/`rename`, `io.open`) **everywhere except
  `persist.lua`**; and asserts `persist.lua` derives its path from `stdpath("data")` and nothing else.
- **Integration smoke test** (`tests/func.lua`): open a temp dir headless, drive the keymaps, assert
  the origin buffer got the expected `/`-normalized text and registers were set; then exercise the
  pinned pane (pin → toggle → jump → remove) and a persistence round-trip against a temp pins file.
- **CI:** `stylua --check`, `luacheck`, the invariant grep, headless tests — Windows in the matrix
  (this plugin's reason for existing is Windows path handling).

## Playbooks (common changes)

- **Add a keymap:** add a default to `config.keymaps`, document it in README's keymap table and
  `doc/yfp.txt`, and wire the handler in `explorer.lua`'s keymap installer → `actions.lua`. Pass a
  `desc` (third arg to the installer's `map`) — that's what which-key/`:map` display; a blank `desc`
  shows up as an empty which-key entry.
- **Add a path mode:** implement a pure function in `path.lua`, add it to `yank.default_mode` and the
  `gy`/`gp` menu list (`do_menu` in `actions.lua`), ensure the final `gsub("\\","/")` still runs, add
  a unit test. Update both docs' mode tables.
- **Add a config option:** default in `config.lua` with a `---@field` annotation, merge logic if
  non-trivial, document in README's config block + DESIGN.md §9.
- **Touch the filesystem:** only inside `fs.lua`, only read-only calls. If you think you need a write
  call, you've misunderstood the project — re-read Golden Rule #2.
- **Persist anything:** route every write through `persist.lua`, always under `stdpath("data")`, via
  `vim.fn.writefile`/`mkdir` (never `vim.uv` mutators). Add the file to the allow/assert checks in
  `scripts/check_no_writes.sh` if it's a new writer (prefer extending `persist.lua` instead).

## Gotchas

- `nvim_win_get_cursor` returns `{row(1-based), col(0-based byte)}`; `nvim_buf_set_text` wants
  **0-based** row. Convert (`row - 1`). Columns are **byte** offsets — fine for UTF-8 insert.
- Joining at a drive root: `C:/` + `name` must not become `C://name`. Use `path.join`.
- `vim.fs.relpath` needs Neovim 0.11+; provide a manual fallback so 0.10 still works.
- `setreg` does **not** push to yanky.nvim's history (it hooks `TextYankPost`). That's acceptable;
  don't add a yanky dependency to fix it.
- Don't let recursive find (future) loop on symlink/junction cycles — track realpaths.
- Drive enumeration is `fs_stat` probing `A:/`…`Z:/`, **not** shelling out — keep it that way.
- Two floats: the pinned pane is created *after* the main float, so its `WinClosed` can't be a fixed
  `pattern` — one handler keys off `args.match`. The `state.closing` flag suppresses the
  pane-teardown-relayout while `M.close`/`M.cleanup` are tearing everything down (avoids a flash).
- `nvim_win_set_config` on an existing float keeps `border`/`title` when you omit them, but you
  **must** pass `relative` to move it. `relayout()` keeps the combined footprint constant — opening
  the pane shrinks the main list rather than growing the block — so geometry stays centered.
- Pins store `{ path, is_dir }`; comparison is slash-normalized, trailing-slash-stripped, lowercased
  (so `C:/Tmp` and `c:\tmp\` dedupe). Don't auto-delete stale pins — render tags them `[missing]`.

## Decisions log (mirror of DESIGN.md §15)

- **2026-06-17** — Standalone, zero-dependency over a snacks layer (read-only by construction + clean
  public repo win over getting find/grep "for free").
- **2026-06-17** — Two yank keys: `y` = registers only (Vim-like), `p` = registers + paste. (Split
  from an earlier single `y`=both during keymap tuning; removed the redundant `yank.insert` flag.)
- **2026-06-17** — Output slash handling is an explicit final `gsub("\\","/")`, not
  `vim.fs.normalize` (stay literal; avoid `~`/`$VAR`/`..` surprises).
- **2026-06-18** — D6: pinned locations persist to yfp's **own** state file
  (`stdpath("data")/yfp/pins.json`), written only by `persist.lua`. The read-only guarantee is scoped
  to the *browsed* filesystem; writing our own state file (like sessions/shada) is allowed and the CI
  grep now proves the write target is confined to `stdpath("data")`. UI form: a toggleable **bottom
  pane** (second float). See DESIGN.md §15.
- **2026-06-18** — D7: `o` opens the selected file in the origin window (picker-style), from the main
  view or the pinned panel. This is a `:edit` (a read) — it does **not** weaken the read-only
  guarantee (yfp's code still calls no write API; the CI grep is unaffected). It relaxes only the
  scope non-goal "no opening files"; yfp stays a navigator, not a file manager. See DESIGN.md §7.5.

## Style

- Format with `stylua` (config in `stylua.toml`), lint with `luacheck`.
- Lua module pattern: `local M = {} … return M`. Annotate public functions with `---@`. Prefer
  `vim.api`/`vim.uv`/`vim.fs` over Vimscript-era `vim.fn.*` where an API equivalent exists.
- Keep modules small and single-purpose; the architecture map above is the contract.
