# Flow: Window Capture. The Shortcut (or the menu item) shows the overlay with the window under the
# pointer highlighted (the front one when windows overlap); a click captures exactly that window
# through the single-window source, which in test mode returns a fixture window image with
# transparent rounded corners. There is no Action bar in this mode, whatever "After selecting an
# Area" says. Checks the menu and Shortcut, the hover, the pixels at 1x and 2x, a window that
# crosses the display's edge (captured whole), the alpha corners in the Copy and the Save PNG (and
# in the 1x averaged ones), that opaque Captures stay RGB PNGs, Esc, a window that vanished, the
# Editor helper warming up and going, memory and idle CPU. Uses the helpers of 40-area-capture.sh
# (area_start, mouse, fact, overlay_panels, area_result). Sourced by scripts/check-run.sh.
# shellcheck shell=bash

WIN_SAVE="$RUN_ROOT/save"
win_warm_state() { send "$APP_SOCK" "editor-warm-up state"; }
win_warm_is() { [[ "$(win_warm_state)" == "$1" ]]; }
win_helper_count() { pgrep -f "$HELPER_EXE" | wc -l | tr -d ' '; }
win_no_helper() { [[ "$(win_helper_count)" == "0" ]]; }
win_file_exists() { [[ -f "$1" ]]; }
win_save_idle() { [[ "$(send "$APP_SOCK" save-pending)" == "0" ]]; }
# A setting is changed while no Editor helper runs (a helper reads settings when it starts).
win_set_default() {
  wait_until 10 win_no_helper
  send "$APP_SOCK" "defaults-set $1 $2" >/dev/null
}

# win_click <display> <x> <y>: a click at a point, as a user's would be: the pointer moves there,
# presses and lets go.
win_click() {
  mouse move "$1" "$2" "$3" >/dev/null
  mouse down "$1" "$2" "$3" >/dev/null
  mouse up "$1" "$2" "$3" >/dev/null
}

# win_png_check <label> <png> <w> <h> <scale> <phys> <profile sha> [<factor>]
# The PNG is the fixture window of w x h pixels (averaged down by <factor>, when given): an RGBA PNG
# whose every pixel, alpha included, is the window's; the four extreme corners are fully transparent
# and the middle is opaque, read by png-inspect's own decoder.
win_png_check() {
  local label="$1" file="$2" w="$3" h="$4" scale="$5" phys="$6" sha="$7" factor="${8:-1}" info verify ow oh
  ow=$((w / factor))
  oh=$((h / factor))
  info="$("$INSPECT" info "$file")"
  if ((factor > 1)); then verify="$("$INSPECT" verify-window-scaled "$file" "$w" "$h" "$scale" "$factor")"; else verify="$("$INSPECT" verify-window "$file" "$w" "$h" "$scale")"; fi
  expect_equal "$label: the PNG is ${ow}x${oh}" "${ow}x${oh}" "$(png_field "$info" width)x$(png_field "$info" height)"
  expect_equal "$label: the PNG has an alpha channel (colour type 6)" "6" "$(png_field "$info" color_type)"
  expect_equal "$label: every pixel, alpha included, is the window's" "mismatches=0" "$(printf '%s\n' "$verify" | grep '^mismatches=')"
  expect_equal "$label: the four corners are fully transparent" "0 0 0 0" \
    "$("$INSPECT" rgba-pixel "$file" 0 0 | cut -d, -f4) $("$INSPECT" rgba-pixel "$file" $((ow - 1)) 0 | cut -d, -f4) $("$INSPECT" rgba-pixel "$file" 0 $((oh - 1)) | cut -d, -f4) $("$INSPECT" rgba-pixel "$file" $((ow - 1)) $((oh - 1)) | cut -d, -f4)"
  expect_equal "$label: the middle is opaque" "255" "$("$INSPECT" rgba-pixel "$file" $((ow / 2)) $((oh / 2)) | cut -d, -f4)"
  expect_equal "$label: the display's color profile is embedded" "$sha" "$(png_field "$info" icc_sha256)"
  expect_equal "$label: pHYs records $phys pixels per metre" "$phys,$phys,1" "$(png_field "$info" phys)"
}

# win_copy_check <label> <w> <h> <scale> <phys> <sha> [<factor>]: Copies the Capture open in the Editor
# and checks the PNG that lands on the pasteboard.
win_copy_check() {
  expect_contains "$1: the Editor shows the window at native pixels" "pixels=${2}x${3}" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  send "$APP_SOCK" pasteboard-clear >/dev/null
  if copy_closes_editor; then pass "$1: ⌘C copies and the Editor closes"; else fail "$1: the Editor helper is still running after ⌘C"; fi
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/window.png" >/dev/null
  win_png_check "$1 (Copy)" "$RUN_ROOT/window.png" "$2" "$3" "$4" "$5" "$6" "${7:-1}"
  rm -f "$RUN_ROOT/window.png"
}

# win_save_check <label> <w> <h> <scale> <phys> <sha> [<factor>]: Saves the Capture open in the Editor
# and checks the file that lands in the Save location.
win_save_check() {
  local name
  mkdir -p "$WIN_SAVE"
  find "$WIN_SAVE" -mindepth 1 -delete 2>/dev/null
  name="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  wait_until 10 gone "$HELPER_PID"
  if wait_until 15 win_file_exists "$WIN_SAVE/$name"; then pass "$1: Save writes $name"; else fail "$1: no $name in the Save location"; fi
  wait_until 15 win_save_idle
  win_png_check "$1 (Save)" "$WIN_SAVE/$name" "$2" "$3" "$4" "$5" "$6" "${7:-1}"
  find "$WIN_SAVE" -mindepth 1 -delete 2>/dev/null
}

SRGB_SHA_WIN="$("$INSPECT" profile-sha srgb)"
P3_SHA_WIN="$("$INSPECT" profile-sha displayP3)"
WIN_AT_REST="$(footprint_mb "$APP_PID")"
send "$APP_SOCK" "fixture-extra-display none" >/dev/null
send "$APP_SOCK" "fixture-window-fail off" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
win_set_default afterSelectingArea captureOnRelease
win_set_default exportStandardResolution false
win_set_default closeEditorAfterSave true

# 1. The menu item and the Shortcut exist, in the right order.
expect_in_order "the menu offers Capture Area, Capture Window, Capture Screen in that order" "$(send "$APP_SOCK" menu-titles)" "Capture Area" "Capture Window" "Capture Screen"
expect_equal "Window Shortcut defaults to control-option-command-5" "23 control,option,command" "$(send "$APP_SOCK" "shortcut-combo capture-window")"
expect_equal "the menu item shows the Window Shortcut" "5 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.window")"
expect_in_order "the Window Shortcut is bound" "$(send "$APP_SOCK" bound-shortcuts)" "capture-window"

# 2. The overlay: the window under the pointer is highlighted, the front one when they overlap. The
#    fixture's windows: front #9001 at 60,40 100x60 over back #9004 at 20,20 200x130.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
expect_equal "no helper process at rest before the Window Capture" "0" "$(win_helper_count)"
expect_equal "the Shortcut shows the overlay" "ok" "$(area_start "press-shortcut capture-window")"
expect_equal "one overlay panel covers the display" "1" "$(overlay_panels | grep -c '^301x187 ')"
expect_equal "it is the window overlay" "window" "$(fact mode)"
if wait_until 10 win_warm_is warm; then pass "the Editor helper warms up while the overlay shows"; else fail "no warm helper while the overlay shows (state '$(win_warm_state)')"; fi
WIN_WARM_PID="$(helper_pid)"
expect_equal "the warm helper is an agent with no window on screen" "UIElement 0" "$(app_type "$WIN_WARM_PID") $(onscreen_windows "$WIN_WARM_PID")"
mouse move 0 10 10 >/dev/null
expect_equal "no window under the pointer: nothing highlighted" "none none" "$(fact hover) $(fact hover-window)"
mouse move 0 30 30 >/dev/null
expect_equal "the pointer over the back window highlights it" "20,20 200x130 9004" "$(fact hover) $(fact hover-window)"
mouse move 0 70 50 >/dev/null
expect_equal "the pointer over the front window highlights it, not the one behind" "60,40 100x60 9001" "$(fact hover) $(fact hover-window)"
expect_equal "there is no crosshair or loupe" "hidden" "$(fact loupe)"
send "$APP_SOCK" "overlay-snapshot 0 $RUN_ROOT/overlay.png" >/dev/null
read -r R G B <<<"$("$INSPECT" pixel "$RUN_ROOT/overlay.png" 290 14)"
if awk -v r="$R" 'BEGIN { exit !(r >= 143 && r <= 152) }'; then pass "the screen outside the highlighted window is dimmed"; else fail "outside the window got $R,$G,$B, not dimmed"; fi
read -r R G B <<<"$("$INSPECT" pixel "$RUN_ROOT/overlay.png" 150 60)"
if awk -v r="$R" -v g="$G" -v b="$B" 'BEGIN { exit !(r >= 125 && r <= 129 && g >= 80 && g <= 84 && b >= 198 && b <= 202) }'; then pass "the highlighted window shows the frozen pixels undimmed ($R,$G,$B)"; else fail "inside the highlighted window got $R,$G,$B"; fi
rm -f "$RUN_ROOT/overlay.png"

# A drag selects nothing, there is no Action bar, and Return does nothing.
mouse down 0 30 30 >/dev/null
mouse drag 0 100 100 >/dev/null
expect_equal "a drag makes no selection" "none" "$(fact selection | sed 's/^[^ ]* //')"
expect_equal "and shows no handles or Action bar" "0 none" "$(fact handles) $(fact action-bar)"
mouse move 0 10 170 >/dev/null
mouse up 0 10 170 >/dev/null
expect_equal "letting go over no window captures nothing" "1" "$(overlay_panels | grep -c '^301x187 ')"
send "$APP_SOCK" "overlay-key enter" >/dev/null
expect_equal "Return does nothing" "1" "$(overlay_panels | grep -c '^301x187 ')"
FILES_BEFORE="$(capture_files)"
win_click 0 10 170
expect_equal "a click on empty desktop does nothing" "1" "$(overlay_panels | grep -c '^301x187 ')"
expect_equal "and makes no Capture file" "$FILES_BEFORE" "$(capture_files)"

# 3. A click captures exactly that window: 100 x 60 pixels at 1x, transparent corners, sRGB.
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
mouse up 0 70 50 >/dev/null
if area_result; then pass "a click on the highlighted window captures it: Capture $EDITOR_N opens in the Editor"; else fail "the window click finished with '$AREA_REPLY'"; fi
expect_equal "the overlay is gone once the Capture is taken" "" "$(overlay_panels)"
if [[ -n "${EDITOR_N:-}" ]]; then
  win_copy_check "front window at 1x" 100 60 1 2835 "$SRGB_SHA_WIN"
fi
expect_equal "the Copy leaves the Shortcut working: no helper is left" "0" "$(win_helper_count)"

# 4. At 2x (Display P3): the window is captured at the display's native pixels, 200 x 120.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
area_start "menu-click capture.window" >/dev/null
expect_equal "the menu item shows the overlay too" "1" "$(overlay_panels | grep -c '^301x187 ')"
win_click 0 70 50
if area_result; then pass "2x: Capture $EDITOR_N opens in the Editor"; else fail "2x: the Capture finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  win_copy_check "front window at 2x" 200 120 2 5669 "$P3_SHA_WIN"
fi

# 5. The back window, partly covered by the front one, is captured whole (the pixels at 2x are its
#    own, not the front window's); a window crossing the display's edge is captured whole too.
area_start "press-shortcut capture-window" >/dev/null
win_click 0 30 30
if area_result; then pass "the back window is captured"; else fail "the back window's Capture finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then win_copy_check "back window at 2x" 400 260 2 5669 "$P3_SHA_WIN"; fi
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
area_start "press-shortcut capture-window" >/dev/null
mouse move 0 5 50 >/dev/null
expect_equal "the window that crosses the display's edge is highlighted, cut at the edge" "0,30 20x60 9002" "$(fact hover) $(fact hover-window)"
win_click 0 5 50
if area_result; then pass "the window that crosses the display's edge is captured"; else fail "its Capture finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then win_copy_check "edge-crossing window at 1x (the whole 80 x 60 window)" 80 60 1 2835 "$SRGB_SHA_WIN"; fi

# 6. Save: the same alpha reaches the Saved file, at 2x and averaged down to 1x ("Export at
#    standard resolution"), and Copy averages the same way.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
area_start "press-shortcut capture-window" >/dev/null
win_click 0 70 50
if area_result; then win_save_check "front window at 2x" 200 120 2 5669 "$P3_SHA_WIN"; else fail "the Capture for Save finished with '$AREA_REPLY'"; fi
win_set_default exportStandardResolution true
area_start "press-shortcut capture-window" >/dev/null
win_click 0 70 50
if area_result; then win_save_check "front window with 1x export" 200 120 2 2835 "$P3_SHA_WIN" 2; else fail "the Capture for the 1x Save finished with '$AREA_REPLY'"; fi
area_start "press-shortcut capture-window" >/dev/null
win_click 0 70 50
if area_result; then win_copy_check "front window with 1x export" 200 120 2 2835 "$P3_SHA_WIN" 2; else fail "the Capture for the 1x Copy finished with '$AREA_REPLY'"; fi
win_set_default exportStandardResolution false

# 7. Annotations over the transparent corners: a Rectangle drawn across the top-left corner is
#    composited over the alpha (the corner pixel under it becomes opaque, the far corner stays clear).
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
area_start "press-shortcut capture-window" >/dev/null
win_click 0 70 50
if area_result; then
  send "$EDITOR_SOCK" "editor-keystroke $EDITOR_N r" >/dev/null
  send "$EDITOR_SOCK" "editor-drag $EDITOR_N 0 0 30 30" >/dev/null
  send "$APP_SOCK" pasteboard-clear >/dev/null
  copy_closes_editor
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/window.png" >/dev/null
  expect_equal "an Annotation over a transparent corner is opaque there (alpha at 1,1)" "255" "$("$INSPECT" rgba-pixel "$RUN_ROOT/window.png" 1 1 | cut -d, -f4)"
  expect_equal "the far corner stays transparent" "0" "$("$INSPECT" rgba-pixel "$RUN_ROOT/window.png" 99 59 | cut -d, -f4)"
  expect_equal "the PNG is still RGBA" "6" "$(png_field "$("$INSPECT" info "$RUN_ROOT/window.png")" color_type)"
  rm -f "$RUN_ROOT/window.png"
else
  fail "the Capture for the Annotation check finished with '$AREA_REPLY'"
fi

# 7b. A Redaction over the transparent corner pixelates premultiplied pixels: the tile there is
#     partly transparent (neither clear nor opaque), and the far corner is untouched.
area_start "press-shortcut capture-window" >/dev/null
win_click 0 70 50
if area_result; then
  send "$EDITOR_SOCK" "editor-keystroke $EDITOR_N x" >/dev/null
  send "$EDITOR_SOCK" "editor-drag $EDITOR_N 0 0 30 30" >/dev/null
  send "$APP_SOCK" pasteboard-clear >/dev/null
  copy_closes_editor
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/window.png" >/dev/null
  REDACTED_ALPHA="$("$INSPECT" rgba-pixel "$RUN_ROOT/window.png" 1 1 | cut -d, -f4)"
  if ((REDACTED_ALPHA > 0 && REDACTED_ALPHA < 255)); then pass "a Redaction over the corner leaves a partly transparent tile (alpha $REDACTED_ALPHA at 1,1)"; else fail "the Redaction's tile at the corner has alpha $REDACTED_ALPHA (expected between 0 and 255)"; fi
  expect_equal "the far corner is untouched by the Redaction" "0" "$("$INSPECT" rgba-pixel "$RUN_ROOT/window.png" 99 59 | cut -d, -f4)"
  expect_equal "the Redaction's PNG is RGBA" "6" "$(png_field "$("$INSPECT" info "$RUN_ROOT/window.png")" color_type)"
  rm -f "$RUN_ROOT/window.png"
else
  fail "the Capture for the Redaction check finished with '$AREA_REPLY'"
fi

# 7c. A Crop keeps the alpha of what is left: cut to the top-left 60 x 40 points, the corner is still
#     clear and the inside is opaque.
area_start "press-shortcut capture-window" >/dev/null
win_click 0 70 50
if area_result; then
  send "$EDITOR_SOCK" "editor-keystroke $EDITOR_N c" >/dev/null
  send "$EDITOR_SOCK" "editor-drag $EDITOR_N 100 60 60 40" >/dev/null
  send "$EDITOR_SOCK" "editor-keystroke $EDITOR_N enter" >/dev/null
  send "$APP_SOCK" pasteboard-clear >/dev/null
  copy_closes_editor
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/window.png" >/dev/null
  WIN_CROP_INFO="$("$INSPECT" info "$RUN_ROOT/window.png")"
  expect_equal "the cropped window is 60 x 40, colour type 6" "60x40 6" "$(png_field "$WIN_CROP_INFO" width)x$(png_field "$WIN_CROP_INFO" height) $(png_field "$WIN_CROP_INFO" color_type)"
  expect_equal "the corner of the cropped window is still transparent" "0" "$("$INSPECT" rgba-pixel "$RUN_ROOT/window.png" 0 0 | cut -d, -f4)"
  expect_equal "and its inside is opaque, with the window's own colour there" "255" "$("$INSPECT" rgba-pixel "$RUN_ROOT/window.png" 59 39 | cut -d, -f4)"
  rm -f "$RUN_ROOT/window.png"
else
  fail "the Capture for the Crop check finished with '$AREA_REPLY'"
fi

# 8. Opaque Captures keep producing RGB PNGs: a Screen Capture, an Area (also from a frozen frame
#    with no alpha channel), and a window-sized crop of one.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
if capture_into_editor "press-shortcut capture-screen"; then
  send "$APP_SOCK" pasteboard-clear >/dev/null
  copy_closes_editor
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/opaque.png" >/dev/null
  expect_equal "a Screen Capture's PNG is RGB (colour type 2)" "2" "$(png_field "$("$INSPECT" info "$RUN_ROOT/opaque.png")" color_type)"
else
  fail "the Screen Capture finished without opening the Editor"
fi
for layout in alpha-first skip-first; do
  send "$APP_SOCK" "fixture-pixel-layout $layout" >/dev/null
  area_start "press-shortcut capture-area" >/dev/null
  area_drag 0 20 30 120 90
  if area_result; then
    send "$APP_SOCK" pasteboard-clear >/dev/null
    copy_closes_editor
    send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/opaque.png" >/dev/null
    expect_equal "an Area Capture of a $layout frame is an RGB PNG (colour type 2)" "2" "$(png_field "$("$INSPECT" info "$RUN_ROOT/opaque.png")" color_type)"
  else
    fail "the $layout Area Capture finished with '$AREA_REPLY'"
  fi
done
send "$APP_SOCK" "fixture-pixel-layout alpha-first" >/dev/null
rm -f "$RUN_ROOT/opaque.png"

# 9. No Action bar in Window mode, even with "After selecting an Area" at Show Action bar (the default).
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
win_set_default afterSelectingArea showActionBar
area_start "press-shortcut capture-window" >/dev/null
expect_equal "the setting is Show Action bar" "showActionBar" "$(fact after-selecting)"
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
expect_equal "pressing on a window shows no Action bar" "none" "$(fact action-bar)"
mouse up 0 70 50 >/dev/null
if area_result; then pass "with Show Action bar on, a click still captures the window straight away"; else fail "the click finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then win_copy_check "front window, Show Action bar" 100 60 1 2835 "$SRGB_SHA_WIN"; fi
win_set_default afterSelectingArea captureOnRelease

# 10. Esc cancels: nothing is captured, the helper that warmed up goes, the Shortcut works again.
FILES_BEFORE="$(capture_files)"
send "$APP_SOCK" pasteboard-clear >/dev/null
area_start "press-shortcut capture-window" >/dev/null
wait_until 10 win_warm_is warm
WIN_WARM_PID="$(helper_pid)"
mouse move 0 70 50 >/dev/null
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone after Esc" "" "$(overlay_panels)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
if wait_until 10 gone "$WIN_WARM_PID"; then pass "Esc quits the helper that was warming up"; else fail "the warm helper is still running after Esc"; fi
expect_equal "Esc leaves the warm-up idle and no helper process" "idle 0" "$(win_warm_state) $(win_helper_count)"
expect_equal "no Editor opened and no Capture file was made" "$FILES_BEFORE" "$(capture_files)"
expect_equal "a cancelled Capture puts nothing on the pasteboard" "" "$(send "$APP_SOCK" pasteboard-types)"
area_start "press-shortcut capture-window" >/dev/null
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels in the middle of a press, and the Shortcut works again" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone" "" "$(overlay_panels)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 win_no_helper

# A display change ends the overlay the same way.
area_start "press-shortcut capture-window" >/dev/null
expect_equal "a display change cancels the Window Capture" "ok" "$(send "$APP_SOCK" overlay-screens-changed)"
expect_equal "and ends it as cancelled" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 win_no_helper

# 11. A window that is gone by the time of the click is a failed Capture: no Editor, no helper left.
area_start "press-shortcut capture-window" >/dev/null
wait_until 10 win_warm_is warm
send "$APP_SOCK" "fixture-window-fail on" >/dev/null
win_click 0 70 50
REPLY="$(send_slow "$APP_SOCK" overlay-wait)"
send "$APP_SOCK" "fixture-window-fail off" >/dev/null
expect_equal "a vanished window is reported as a failed Capture" "failed" "$(printf '%s\n' "$REPLY" | cut -d' ' -f1)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
if wait_until 10 win_no_helper; then pass "a failed Window Capture quits the helper that was warming up"; else fail "the helper is still running after a failed Window Capture"; fi
expect_equal "and leaves the warm-up idle, with no Editor open" "idle" "$(win_warm_state)"
expect_equal "the Shortcut works again" "1" "$(area_start "press-shortcut capture-window" >/dev/null; overlay_panels | grep -c '^301x187 ')"
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 win_no_helper

# 12. Memory returns to baseline over repeated Window Captures, nothing runs while the overlay is up
#     or after it, and hovering does not poll. A 2560 x 1600 pixel display (16 MB of pixels).
send "$APP_SOCK" "fixture-display 2 1280 800" >/dev/null
area_start "press-shortcut capture-window" >/dev/null
win_click 0 70 50
area_result && copy_closes_editor   # warm up allocator pools
sleep 1
WIN_BASELINE="$(footprint_mb "$APP_PID")"
WIN_PEAK=0
for _ in 1 2 3 4 5; do
  area_start "press-shortcut capture-window" >/dev/null
  mouse move 0 70 50 >/dev/null
  NOW="$(footprint_mb "$APP_PID")"
  WIN_PEAK="$(awk -v a="$WIN_PEAK" -v b="$NOW" 'BEGIN { print (b > a ? b : a) }')"
  win_click 0 70 50
  area_result && copy_closes_editor
done
sleep 1
WIN_AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$WIN_AFTER" -v b="$WIN_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory returns to baseline after five Window Captures (${WIN_BASELINE} MB before, ${WIN_AFTER} MB after)"
else
  fail "memory grew from ${WIN_BASELINE} MB to ${WIN_AFTER} MB over five Window Captures (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
if awk -v a="$WIN_AFTER" -v b="$WIN_AT_REST" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory is back near the at-rest footprint (${WIN_AT_REST} MB at rest, ${WIN_AFTER} MB after)"
else
  fail "memory is ${WIN_AFTER} MB after the Window Captures, ${WIN_AT_REST} MB at rest (limit +${FOOTPRINT_FROM_REST_MB_MAX} MB)"
fi
if awk -v peak="$WIN_PEAK" -v base="$WIN_BASELINE" 'BEGIN { exit !(peak - base <= 16 + 10) }'; then
  pass "the window overlay holds the frozen frame once: peak ${WIN_PEAK} MB over a ${WIN_BASELINE} MB base, a frame of 16 MB"
else
  fail "the window overlay's peak is ${WIN_PEAK} MB over a ${WIN_BASELINE} MB base: more than one copy of a 16 MB frame"
fi
area_start "press-shortcut capture-window" >/dev/null
mouse move 0 70 50 >/dev/null
UPDATES_BEFORE="$(fact scene-updates)"
assert_idle_cpu "the menu bar app with the window overlay up" "$APP_PID" 3
expect_equal "an idle overlay updates nothing (no polling)" "$UPDATES_BEFORE" "$(fact scene-updates)"
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 win_no_helper
assert_idle_cpu "the menu bar app after the Window Captures" "$APP_PID" 3
expect_equal "no helper process is left after the Window Capture checks" "0" "$(win_helper_count)"
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
