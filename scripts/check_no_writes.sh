#!/usr/bin/env bash
# Enforce yfp's read-only-by-construction invariant (see CLAUDE.md, Golden Rule #2).
# Fails if any mutating libuv filesystem call, or a shell-out, appears under lua/.
set -euo pipefail

mutating='fs_write|fs_unlink|fs_mkdir|fs_mkdtemp|fs_rmdir|fs_rename|fs_ftruncate|fs_chmod|fs_fchmod|fs_chown|fs_fchown|fs_lchown|fs_link|fs_symlink|fs_copyfile|fs_utime|fs_futime|fs_sendfile|fs_open'
shellout='vim\.fn\.system|jobstart|uv\.spawn|io\.popen|os\.execute'

status=0

if grep -RInE "$mutating" lua/; then
  echo "ERROR: a mutating libuv fs call appears above. yfp must stay read-only." >&2
  status=1
fi

if grep -RInE "$shellout" lua/; then
  echo "ERROR: yfp must not shell out for filesystem work." >&2
  status=1
fi

if [ "$status" -eq 0 ]; then
  echo "OK: no mutating fs calls or shell-outs found under lua/."
fi
exit "$status"
