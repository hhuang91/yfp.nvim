#!/usr/bin/env bash
# Enforce yfp's read-only-by-construction invariant (see CLAUDE.md Golden Rule #2,
# DESIGN.md §8 and D6).
#
# The filesystem you BROWSE is never mutated: no mutating libuv fs call and no
# shell-out may appear anywhere under lua/. The ONE thing yfp may write is its own
# pins state file under stdpath("data") -- and only from lua/yfp/persist.lua, via
# host write helpers (vim.fn.writefile / vim.fn.mkdir). This script proves all of
# that, so a future change can't silently break the guarantee.
set -euo pipefail

mutating='fs_write|fs_unlink|fs_mkdir|fs_mkdtemp|fs_rmdir|fs_rename|fs_ftruncate|fs_chmod|fs_fchmod|fs_chown|fs_fchown|fs_lchown|fs_link|fs_symlink|fs_copyfile|fs_utime|fs_futime|fs_sendfile|fs_open'
shellout='vim\.fn\.system|jobstart|uv\.spawn|io\.popen|os\.execute'
# Host-side writes (Vimscript / Lua stdlib). Allowed ONLY in persist.lua.
hostwrite='vim\.fn\.writefile|vim\.fn\.mkdir|vim\.fn\.delete|vim\.fn\.rename|vim\.fn\.appendfile|io\.open'
persist='lua/yfp/persist.lua'

status=0

# 1) Mutating libuv fs calls: forbidden anywhere under lua/ (incl. persist.lua).
if grep -RInE "$mutating" lua/; then
  echo "ERROR: a mutating libuv fs call appears above. yfp must stay read-only." >&2
  status=1
fi

# 2) Shell-outs: forbidden anywhere under lua/.
if grep -RInE "$shellout" lua/; then
  echo "ERROR: yfp must not shell out for filesystem work." >&2
  status=1
fi

# 3) Host-side writes: allowed ONLY in persist.lua.
if grep -RInE "$hostwrite" lua/ | grep -vE "$persist"; then
  echo "ERROR: host-side filesystem writes are only allowed in $persist (pins state)." >&2
  status=1
fi

# 4) persist.lua must target stdpath("data") and nothing else.
if [ -f "$persist" ]; then
  if ! grep -qE 'stdpath\("data"\)' "$persist"; then
    echo "ERROR: $persist must derive its write path from stdpath(\"data\")." >&2
    status=1
  fi
  if grep -nE 'stdpath\("config"\)|stdpath\("state"\)|getcwd|expand\(' "$persist"; then
    echo "ERROR: $persist may only ever write under stdpath(\"data\")." >&2
    status=1
  fi
fi

if [ "$status" -eq 0 ]; then
  echo "OK: read-only invariant holds (writes confined to $persist -> stdpath data)."
fi
exit "$status"
