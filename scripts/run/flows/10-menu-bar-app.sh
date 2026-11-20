# Flow: the menu bar app starts, is an agent with the right menu, and idles. The app is
# already running (check-run.sh starts it). Sourced by scripts/check-run.sh.
# shellcheck shell=bash

# The menu: Capture Screen with its Shortcut, the engine version (read through the C ABI), Quit.
expect_in_order "menu lists Capture Screen, the engine version and Quit snapit, in that order" \
  "$(send "$APP_SOCK" menu-titles)" "Capture Screen" "Engine $EXPECTED_VERSION" "Quit snapit"
expect_equal "engine version round-trips through the C ABI in the menu bar app" "$EXPECTED_VERSION" "$(send "$APP_SOCK" engine-version)"
expect_equal "an engine panic comes back as a status code in the menu bar app" "panic" "$(send "$APP_SOCK" engine-probe-panic)"
expect_equal "the menu bar app survives an engine panic" "$EXPECTED_VERSION" "$(send "$APP_SOCK" engine-version)"
expect_equal "unknown commands are refused" "error unknown command nope" "$(send "$APP_SOCK" nope)"
expect_equal "arguments with spaces survive the socket" "hello world" "$(send "$APP_SOCK" 'echo hello%20world')"

# A second copy on the same socket quits and leaves the running one alone.
"$APP_EXE" >"$RUN_ROOT/second.log" 2>&1 &
SECOND_PID=$!
if wait_until 10 gone "$SECOND_PID"; then pass "a second copy of the menu bar app quits"; else fail "a second copy of the menu bar app kept running"; kill "$SECOND_PID" 2>/dev/null; fi
if answers "$APP_SOCK" && kill -0 "$APP_PID" 2>/dev/null; then pass "the running menu bar app keeps its socket"; else fail "the second copy took over the socket"; fi

# It is an agent app: no Dock icon.
ASN="$(lsappinfo find pid="$APP_PID")"
if lsappinfo info -only applicationType "$ASN" 2>/dev/null | grep -q 'UIElement'; then pass "menu bar app has no Dock icon"; else fail "menu bar app is not an agent"; fi

# No helper process at rest.
if [[ -z "$(pid_of "$APP/Contents/Helpers/")" ]]; then pass "no helper process at rest"; else fail "a helper is running at rest"; fi

# Idle: 0% CPU and about 15 MB.
sleep 3
assert_idle_cpu "menu bar app" "$APP_PID" "$IDLE_SECONDS"
FOOTPRINT="$(footprint_mb "$APP_PID")"
if awk -v f="$FOOTPRINT" -v max="$FOOTPRINT_MB_MAX" 'BEGIN { exit !(f > 0 && f <= max) }'; then
  pass "menu bar app footprint is ${FOOTPRINT} MB (about 15 MB, ceiling ${FOOTPRINT_MB_MAX} MB)"
else
  fail "menu bar app footprint is '${FOOTPRINT}' MB (ceiling ${FOOTPRINT_MB_MAX} MB)"
fi
