# Helpers for the scripted whole-app run. Sourced by scripts/check-run.sh, which sets
# APP, APP_EXE, HELPER_EXE, RUN_ROOT, APP_SOCK, EDITOR_SOCK, INSPECT and ROOT_DIR first.
# A flow (scripts/run/flows/NN-name.sh) is sourced after these helpers and may use them.
# shellcheck shell=bash

failures=0

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
expect_equal() { # description, expected, actual
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}
expect_contains() { # description, needle, haystack
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1 (expected to contain '$2', got '$3')"; fi
}
abort() { echo "FAIL $1"; exit 1; }

# One command to a snapit process: send <socket> "<command line>". Arguments with spaces are
# percent-encoded. SEND_TIMEOUT (seconds, default 2) is how long to wait for the reply.
send() { printf '%s\n' "$2" | nc -U -w "${SEND_TIMEOUT:-2}" "$1" 2>/dev/null; }
# The same, for commands that run a whole Capture.
send_slow() { SEND_TIMEOUT=30 send "$@"; }

wait_until() { # seconds, command...
  local deadline=$((SECONDS + $1))
  shift
  while ((SECONDS < deadline)); do
    "$@" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  return 1
}
answers() { [[ "$(send "$1" ping)" == "pong" ]]; }
pid_of() { pgrep -f "$1" | head -1; }
gone() { ! kill -0 "$1" 2>/dev/null; }
cpu_seconds() { ps -o cputime= -p "$1" | awk -F'[:]' '{ print ($1 * 60) + $2 }'; }
footprint_mb() { footprint -p "$1" 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "Footprint:") { v = $(i+1); u = $(i+2); if (u == "KB") v = v / 1024; if (u == "GB") v = v * 1024; printf "%.1f", v; exit } }'; }

# assert_idle_cpu <label> <pid> <seconds>: the process used no CPU for <seconds>.
assert_idle_cpu() {
  local before after used
  before="$(cpu_seconds "$2")"
  sleep "$3"
  after="$(cpu_seconds "$2")"
  used="$(awk -v a="$before" -v b="$after" 'BEGIN { printf "%.2f", b - a }')"
  if awk -v used="$used" 'BEGIN { exit !(used <= 0.02) }'; then
    pass "$1 idles at 0% CPU (${used}s of CPU in ${3}s)"
  else
    fail "$1 used ${used}s of CPU in ${3}s idle"
  fi
}

# png_field <info output> <key>: one value out of `png-inspect info`.
png_field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }

# Isolation: a test run must leave the user's machine as it found it. isolation_begin takes
# a snapshot of everything a run could touch by mistake; isolation_check compares at the end.
# (Not snapshotted: ~/Downloads, which a terminal may not be allowed to list. The run's Save
# location is <root>/save, checked by the `test-seams` assertions.)
isolation_state() {
  echo "-- preference files"
  find "$HOME/Library/Preferences" -maxdepth 1 -name 'dev.snapit.snapit*.plist' -exec stat -f '%N %m %z' {} + 2>/dev/null | sort
  echo "-- preferences as cfprefsd sees them"
  defaults read dev.snapit.snapit 2>&1 | shasum
  defaults read dev.snapit.snapit.editor 2>&1 | shasum
  echo "-- real cache folder"
  find "$HOME/Library/Caches/dev.snapit.snapit" -exec stat -f '%N %m %z' {} + 2>&1 | sort
  echo "-- general pasteboard"
  "$INSPECT" general-pasteboard
}
isolation_begin() { ISOLATION_BEFORE="$(isolation_state)"; }
isolation_check() {
  local after
  after="$(isolation_state)"
  if [[ "$ISOLATION_BEFORE" == "$after" ]]; then
    pass "isolation: no snapit preferences, real cache folder or general pasteboard were touched"
  else
    fail "isolation: the run touched the real system"
    diff <(echo "$ISOLATION_BEFORE") <(echo "$after") | sed 's/^/     /'
  fi
}
