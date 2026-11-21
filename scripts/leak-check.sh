#!/usr/bin/env bash
# Sourced by scripts/test.sh around the scripted whole-app run. The run is meant to leave the
# real machine as it found it, so this looks from outside at two places it must never reach:
#
#   - ~/Downloads: the names of the `snapit-*` files there (names only, nothing is opened);
#   - the general pasteboard's changeCount (a read of one integer: it never writes to the
#     pasteboard and never reads what is on it).
#
#   leak_begin   records both before the run
#   leak_check   returns non-zero, with a message, when a new `snapit-*` file appeared or the
#                changeCount moved
#
# SNAPIT_LEAK_DOWNLOADS_DIR replaces ~/Downloads, for testing this check only. When the folder
# can't be listed (a terminal without access to Downloads) the file half says so and is skipped;
# the pasteboard half always runs.

_leak_downloads_dir() { printf '%s' "${SNAPIT_LEAK_DOWNLOADS_DIR:-$HOME/Downloads}"; }

# Sorted names of the snapit-* entries in Downloads, one per line; fails when it can't list.
_leak_downloads_names() {
  local dir
  dir="$(_leak_downloads_dir)"
  ls -1A "$dir" >/dev/null 2>&1 || return 1
  find "$dir" -mindepth 1 -maxdepth 1 -name 'snapit-*' 2>/dev/null | sed 's|.*/||' | sort
}

# Prints NSPasteboard.general.changeCount, one integer. Needs swift (Xcode, see xcode-env.sh).
_leak_changecount() {
  local count
  count="$(swift -e 'import AppKit; print(NSPasteboard.general.changeCount)' 2>/dev/null)" || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$count"
}

leak_begin() {
  LEAK_DOWNLOADS_UNREADABLE=""
  if ! LEAK_DOWNLOADS_BEFORE="$(_leak_downloads_names)"; then
    LEAK_DOWNLOADS_UNREADABLE=yes
    LEAK_DOWNLOADS_BEFORE=""
    echo "note: $(_leak_downloads_dir) can't be listed from here (a terminal without access to Downloads?); the snapit-* file check is skipped"
  fi
  LEAK_CHANGECOUNT_BEFORE="$(_leak_changecount)" || {
    echo "error: could not read the general pasteboard's changeCount (is swift working?)" >&2
    return 1
  }
}

leak_check() {
  local ok=0 after_names new count
  if [[ -z "$LEAK_DOWNLOADS_UNREADABLE" ]]; then
    if ! after_names="$(_leak_downloads_names)"; then
      echo "error: $(_leak_downloads_dir) could be listed before the run but not after" >&2
      ok=1
    else
      new="$(comm -13 <(printf '%s\n' "$LEAK_DOWNLOADS_BEFORE") <(printf '%s\n' "$after_names") | sed '/^$/d')"
      if [[ -n "$new" ]]; then
        echo "error: the scripted run left new snapit-* files in $(_leak_downloads_dir): $(printf '%s' "$new" | tr '\n' ' ')" >&2
        ok=1
      fi
    fi
  fi
  if ! count="$(_leak_changecount)"; then
    echo "error: could not read the general pasteboard's changeCount after the run" >&2
    ok=1
  elif [[ "$count" != "$LEAK_CHANGECOUNT_BEFORE" ]]; then
    echo "error: the general pasteboard changed during the scripted run (changeCount $LEAK_CHANGECOUNT_BEFORE -> $count). The run uses a private pasteboard, so either snapit wrote to the real clipboard or something else copied while it ran; if you copied, rerun without copying" >&2
    ok=1
  fi
  if ((ok == 0)); then
    if [[ -n "$LEAK_DOWNLOADS_UNREADABLE" ]]; then
      echo "leak check: general pasteboard unchanged (Downloads not checked)"
    else
      echo "leak check: no new snapit-* files in Downloads, general pasteboard unchanged"
    fi
  fi
  return "$ok"
}
