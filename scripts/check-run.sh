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
# SNAPIT_FOOTPRINT_FROM_REST_MB_MAX (default 5) how far above its at-rest footprint it may end up;
# SNAPIT_BAR_FIRST_USE_MB_MAX (default 2.5) what the first Action bar's glass may cost for good;
# SNAPIT_FLOWS (flow number prefixes, default every flow) runs only those flows; SNAPIT_VM=0|1 forces
# the virtual-machine rules off or on (default: what the kernel says).
set -uo pipefail

APP="${1:?usage: check-run.sh path/to/snapit.app}"
APP="$(cd "$APP" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXE="$APP/Contents/MacOS/snapit"
HELPER_EXE="$APP/Contents/Helpers/snapit Editor.app/Contents/MacOS/snapit"
IDLE_SECONDS="${SNAPIT_IDLE_SECONDS:-15}"
FOOTPRINT_MB_MAX="${SNAPIT_FOOTPRINT_MB_MAX:-20}"
FOOTPRINT_GROWTH_MB_MAX="${SNAPIT_FOOTPRINT_GROWTH_MB_MAX:-4}"
FOOTPRINT_FROM_REST_MB_MAX="${SNAPIT_FOOTPRINT_FROM_REST_MB_MAX:-5}"
# The Action bar is Liquid Glass (an NSGlassEffectView), and the first one a process shows costs
# memory that stays: measured +0.7 to +1.8 MB once it is cancelled, +0.9 to +2.1 MB after five
# Captures through it (it varies run to run). 2.5 MB is that with a little room, and still catches a bar built from
# SwiftUI on glass (+4.2 MB) or AppKit controls (+2.4 MB).
BAR_FIRST_USE_MB_MAX="${SNAPIT_BAR_FIRST_USE_MB_MAX:-2.5}"
# From flow 42 on the process holds that glass, so what is measured against the resting footprint
# of flow 20 (and against the launch ceiling) gets the same 2.5 MB on top.
FOOTPRINT_FROM_REST_AFTER_BAR_MB_MAX="$(awk -v a="$FOOTPRINT_FROM_REST_MB_MAX" -v b="$BAR_FIRST_USE_MB_MAX" 'BEGIN { print a + b }')"
FOOTPRINT_AFTER_BAR_MB_MAX="$(awk -v a="$FOOTPRINT_MB_MAX" -v b="$BAR_FIRST_USE_MB_MAX" 'BEGIN { print a + b }')"

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

# The machine, so a log of a run that fails somewhere else (a CI runner) says what it ran on. IS_VM is 1 on
# a virtual machine (the kernel says so; SNAPIT_VM=0|1 overrides it, to try either rule on any machine): a few
# budgets there are measured against what software rendering and a noisy CPU can do, each time with an
# `ENV` line and counted in the last line (docs/testing.md, "CI environment"). Never 1 on a real Mac.
IS_VM="${SNAPIT_VM:-$(sysctl -n kern.hv_vmm_present 2>/dev/null || echo 0)}"
[[ "$IS_VM" == 1 ]] || IS_VM=0
export IS_VM
if [[ "$IS_VM" == 1 ]]; then IDLE_ACTIVE_MIN=0.02; else IDLE_ACTIVE_MIN=0.01; fi
export IDLE_ACTIVE_MIN
echo "environment: macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(sysctl -n hw.model), $(sysctl -n hw.ncpu) CPUs, $(($(sysctl -n hw.memsize) / 1073741824)) GB, load $(sysctl -n vm.loadavg | tr -d '{}')"
echo "environment: virtual machine=$IS_VM (kernel says $(sysctl -n kern.hv_vmm_present 2>/dev/null || echo unknown)), CI=${CI:-no}, GITHUB_ACTIONS=${GITHUB_ACTIONS:-no}, idle window is active from ${IDLE_ACTIVE_MIN}s of CPU"
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
done

# Everything has quit by now; give preferences a moment to flush, then compare.
sleep 1
isolation_check

echo "environment: $(ambient_events)"
if ((failures > 0)); then
  # What the menu bar app logged in test mode (why an overlay ended, which notifications arrived): the run's
  # root is deleted on exit, so a failing run prints it here.
  echo "--- the menu bar app's log (snapit: lines, last 150)"
  grep -h 'snapit:' "$RUN_ROOT"/app.log 2>/dev/null | cut -c1-400 | tail -150
  echo "$failures scripted-run check(s) failed ($adaptations adaptation(s) to a virtual machine)"
  exit 1
fi
echo "scripted run passed ($adaptations adaptation(s) to a virtual machine)"
