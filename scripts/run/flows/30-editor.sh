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
  expect_contains "the Capture is a read-only mapping in the helper" "capture-mapping=read-only" "$FACTS"

  # An Export leaves the read-only mapping behind: a copy in memory of its own carries the same
  # pixels and the display's ICC profile byte for byte.
  PROBE="$(send "$EDITOR_SOCK" "export-owned-probe $EDITOR_N")"
  if [[ "$PROBE" == ok\ * ]]; then
    PROBE_INFO="$("$INSPECT" info "${PROBE#ok }")"
    expect_equal "an owned copy of the Capture keeps the ICC profile byte for byte" "$P3_SHA" "$(png_field "$PROBE_INFO" icc_sha256)"
    expect_equal "an owned copy of the Capture has the Capture's pixels" "mismatches=0" "$("$INSPECT" verify-fixture "${PROBE#ok }" 602 374 | grep '^mismatches=')"
  else
    fail "the owned copy probe failed: $PROBE"
  fi

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
  expect_in_order "the helper has its own app menu" "$(menu_items "$MENUS" snapit)" "About snapit" "Hide snapit" "Quit snapit"
  expect_in_order "the helper's Edit menu has Copy" "$(menu_items "$MENUS" Edit)" "Copy"
  expect_in_order "the helper's Window menu has Minimize and Close" "$(menu_items "$MENUS" Window)" "Minimize" "Close"

    # Activation: a scripted run never takes focus; a normal run asks LaunchServices to bring the
  # helper forward when it launches and again when the Editor shows.
  expect_contains "test mode does not activate the helper at launch" "activate-at-launch=false" "$(send "$APP_SOCK" "activation-plan test")"
  expect_contains "test mode does not activate the helper when a Capture opens" "activate-after-open=false" "$(send "$APP_SOCK" "activation-plan test")"
  expect_contains "a normal run activates the helper at launch" "activate-at-launch=true" "$(send "$APP_SOCK" "activation-plan normal")"
  expect_contains "a normal run activates the helper when a Capture opens" "activate-after-open=true" "$(send "$APP_SOCK" "activation-plan normal")"

  # 2. Esc closes without exporting.
  send "$APP_SOCK" pasteboard-clear >/dev/null
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Esc closes the Editor and the helper quits"; else fail "the helper is still running after Esc"; fi
  expect_equal "Esc exports nothing" "" "$(send "$APP_SOCK" pasteboard-types)"
  expect_equal "the helper's Dock icon is gone after the last Editor closed" "" "$(app_type "$HELPER_PID")"
  expect_in_order "the menu bar app keeps the Last Capture's file after the Editor closed" "$(capture_files)" "capture-$EDITOR_N.pixels"
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
    expect_in_order "the newest Capture's file is kept" "$(capture_files)" "capture-$EDITOR_N.pixels"
    expect_equal "the Capture before it was replaced" "0" "$(capture_files | grep -c "^capture-$FIRST_N.pixels\$")"
    expect_equal "both Editors have a window" "2" "$(onscreen_windows "$HELPER_PID")"
    send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
    wait_until 5 bash -c "[[ \"\$(printf 'editors\n' | nc -U -w 2 '$EDITOR_SOCK')\" == '$FIRST_N' ]]"
    expect_equal "closing one Editor leaves the other open" "$FIRST_N" "$(open_editors)"
    expect_equal "the helper keeps running while an Editor is open" "$HELPER_PID" "$(helper_pid)"
    expect_equal "the first Editor still works from its mapping after its file was replaced" "pixels=602x374" "$(send "$EDITOR_SOCK" "editor-facts $FIRST_N" | grep '^pixels=')"
  fi
  send "$EDITOR_SOCK" "editor-key $FIRST_N close" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "⌘W closes the last Editor and the helper quits"; else fail "the helper is still running after its last Editor closed"; fi
fi
send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null

# 5. Delete Capture closes the Editor at once and removes the Capture file.
if capture_into_editor "menu-click capture.screen"; then
  DELETED_N="$EDITOR_N"
  send "$EDITOR_SOCK" "editor-press $EDITOR_N delete-capture" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Delete Capture closes the Editor"; else fail "the helper is still running after Delete Capture"; fi
  if wait_until 5 bash -c "[[ ! -e '$RUN_ROOT/captures/capture-$DELETED_N.pixels' ]]"; then pass "Delete Capture removes the Capture file"; else fail "the Capture file is still there after Delete Capture"; fi
fi

# 6. Warm-up seam: the Editor's window, toolbars and canvas are built without a Capture, hidden,
#    and the next Capture only has to be attached and shown. The helper stays an agent meanwhile.
send "$APP_SOCK" start-editor >/dev/null
wait_until 10 answers "$EDITOR_SOCK"
WARM_PID="$(helper_pid)"
send "$EDITOR_SOCK" editor-warm >/dev/null
expect_contains "a warm helper has built its Editor, hidden, without a Capture" "warm window=hidden canvas=built" "$(send "$EDITOR_SOCK" editor-warm-state)"
expect_equal "a warm helper is still an agent (no Dock icon)" "UIElement" "$(app_type "$WARM_PID")"
expect_equal "a warm helper has no window on screen" "0" "$(onscreen_windows "$WARM_PID")"
expect_equal "a warm helper has no Editor open" "" "$(open_editors)"
if capture_into_editor "menu-click capture.screen"; then
  expect_contains "the Capture opens in the Editor that was built ahead of it" "warm=yes" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  expect_equal "the warm helper is the one that shows it" "$WARM_PID" "$HELPER_PID"
  if wait_until 5 is_foreground "$HELPER_PID"; then pass "the helper becomes a regular app when the warm Editor shows"; else fail "the helper is not a regular app after the warm Editor showed"; fi
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "the helper quits when the warm Editor closes"; else fail "the helper is still running after the warm Editor closed"; fi
fi

# 7. Memory: the menu bar app is back at its baseline after Editors close, flat over cycles, and
#    nothing of the Capture is left behind in the helper (a new helper every time).
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
capture_into_editor "menu-click capture.screen" && copy_closes_editor   # warm up
sleep 1
CYCLE_BASELINE="$(footprint_mb "$APP_PID")"
HELPER_MIN=""
HELPER_MAX=""
for _ in 1 2 3 4 5; do
  if capture_into_editor "menu-click capture.screen"; then
    HELPER_MB="$(peak_footprint_mb "$HELPER_PID" 3)"
    if [[ -z "$HELPER_MIN" ]] || awk -v a="$HELPER_MB" -v b="$HELPER_MIN" 'BEGIN { exit !(a < b) }'; then HELPER_MIN="$HELPER_MB"; fi
    if [[ -z "$HELPER_MAX" ]] || awk -v a="$HELPER_MB" -v b="$HELPER_MAX" 'BEGIN { exit !(a > b) }'; then HELPER_MAX="$HELPER_MB"; fi
    copy_closes_editor
  fi
done
expect_memory_returns "the menu bar app's memory is flat over five Capture, Editor, Copy cycles" "$APP_PID" "$CYCLE_BASELINE" "$(pixels_mb 5120 2880)"
expect_memory_returns "the menu bar app is back near its at-rest footprint after the Editors closed" "$APP_PID" "$AT_REST" "$(pixels_mb 5120 2880)"
expect_steady_across_cycles "the helper's footprint with a 5K Editor open is the same every cycle" "$HELPER_MIN" "$HELPER_MAX" "$(pixels_mb 5120 2880)"
if [[ -z "$(helper_pid)" ]]; then pass "no helper process at rest after the Editors closed"; else fail "a helper is running at rest"; fi
expect_equal "the Last Capture's file is the only Capture file" "1" "$(capture_files | wc -l | tr -d ' ')"
send "$APP_SOCK" pasteboard-clear >/dev/null
