# Flow: the Editor helper warms up when a Capture starts. Pressing a Capture Shortcut starts the
# helper hidden (an agent: no Dock icon, no window) and it builds the Editor ahead of its Capture;
# Cancel quits a helper that never showed anything; the Capture then opens in about 50 ms. A helper
# launched on its own (a Dock pin) starts snapit and leaves nothing behind.
# Sourced by scripts/check-run.sh. Needs the helpers in scripts/run/editor.sh.
# shellcheck shell=bash

# The ceiling for "Capture to the Editor visible" with a warm helper. The target is about 50 ms;
# the ceiling leaves room for a busy CI machine. The measured value is in the pass line.
# It is the median of three Captures, each with a helper that was already warm.
WARM_OPEN_MS_MAX="${SNAPIT_WARM_OPEN_MS_MAX:-120}"
# The footprint ceiling for a warm helper (hidden window, toolbars and canvas built, no Capture).
WARM_HELPER_MB_MAX="${SNAPIT_WARM_HELPER_MB_MAX:-60}"

warm_state() { send "$APP_SOCK" "editor-warm-up state"; }
helper_count() { pgrep -f "$HELPER_EXE" | wc -l | tr -d ' '; }
no_helper() { [[ "$(helper_count)" == "0" ]]; }
warm_is() { [[ "$(warm_state)" == "$1" ]]; }
some_helper() { [[ "$(helper_count)" != "0" ]]; }
one_snapit() { [[ "$(pgrep -f "$APP_EXE" | wc -l | tr -d ' ')" == "1" ]]; }

send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" "fixture-delay 0" >/dev/null
expect_equal "no helper process at rest before the warm-up flow" "0" "$(helper_count)"
WARM_REST_MB="$(footprint_mb "$APP_PID")"

# 1. Shortcut pressed: the helper starts hidden and prepares an Editor.
expect_equal "Shortcut pressed: warm-up starts" "ok" "$(send "$APP_SOCK" "editor-warm-up begin")"
if wait_until 10 warm_is warm; then pass "the menu bar app reports the helper warm"; else fail "the helper did not warm up (state '$(warm_state)')"; fi
WARM_PID="$(helper_pid)"
expect_equal "exactly one helper process is warming up" "1" "$(helper_count)"
expect_contains "the warm helper has built its Editor, hidden" "warm window=hidden canvas=built" "$(send "$EDITOR_SOCK" editor-warm-state)"
expect_equal "a warm helper has no Dock icon (application type UIElement)" "UIElement" "$(app_type "$WARM_PID")"
expect_equal "a warm helper has no window on screen" "0" "$(onscreen_windows "$WARM_PID")"
expect_equal "a warm helper has no Editor open" "" "$(open_editors)"
expect_equal "pressing the Shortcut again while warm starts no second helper" "ok" "$(send "$APP_SOCK" "editor-warm-up begin")"
expect_equal "still exactly one helper process" "1" "$(helper_count)"
WARM_HELPER_MB="$(footprint_mb "$WARM_PID")"
if awk -v a="$WARM_HELPER_MB" -v max="$WARM_HELPER_MB_MAX" 'BEGIN { exit !(a > 0 && a <= max) }'; then
  pass "a warm helper's footprint is ${WARM_HELPER_MB} MB (ceiling ${WARM_HELPER_MB_MAX} MB)"
else
  fail "a warm helper's footprint is '${WARM_HELPER_MB}' MB (ceiling ${WARM_HELPER_MB_MAX} MB)"
fi
# A warm helper can sit through a Timed Capture countdown: it must cost nothing.
sleep 2
assert_idle_cpu "a warm helper" "$WARM_PID" 3
assert_idle_cpu "the menu bar app while the helper is warm" "$APP_PID" 2

# 2. Cancel quits a helper that never showed anything.
expect_equal "Cancel: the warm-up is cancelled" "ok" "$(send "$APP_SOCK" "editor-warm-up cancel")"
if wait_until 10 gone "$WARM_PID"; then pass "Cancel quits a helper that was never shown"; else fail "the warm helper is still running after Cancel"; fi
expect_equal "Cancel leaves the warm-up idle" "idle" "$(warm_state)"
expect_equal "no helper process at rest after Cancel" "0" "$(helper_count)"
expect_equal "the helper's Dock icon never existed and is not there now" "" "$(app_type "$WARM_PID")"

# 3. Cancel right after the Shortcut, before the helper is even up: it must still end up gone.
for round in 1 2 3; do
  send "$APP_SOCK" "editor-warm-up begin" >/dev/null
  send "$APP_SOCK" "editor-warm-up cancel" >/dev/null
  # `settle` returns once the helper has been started and told about the Cancel.
  send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
  if wait_until 15 no_helper; then
    sleep 1
    expect_equal "Cancel before the helper is up (round $round): no helper process is left" "0" "$(helper_count)"
  else
    fail "Cancel before the helper is up (round $round): a helper is still running"
    send "$EDITOR_SOCK" quit >/dev/null
    wait_until 5 no_helper
  fi
  expect_equal "Cancel before the helper is up (round $round): the warm-up is idle" "idle" "$(warm_state)"
done

# 4. Cancel while an Editor is open: the helper and the Editor stay; only the warm one goes.
if capture_into_editor "menu-click capture.screen"; then
  OPEN_N="$EDITOR_N"
  OPEN_PID="$HELPER_PID"
  send "$APP_SOCK" "editor-warm-up begin" >/dev/null
  if wait_until 10 warm_is warm; then pass "a helper with an Editor open warms the next one"; else fail "no warm-up while an Editor is open (state '$(warm_state)')"; fi
  expect_contains "the next Editor is built hidden beside the open one" "warm window=hidden" "$(send "$EDITOR_SOCK" editor-warm-state)"
  expect_equal "the open Editor is the only window" "1" "$(onscreen_windows "$OPEN_PID")"
  send "$APP_SOCK" "editor-warm-up cancel" >/dev/null
  if wait_until 10 bash -c "[[ \"\$(printf 'editor-warm-state\n' | nc -U -w 2 '$EDITOR_SOCK')\" == cold ]]"; then pass "Cancel throws the warm Editor away"; else fail "the warm Editor is still there after Cancel"; fi
  sleep 1
  expect_equal "Cancel leaves the helper running while an Editor is open" "$OPEN_PID" "$(helper_pid)"
  expect_equal "Cancel leaves the open Editor open" "$OPEN_N" "$(open_editors)"
  expect_equal "the open Editor's window is still on screen" "1" "$(onscreen_windows "$OPEN_PID")"
  send "$EDITOR_SOCK" "editor-key $OPEN_N escape" >/dev/null
  if wait_until 10 gone "$OPEN_PID"; then pass "the helper quits when the last Editor closes after a Cancel"; else fail "the helper is still running"; fi
fi

# 5. The Capture opens in the Editor that was built ahead of it, and it is quick. The helper is
#    made warm first, so the number is the warm path every time. Measured on a 5K display so
#    mapping the Capture's pixels costs what it costs for real. The number covers the Capture's
#    pixels being ready to the Editor window on screen (see `capture-timing` in docs/testing.md);
#    it is the median of three Captures.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
WARM_SAMPLES=()
for round in 1 2 3; do
  send "$APP_SOCK" "editor-warm-up begin" >/dev/null
  if ! wait_until 10 warm_is warm; then fail "timing round $round: the helper did not warm up"; continue; fi
  if capture_into_editor "press-shortcut capture-screen"; then
    TIMING="$(send "$APP_SOCK" capture-timing)"
    expect_contains "timing round $round: the Capture opened in a warm helper" "warm=yes" "$TIMING"
    expect_contains "timing round $round: the Editor was built before its Capture" "warm=yes" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
    WARM_SAMPLES+=("$(printf '%s\n' "$TIMING" | sed -n 's/.*capture-to-editor-ms=\([0-9.]*\).*/\1/p')")
    expect_equal "timing round $round: the warm Editor is on screen once it opened" "1" "$(onscreen_windows "$HELPER_PID")"
    send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
    wait_until 10 gone "$HELPER_PID"
  fi
done
WARM_MS="$(printf '%s\n' "${WARM_SAMPLES[@]}" | sort -n | sed -n '2p')"
if [[ -n "$WARM_MS" ]] && awk -v ms="$WARM_MS" -v max="$WARM_OPEN_MS_MAX" 'BEGIN { exit !(ms > 0 && ms <= max) }'; then
  pass "Capture to the Editor visible takes ${WARM_MS} ms with a warm helper (median of ${WARM_SAMPLES[*]}; about 50 ms; ceiling ${WARM_OPEN_MS_MAX} ms)"
else
  fail "Capture to the Editor visible took '${WARM_MS}' ms with a warm helper (samples ${WARM_SAMPLES[*]}; ceiling ${WARM_OPEN_MS_MAX} ms)"
fi

# The same Capture with no time to warm up: the helper is still starting when it is ready.
send "$APP_SOCK" "fixture-delay 0" >/dev/null
if capture_into_editor "press-shortcut capture-screen"; then
  TIMING="$(send "$APP_SOCK" capture-timing)"
  COLD_MS="$(printf '%s\n' "$TIMING" | sed -n 's/.*capture-to-editor-ms=\([0-9.]*\).*/\1/p')"
  pass "for comparison, Capture to the Editor visible takes ${COLD_MS} ms when the helper has no time to warm up ($TIMING)"
  expect_equal "the Capture still opens in the one helper that was started for it" "1" "$(helper_count)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi

# A Capture that fails ends without a Capture: it cancels the warm-up, the production Cancel path.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" "fixture-fail on" >/dev/null
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
send "$APP_SOCK" "fixture-fail off" >/dev/null
if wait_until 10 no_helper; then pass "a Capture that fails quits the helper that was warming up for it"; else fail "a helper is still running after a failed Capture"; fi
expect_equal "a failed Capture leaves the warm-up idle" "idle" "$(warm_state)"

# 6. Nothing is left at rest and the menu bar app is back at its baseline.
expect_equal "no helper process at rest after the warm-up flows" "0" "$(helper_count)"
sleep 1
WARM_AFTER_MB="$(footprint_mb "$APP_PID")"
if awk -v a="$WARM_AFTER_MB" -v b="$WARM_REST_MB" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app is back at its baseline after the warm-up flows (${WARM_REST_MB} MB before, ${WARM_AFTER_MB} MB after)"
else
  fail "the menu bar app went from ${WARM_REST_MB} MB to ${WARM_AFTER_MB} MB over the warm-up flows (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
assert_idle_cpu "the menu bar app after the warm-up flows" "$APP_PID" 3
send "$APP_SOCK" pasteboard-clear >/dev/null

# 7. A helper launched on its own (a Dock pin) while snapit is running: it starts nothing new,
#    shows nothing and quits. `open -n` goes through LaunchServices, as the Dock does.
if open -n -g --env "SNAPIT_TEST_ROOT=$RUN_ROOT" "$APP/Contents/Helpers/snapit Editor.app" >/dev/null 2>&1; then
  pass "LaunchServices launches the helper on its own"
else
  fail "open -n could not launch the helper on its own"
fi
if wait_until 10 some_helper; then
  PIN_PID="$(helper_pid)"
  if is_foreground "$PIN_PID"; then fail "a helper launched on its own has a Dock icon"; else pass "a helper launched on its own has no Dock icon"; fi
  expect_equal "a helper launched on its own shows no window" "0" "$(onscreen_windows "$PIN_PID")"
  if wait_until 10 gone "$PIN_PID"; then pass "a helper launched on its own through LaunchServices quits"; else fail "a helper launched on its own is still running"; fi
else
  pass "a helper launched on its own through LaunchServices already quit"
fi
expect_equal "launching the helper on its own leaves snapit running, the same process" "$APP_PID" "$(pid_of "$APP_EXE")"
if wait_until 10 one_snapit; then pass "launching the helper on its own leaves exactly one snapit"; else fail "more than one snapit process is running"; fi
expect_equal "launching the helper on its own leaves no helper process" "0" "$(helper_count)"
expect_equal "snapit is still an agent (no Dock icon)" "UIElement" "$(app_type "$APP_PID")"

# 8. The menu bar app dies (killed, crashed) while its helper is warming up: the helper, which has
#    shown nothing, goes with it. A second menu bar app under its own root, so this run's stays up.
SECOND_ROOT="$(mktemp -d /tmp/snapit-run2.XXXXXX)"
SECOND_SOCK="$SECOND_ROOT/app.sock"
(SNAPIT_TEST_ROOT="$SECOND_ROOT" nohup "$APP_EXE" >"$SECOND_ROOT/app.log" 2>&1 &)
if wait_until 10 answers "$SECOND_SOCK"; then
  SECOND_PID="$(pgrep -f "$APP_EXE" | grep -v "^$APP_PID\$" | head -1)"
  send "$SECOND_SOCK" "editor-warm-up begin" >/dev/null
  wait_until 10 bash -c "[[ \"\$(printf 'editor-warm-up state\n' | nc -U -w 2 '$SECOND_SOCK')\" == warm ]]"
  expect_equal "the second snapit's helper is warm" "1" "$(helper_count)"
  ORPHAN_PID="$(helper_pid)"
  kill -9 "$SECOND_PID" 2>/dev/null
  if wait_until 10 gone "$ORPHAN_PID"; then pass "a warm helper quits when its menu bar app is killed"; else fail "a warm helper outlived its killed menu bar app"; fi
  expect_equal "no helper process is left after the menu bar app was killed" "0" "$(helper_count)"
else
  fail "the second snapit did not start"
  pgrep -f "$APP_EXE" | grep -v "^$APP_PID\$" | xargs kill -9 2>/dev/null
fi
rm -rf "$SECOND_ROOT"
expect_equal "this run's snapit was not disturbed" "$APP_PID" "$(pid_of "$APP_EXE")"
