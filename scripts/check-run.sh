#!/usr/bin/env bash
# Scripted whole-app run. Drives the built snapit.app from the outside, in test mode: a fresh
# temporary root holds the sockets, the private pasteboard's name, the Save location, the
# Last Capture/cache folder and the defaults, and the Capture source returns fixture images.
# The run never touches the real cache folder, preferences, clipboard or Save location, never
# registers a real hot key and never triggers a Screen Recording prompt, so several runs (and
# the user's own snapit) can go at once. It asserts only on what is observable: processes,
# sockets and their replies, the pasteboard's PNG, memory footprint, CPU time and the cache folder's files.
#
# The run is a list of flows, one file each, in scripts/run/flows/ (sourced in name order).
# Helpers are in scripts/run/lib.sh. docs/testing.md says how to add a flow.
#
# Usage: scripts/check-run.sh path/to/snapit.app
# Optional: SNAPIT_FLOWS (flow number prefixes, default every flow) runs only those flows.
set -uo pipefail

APP="${1:?usage: check-run.sh path/to/snapit.app}"
APP="$(cd "$APP" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXE="$APP/Contents/MacOS/snapit"
HELPER_EXE="$APP/Contents/Helpers/snapit Editor.app/Contents/MacOS/snapit"

# A short path: a Unix socket path holds at most 103 bytes.
RUN_ROOT="$(mktemp -d /tmp/snapit-run.XXXXXX)"
export SNAPIT_TEST_ROOT="$RUN_ROOT"
APP_SOCK="$RUN_ROOT/app.sock"
EDITOR_SOCK="$RUN_ROOT/editor.sock"
INSPECT="$RUN_ROOT/png-inspect"

# shellcheck source=run/lib.sh
source "$ROOT_DIR/scripts/run/lib.sh"
# shellcheck source=run/editor.sh
source "$ROOT_DIR/scripts/run/editor.sh"
# shellcheck source=run/install.sh
source "$ROOT_DIR/scripts/run/install.sh"

cleanup() {
  # Quit whatever is still running from this bundle, then remove the run root.
  for sock in "$EDITOR_SOCK" "$APP_SOCK"; do
    [[ -S "$sock" ]] && send "$sock" quit >/dev/null 2>&1
  done
  sleep 0.5
  pkill -f "$APP/Contents/" 2>/dev/null
  # Copies a flow relaunched from the run's fixture Applications folder.
  pkill -f "$(basename "$RUN_ROOT")/Applications/" 2>/dev/null
  unregister_fixture_apps
  chflags -R nouchg "$RUN_ROOT" 2>/dev/null
  chmod -R u+w "$RUN_ROOT" 2>/dev/null
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

echo "environment: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model), $(sysctl -n hw.ncpu) CPUs, $(($(sysctl -n hw.memsize) / 1073741824)) GB, load $(sysctl -n vm.loadavg | tr -d '{}')"
echo "environment: $(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
"$INSPECT" screens 2>&1 | sed 's/^/environment: /'
echo "environment: the run's fixture displays are fake (placed on the real desktop); the real screens above are only where their panels sit"

# The menu bar app starts, in test mode, and answers on its socket.
launch_app
if wait_until 10 answers "$APP_SOCK"; then pass "menu bar app starts and answers on its socket"; else abort "menu bar app did not answer"; fi
APP_PID="$(pid_of "$APP_EXE")"

# SNAPIT_FLOWS="38 40" runs only the flows whose names start with one of those numbers (all by
# default): quicker while working on one flow. Flows share state, so a run of a few flows is for
# development only; scripts/test.sh runs them all.
for flow in "$ROOT_DIR"/scripts/run/flows/*.sh; do
  if [[ -n "${SNAPIT_FLOWS:-}" ]]; then
    selected=""
    for prefix in $SNAPIT_FLOWS; do [[ "$(basename "$flow")" == "$prefix"* ]] && selected=yes; done
    [[ -n "$selected" ]] || continue
  fi
  echo "--- $(basename "$flow" .sh)"
  # shellcheck source=/dev/null
  source "$flow"
  expect_cache_holds_only_expected "$(basename "$flow" .sh)"
done

# Everything has quit by now; give preferences a moment to flush, then compare.
sleep 1
isolation_check

if ((failures > 0)); then
  # What the menu bar app logged in test mode (why an overlay ended, which notifications arrived): the run's
  # root is deleted on exit, so a failing run prints it here.
  echo "--- the menu bar app's log (snapit: lines, last 150)"
  grep -h 'snapit:' "$RUN_ROOT"/app.log 2>/dev/null | cut -c1-400 | tail -150
  echo "$failures scripted-run check(s) failed"
  exit 1
fi
echo "scripted run passed"
