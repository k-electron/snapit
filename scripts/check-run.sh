#!/usr/bin/env bash
# Scripted whole-app run. Drives the built snapit.app from the outside, in test mode: a fresh
# temporary root holds the sockets, the private pasteboard's name, the Save location, the
# Last Capture/cache folder and the defaults, and the Capture source returns fixture images.
# The run never touches the real cache folder, preferences, clipboard or Save location, never
# registers a real hot key and never triggers a Screen Recording prompt, so several runs (and
# the user's own snapit) can go at once. It asserts only on what is observable: processes,
# sockets and their replies, the pasteboard's PNG, CPU time, memory footprint.
#
# The run is a list of flows, one file each, in scripts/run/flows/ (sourced in name order).
# Helpers are in scripts/run/lib.sh. docs/testing.md says how to add a flow.
#
# Usage: scripts/check-run.sh path/to/snapit.app
# Optional: SNAPIT_IDLE_SECONDS (default 15) sets the idle window; SNAPIT_FOOTPRINT_MB_MAX
# (default 20) the menu bar app's footprint ceiling; SNAPIT_FOOTPRINT_GROWTH_MB_MAX (default 4)
# how far its footprint may grow over repeated Captures once warmed up;
# SNAPIT_FOOTPRINT_FROM_REST_MB_MAX (default 8) how far above its at-rest footprint it may end up.
set -uo pipefail

APP="${1:?usage: check-run.sh path/to/snapit.app}"
APP="$(cd "$APP" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXE="$APP/Contents/MacOS/snapit"
HELPER_EXE="$APP/Contents/Helpers/snapit Editor.app/Contents/MacOS/snapit Editor"
IDLE_SECONDS="${SNAPIT_IDLE_SECONDS:-15}"
FOOTPRINT_MB_MAX="${SNAPIT_FOOTPRINT_MB_MAX:-20}"
FOOTPRINT_GROWTH_MB_MAX="${SNAPIT_FOOTPRINT_GROWTH_MB_MAX:-4}"
FOOTPRINT_FROM_REST_MB_MAX="${SNAPIT_FOOTPRINT_FROM_REST_MB_MAX:-8}"

# A short path: a Unix socket path holds at most 103 bytes.
RUN_ROOT="$(mktemp -d /tmp/snapit-run.XXXXXX)"
export SNAPIT_TEST_ROOT="$RUN_ROOT"
APP_SOCK="$RUN_ROOT/app.sock"
EDITOR_SOCK="$RUN_ROOT/editor.sock"
INSPECT="$RUN_ROOT/png-inspect"

# shellcheck source=run/lib.sh
source "$ROOT_DIR/scripts/run/lib.sh"

cleanup() {
  # Quit whatever is still running from this bundle, then remove the run root.
  for sock in "$EDITOR_SOCK" "$APP_SOCK"; do
    [[ -S "$sock" ]] && send "$sock" quit >/dev/null 2>&1
  done
  sleep 0.5
  pkill -f "$APP/Contents/" 2>/dev/null
  rm -rf "$RUN_ROOT"
}
trap cleanup EXIT

EXPECTED_VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$ROOT_DIR/Cargo.toml" | head -1)"

# The independent PNG checker, built fresh into the run root.
if ! xcrun swiftc -O -module-cache-path "$RUN_ROOT/modcache" "$ROOT_DIR/scripts/run/png-inspect.swift" -o "$INSPECT" 2>"$RUN_ROOT/inspect-build.log"; then
  cat "$RUN_ROOT/inspect-build.log"
  abort "could not build png-inspect"
fi

isolation_begin

# The menu bar app starts, in test mode, and answers on its socket.
(nohup "$APP_EXE" >"$RUN_ROOT/app.log" 2>&1 &)
if wait_until 10 answers "$APP_SOCK"; then pass "menu bar app starts and answers on its socket"; else abort "menu bar app did not answer"; fi
APP_PID="$(pid_of "$APP_EXE")"

for flow in "$ROOT_DIR"/scripts/run/flows/*.sh; do
  echo "--- $(basename "$flow" .sh)"
  # shellcheck source=/dev/null
  source "$flow"
done

# Everything has quit by now; give preferences a moment to flush, then compare.
sleep 1
isolation_check

if ((failures > 0)); then
  echo "$failures scripted-run check(s) failed"
  exit 1
fi
echo "scripted run passed"
