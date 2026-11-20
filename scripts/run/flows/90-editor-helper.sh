# Flow: snapit starts the Editor helper, the helper quits with snapit, and a helper launched
# on its own starts snapit and quits. Ends by quitting snapit, so it runs last.
# Sourced by scripts/check-run.sh.
# shellcheck shell=bash

# snapit starts the Editor helper, which is an agent, links the same engine and quits when told to.
expect_equal "snapit starts the Editor helper" "ok" "$(send "$APP_SOCK" start-editor)"
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
expect_contains "the Editor helper runs in test mode with the same private pasteboard" \
  "pasteboard=dev.snapit.test.$(basename "$RUN_ROOT")" "$(send "$EDITOR_SOCK" test-seams)"
# Both processes see the same defaults: write in one, read in the other.
send "$APP_SOCK" "defaults-set shared-probe written-by-the-menu-bar-app" >/dev/null
expect_equal "the Editor helper reads a default the menu bar app wrote" "written-by-the-menu-bar-app" "$(send "$EDITOR_SOCK" "defaults-get shared-probe")"
send "$EDITOR_SOCK" "defaults-set helper-probe written-by-the-helper" >/dev/null
expect_equal "the menu bar app reads a default the Editor helper wrote" "written-by-the-helper" "$(send "$APP_SOCK" "defaults-get helper-probe")"
expect_equal "Editor helper replies ok to quit" "ok" "$(send "$EDITOR_SOCK" quit)"
if wait_until 5 gone "$HELPER_PID"; then pass "Editor helper quits when told to"; else fail "Editor helper is still running after quit"; fi

# Quitting snapit also quits a running helper.
send "$APP_SOCK" start-editor >/dev/null
wait_until 10 answers "$EDITOR_SOCK"
HELPER_PID="$(pid_of "$HELPER_EXE")"
expect_equal "menu bar app replies ok to quit" "ok" "$(send "$APP_SOCK" quit)"
if wait_until 5 gone "$APP_PID"; then pass "menu bar app quits when told to"; else fail "menu bar app is still running after quit"; fi
if wait_until 5 gone "$HELPER_PID"; then pass "quitting snapit quits the Editor helper"; else fail "Editor helper outlived snapit"; fi
if [[ ! -e "$APP_SOCK" ]]; then pass "menu bar app removes its socket on quit"; else fail "stale app socket left behind"; fi

# The helper launched on its own starts snapit and quits without showing anything.
(nohup "$HELPER_EXE" >"$RUN_ROOT/helper.log" 2>&1 &)
HELPER_PID="$(pid_of "$HELPER_EXE")"
if wait_until 10 answers "$APP_SOCK"; then pass "Editor helper launched on its own starts snapit"; else fail "snapit was not started by the helper"; fi
if [[ -n "$HELPER_PID" ]] && wait_until 10 gone "$HELPER_PID"; then pass "Editor helper launched on its own quits"; else fail "Editor helper launched on its own is still running"; fi
send "$APP_SOCK" quit >/dev/null
wait_until 5 bash -c "! pgrep -f '$APP_EXE' >/dev/null"
