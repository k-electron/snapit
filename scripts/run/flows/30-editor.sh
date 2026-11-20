# Flow: the Editor. A Capture opens an Editor window in the helper, which turns into a regular
# app (Dock icon) while a window shows and quits when the last one closes. The pixels reach the
# helper through a memory-mapped file. ⌘C copies and closes, Esc closes without exporting,
# Delete Capture closes and removes the Capture. Sourced by scripts/check-run.sh.
# shellcheck shell=bash

send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
expect_equal "no Editor helper runs before the first Capture" "" "$(helper_pid)"

# 1. A Capture opens the Editor.
if capture_into_editor "menu-click capture.screen"; then
  pass "a Capture opens an Editor in the helper"
  FACTS="$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  expect_contains "the Editor window is visible" "window=visible" "$FACTS"
  expect_contains "the Editor shows the Capture at its native pixel size" "pixels=602x374" "$FACTS"
  expect_contains "the Editor knows the display's scale" "scale=2.0" "$FACTS"
  expect_contains "the canvas is layer-hosted" "canvas=layer-hosted" "$FACTS"
  expect_contains "the Select tool is active" "tool=select" "$FACTS"
  expect_contains "the helper is a regular app while its window shows" "activation=regular" "$FACTS"

  # The process and window facts, from outside.
  if wait_until 5 is_foreground "$HELPER_PID"; then pass "the helper has a Dock icon and a Cmd-Tab entry while the Editor is open (application type Foreground)"; else fail "the helper is '$(app_type "$HELPER_PID")' while the Editor is open, expected Foreground"; fi
  if wait_until 5 has_onscreen_window "$HELPER_PID"; then pass "the Editor window is on screen according to the window server"; else fail "the window server lists no on-screen window for the helper"; fi
  expect_equal "the Editor is the helper's only window" "1" "$(onscreen_windows "$HELPER_PID")"
  expect_equal "the menu bar app stays an agent while the Editor is open" "UIElement" "$(app_type "$APP_PID")"

  # The pixels travel through a memory-mapped file, never over the socket.
  CAPTURE_FILE="$RUN_ROOT/captures/capture-$EDITOR_N.pixels"
  if [[ -f "$CAPTURE_FILE" ]]; then pass "the Capture is a file in the private cache folder"; else fail "no Capture file at $CAPTURE_FILE"; fi
  if lsof -p "$HELPER_PID" 2>/dev/null | grep -q "capture-$EDITOR_N.pixels"; then pass "the helper has the Capture file memory-mapped"; else fail "the helper does not map the Capture file"; fi
  if lsof -p "$APP_PID" 2>/dev/null | grep -q "capture-$EDITOR_N.pixels"; then fail "the menu bar app still maps the Capture file"; else pass "the menu bar app holds no mapping of the Capture afterwards"; fi
  expect_equal "the Capture file is private to the user (mode 600)" "600" "$(stat -f '%Lp' "$CAPTURE_FILE")"
  expect_equal "the cache folder for Captures is private to the user (mode 700)" "700" "$(stat -f '%Lp' "$RUN_ROOT/captures")"

  # Every control has a tooltip; the registries list what the Editor offers, in order.
  TOOLBAR="$(send "$EDITOR_SOCK" "editor-toolbar $EDITOR_N")"
  expect_contains "the Select tool has its tooltip" "tool select 100 Select (V)" "$TOOLBAR"
  expect_contains "Copy has its tooltip" "item copy export Copy (⌘C)" "$TOOLBAR"
  expect_contains "Delete Capture has its tooltip" "item delete-capture destructive Delete Capture" "$TOOLBAR"
  NO_TOOLTIP="$(printf '%s\n' "$TOOLBAR" | awk 'NF < 4' | wc -l | tr -d ' ')"
  expect_equal "every tool and toolbar item has a tooltip" "0" "$NO_TOOLTIP"
  expect_in_order "the Export pipeline runs crop, Redactions, Annotations, 1x, PNG" \
    "$(send "$EDITOR_SOCK" export-stages)" "crop" "redaction" "annotations" "standard-resolution" "png"

  # While regular, the helper has its own menus in the menu bar.
  MENUS="$(send "$EDITOR_SOCK" main-menu)"
  expect_contains "the helper has its own app menu" "snapit: About snapit|-|Hide snapit|-|Quit snapit" "$MENUS"
  expect_contains "the helper's Edit menu has Copy" "Edit: Copy" "$MENUS"
  expect_contains "the helper's Window menu has Minimize and Close" "Window: Minimize|Close" "$MENUS"

  # An open Editor costs nothing at rest.
  sleep 2
  assert_idle_cpu "the Editor helper with an Editor open" "$HELPER_PID" 5
  assert_idle_cpu "the menu bar app with an Editor open" "$APP_PID" 3

  # 2. Esc closes without exporting.
  send "$APP_SOCK" pasteboard-clear >/dev/null
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Esc closes the Editor and the helper quits"; else fail "the helper is still running after Esc"; fi
  expect_equal "Esc exports nothing" "" "$(send "$APP_SOCK" pasteboard-types)"
  expect_equal "the helper's Dock icon is gone after the last Editor closed" "" "$(app_type "$HELPER_PID")"
  expect_equal "the menu bar app keeps the Last Capture's file after the Editor closed" "capture-$EDITOR_N.pixels" "$(ls "$RUN_ROOT/captures")"
fi

# 3. Close after Copy off: the Editor stays, the PNG is on the pasteboard.
send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
if capture_into_editor "press-shortcut capture-screen"; then
  expect_equal "the second Editor is shown by a regular app" "regular" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N" | sed -n 's/^activation=//p')"
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N copy" >/dev/null
  expect_equal "Copy puts a PNG on the pasteboard" "public.png" "$(send "$APP_SOCK" pasteboard-types | head -1)"
  expect_equal "the Editor stays open after Copy when close after Copy is off" "$EDITOR_N" "$(open_editors | tail -1)"
  expect_equal "the helper is still running" "$HELPER_PID" "$(helper_pid)"

  # 4. Two Captures: a second Editor opens in the same helper; the helper quits only with the last.
  FIRST_N="$EDITOR_N"
  send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null
  if capture_into_editor "menu-click capture.screen"; then
    expect_equal "a second Editor opens in the same helper" "$HELPER_PID" "$(helper_pid)"
    expect_equal "two Editors are open" "2" "$(open_editors | grep -c .)"
    expect_equal "only the newest Capture's file is kept" "capture-$EDITOR_N.pixels" "$(ls "$RUN_ROOT/captures")"
    expect_equal "both Editors have a window" "2" "$(onscreen_windows "$HELPER_PID")"
    send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
    wait_until 5 bash -c "[[ \"\$(printf 'editors\n' | nc -U -w 2 '$EDITOR_SOCK')\" == '$FIRST_N' ]]"
    expect_equal "closing one Editor leaves the other open" "$FIRST_N" "$(open_editors)"
    expect_equal "the helper keeps running while an Editor is open" "$HELPER_PID" "$(helper_pid)"
    expect_equal "the first Editor still works from its mapping after its file was replaced" "pixels=602x374" "$(send "$EDITOR_SOCK" "editor-facts $FIRST_N" | grep '^pixels=')"
  fi
  send "$EDITOR_SOCK" "editor-key $FIRST_N escape" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "the helper quits when its last Editor closes"; else fail "the helper is still running after its last Editor closed"; fi
fi
send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null

# 5. Delete Capture closes the Editor at once and removes the Capture file.
if capture_into_editor "menu-click capture.screen"; then
  DELETED_N="$EDITOR_N"
  send "$EDITOR_SOCK" "editor-press $EDITOR_N delete-capture" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Delete Capture closes the Editor"; else fail "the helper is still running after Delete Capture"; fi
  if wait_until 5 bash -c "[[ ! -e '$RUN_ROOT/captures/capture-$DELETED_N.pixels' ]]"; then pass "Delete Capture removes the Capture file"; else fail "the Capture file is still there after Delete Capture"; fi
fi

# 6. Memory: the menu bar app is back at its baseline after Editors close, flat over cycles, and
#    nothing of the Capture is left behind in the helper (a new helper every time).
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
capture_into_editor "menu-click capture.screen" && copy_closes_editor   # warm up
sleep 1
CYCLE_BASELINE="$(footprint_mb "$APP_PID")"
HELPER_MIN=""
HELPER_MAX=""
for _ in 1 2 3 4 5; do
  if capture_into_editor "menu-click capture.screen"; then
    sleep 1
    HELPER_MB="$(footprint_mb "$HELPER_PID")"
    if [[ -z "$HELPER_MIN" ]] || awk -v a="$HELPER_MB" -v b="$HELPER_MIN" 'BEGIN { exit !(a < b) }'; then HELPER_MIN="$HELPER_MB"; fi
    if [[ -z "$HELPER_MAX" ]] || awk -v a="$HELPER_MB" -v b="$HELPER_MAX" 'BEGIN { exit !(a > b) }'; then HELPER_MAX="$HELPER_MB"; fi
    copy_closes_editor
  fi
done
sleep 1
CYCLE_AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$CYCLE_AFTER" -v b="$CYCLE_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app's memory is flat over five Capture, Editor, Copy cycles (${CYCLE_BASELINE} MB before, ${CYCLE_AFTER} MB after)"
else
  fail "the menu bar app's memory went from ${CYCLE_BASELINE} MB to ${CYCLE_AFTER} MB over five Editor cycles (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
if awk -v a="$CYCLE_AFTER" -v b="$AT_REST" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app is back near its at-rest footprint after the Editors closed (${AT_REST} MB at rest, ${CYCLE_AFTER} MB after)"
else
  fail "the menu bar app is at ${CYCLE_AFTER} MB after the Editors closed, ${AT_REST} MB at rest (limit +${FOOTPRINT_FROM_REST_MB_MAX} MB)"
fi
if awk -v lo="$HELPER_MIN" -v hi="$HELPER_MAX" 'BEGIN { exit !(lo > 0 && hi - lo <= 15) }'; then
  pass "the helper's footprint with a 5K Editor open is the same every cycle (${HELPER_MIN} to ${HELPER_MAX} MB)"
else
  fail "the helper's footprint with a 5K Editor open varies from ${HELPER_MIN} to ${HELPER_MAX} MB"
fi
if [[ -z "$(helper_pid)" ]]; then pass "no helper process at rest after the Editors closed"; else fail "a helper is running at rest"; fi
expect_equal "the Last Capture's file is the only Capture file" "1" "$(ls "$RUN_ROOT/captures" | wc -l | tr -d ' ')"
assert_idle_cpu "menu bar app after the Editor cycles" "$APP_PID" 5
send "$APP_SOCK" pasteboard-clear >/dev/null
