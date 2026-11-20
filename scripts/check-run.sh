#!/usr/bin/env bash
# Scripted whole-app run. Drives the built snapit.app from the outside, in test mode:
# a fresh temporary root holds the sockets, so the run never touches the real cache
# folder, preferences or any other snapit that is running. Asserts only on what is
# observable: processes, sockets and their replies, CPU time, memory footprint.
#
# Usage: scripts/check-run.sh path/to/snapit.app
# Optional: SNAPIT_IDLE_SECONDS (default 15) sets the idle window; SNAPIT_FOOTPRINT_MB_MAX
# (default 20) the menu bar app's footprint ceiling.
set -uo pipefail

APP="${1:?usage: check-run.sh path/to/snapit.app}"
APP="$(cd "$APP" && pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_EXE="$APP/Contents/MacOS/snapit"
HELPER_EXE="$APP/Contents/Helpers/snapit Editor.app/Contents/MacOS/snapit Editor"
IDLE_SECONDS="${SNAPIT_IDLE_SECONDS:-15}"
FOOTPRINT_MB_MAX="${SNAPIT_FOOTPRINT_MB_MAX:-20}"

# A short path: a Unix socket path holds at most 103 bytes.
RUN_ROOT="$(mktemp -d /tmp/snapit-run.XXXXXX)"
export SNAPIT_TEST_ROOT="$RUN_ROOT"
APP_SOCK="$RUN_ROOT/app.sock"
EDITOR_SOCK="$RUN_ROOT/editor.sock"
failures=0

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

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
expect_equal() { # description, expected, actual
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (expected '$2', got '$3')"; fi
}

send() { printf '%s\n' "$2" | nc -U -w 2 "$1" 2>/dev/null; }

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

EXPECTED_VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$ROOT_DIR/Cargo.toml" | head -1)"

# 1. The menu bar app starts and answers on its socket.
(nohup "$APP_EXE" >"$RUN_ROOT/app.log" 2>&1 &)
if wait_until 10 answers "$APP_SOCK"; then pass "menu bar app starts and answers on its socket"; else fail "menu bar app did not answer"; exit 1; fi
APP_PID="$(pid_of "$APP_EXE")"

# 2. The menu shows the engine version (read through the C ABI) and Quit snapit.
expect_equal "menu lists the engine version and Quit snapit" \
  "Engine $EXPECTED_VERSION"$'\n-\nQuit snapit' "$(send "$APP_SOCK" menu-titles)"
expect_equal "engine version round-trips through the C ABI in the menu bar app" "$EXPECTED_VERSION" "$(send "$APP_SOCK" engine-version)"
expect_equal "an engine panic comes back as a status code in the menu bar app" "panic" "$(send "$APP_SOCK" engine-probe-panic)"
expect_equal "the menu bar app survives an engine panic" "$EXPECTED_VERSION" "$(send "$APP_SOCK" engine-version)"
expect_equal "unknown commands are refused" "error unknown command nope" "$(send "$APP_SOCK" nope)"

# 3. It is an agent app: no Dock icon.
ASN="$(lsappinfo find pid="$APP_PID")"
if lsappinfo info -only applicationType "$ASN" 2>/dev/null | grep -q 'UIElement'; then pass "menu bar app has no Dock icon"; else fail "menu bar app is not an agent"; fi

# 4. No helper process at rest.
if [[ -z "$(pid_of "$APP/Contents/Helpers/")" ]]; then pass "no helper process at rest"; else fail "a helper is running at rest"; fi

# 5. Idle: 0% CPU and about 15 MB.
sleep 3
CPU_BEFORE="$(cpu_seconds "$APP_PID")"
sleep "$IDLE_SECONDS"
CPU_AFTER="$(cpu_seconds "$APP_PID")"
CPU_USED="$(awk -v a="$CPU_BEFORE" -v b="$CPU_AFTER" 'BEGIN { printf "%.2f", b - a }')"
if awk -v used="$CPU_USED" 'BEGIN { exit !(used <= 0.02) }'; then
  pass "menu bar app idles at 0% CPU (${CPU_USED}s of CPU in ${IDLE_SECONDS}s)"
else
  fail "menu bar app used ${CPU_USED}s of CPU in ${IDLE_SECONDS}s idle"
fi
FOOTPRINT="$(footprint_mb "$APP_PID")"
if awk -v f="$FOOTPRINT" -v max="$FOOTPRINT_MB_MAX" 'BEGIN { exit !(f > 0 && f <= max) }'; then
  pass "menu bar app footprint is ${FOOTPRINT} MB (about 15 MB, ceiling ${FOOTPRINT_MB_MAX} MB)"
else
  fail "menu bar app footprint is '${FOOTPRINT}' MB (ceiling ${FOOTPRINT_MB_MAX} MB)"
fi

# 6. The Editor helper starts as an agent, links the same engine and quits when told to.
(nohup "$HELPER_EXE" >"$RUN_ROOT/helper.log" 2>&1 &)
if wait_until 10 answers "$EDITOR_SOCK"; then pass "Editor helper starts and answers on its socket"; else fail "Editor helper did not answer"; fi
HELPER_PID="$(pid_of "$HELPER_EXE")"
if lsappinfo info -only applicationType "$(lsappinfo find pid="$HELPER_PID")" 2>/dev/null | grep -q 'UIElement'; then
  pass "Editor helper has no Dock icon"
else
  fail "Editor helper is not an agent"
fi
expect_equal "engine version round-trips through the C ABI in the Editor helper" "$EXPECTED_VERSION" "$(send "$EDITOR_SOCK" engine-version)"
expect_equal "an engine panic comes back as a status code in the Editor helper" "panic" "$(send "$EDITOR_SOCK" engine-probe-panic)"
expect_equal "the Editor helper survives an engine panic" "$EXPECTED_VERSION" "$(send "$EDITOR_SOCK" engine-version)"
expect_equal "Editor helper replies ok to quit" "ok" "$(send "$EDITOR_SOCK" quit)"
if wait_until 5 gone "$HELPER_PID"; then pass "Editor helper quits when told to"; else fail "Editor helper is still running after quit"; fi

# 7. Quitting snapit also quits a running helper.
(nohup "$HELPER_EXE" >"$RUN_ROOT/helper.log" 2>&1 &)
wait_until 10 answers "$EDITOR_SOCK"
HELPER_PID="$(pid_of "$HELPER_EXE")"
expect_equal "menu bar app replies ok to quit" "ok" "$(send "$APP_SOCK" quit)"
if wait_until 5 gone "$APP_PID"; then pass "menu bar app quits when told to"; else fail "menu bar app is still running after quit"; fi
if wait_until 5 gone "$HELPER_PID"; then pass "quitting snapit quits the Editor helper"; else fail "Editor helper outlived snapit"; fi
if [[ ! -e "$APP_SOCK" ]]; then pass "menu bar app removes its socket on quit"; else fail "stale app socket left behind"; fi

# 8. The helper launched on its own starts snapit and quits without showing anything.
(nohup "$HELPER_EXE" >"$RUN_ROOT/helper.log" 2>&1 &)
HELPER_PID="$(pid_of "$HELPER_EXE")"
if wait_until 10 answers "$APP_SOCK"; then pass "Editor helper launched on its own starts snapit"; else fail "snapit was not started by the helper"; fi
if [[ -n "$HELPER_PID" ]] && wait_until 10 gone "$HELPER_PID"; then pass "Editor helper launched on its own quits"; else fail "Editor helper launched on its own is still running"; fi
send "$APP_SOCK" quit >/dev/null
wait_until 5 bash -c "! pgrep -f '$APP_EXE' >/dev/null"

if ((failures > 0)); then
  echo "$failures scripted-run check(s) failed"
  exit 1
fi
echo "scripted run passed"
