# Flow: Area Capture with "After selecting an Area" at Capture on release. The Shortcut (or the menu item) freezes the fixture
# display and shows the overlay; synthetic mouse events (real NSEvents sent to the overlay's
# panel) drag out an Area, and letting go crops the frozen frame in the engine and opens the
# Editor. Checks the overlay as the window server and a rendered snapshot show it, the crop pixel
# by pixel at 1x and 2x (with fractional point positions), Esc, the 3 pt click threshold, a
# highlighted window, a second display of another scale and memory. Sourced by
# scripts/check-run.sh.
# shellcheck shell=bash

area_start() { send_slow "$APP_SOCK" "$1"; }
mouse() { send "$APP_SOCK" "overlay-mouse $*"; }
fact() { send "$APP_SOCK" overlay-facts | sed -n "s/^$1=//p"; }
# overlay_panels: the window server's list of the app's windows at the overlay's level. The list lags
# AppKit's orderFront and orderOut when the machine is busy (a panel still there after the overlay
# ended, not yet there after a Shortcut returned), so this reads it until it agrees with how many
# such windows the app itself has ordered in.
overlay_panels() {
  local want lines deadline=$((SECONDS + 20))
  while :; do
    want="$(send "$APP_SOCK" overlay-window-count)"
    lines="$("$INSPECT" overlay-windows "$APP_PID")"
    [[ "$(printf '%s' "$lines" | grep -c .)" == "$want" || SECONDS -ge deadline ]] && break
    sleep 0.1
  done
  [[ -z "$lines" ]] || printf '%s\n' "$lines"
}

# scene_updates_quiet: the overlay's scene has stopped redrawing (a move's own redraw can land late on a busy
# machine, so the count an idle check starts from is read once this holds).
scene_updates_quiet() {
  local before after
  before="$(fact scene-updates)"
  sleep 0.3
  after="$(fact scene-updates)"
  [[ "$before" == "$after" ]]
}

# Drags from (x1, y1) to (x2, y2) on one display, in points from its top-left corner, in a few
# steps, and lets go.
area_drag() {
  local display="$1" x1="$2" y1="$3" x2="$4" y2="$5"
  mouse move "$display" "$x1" "$y1" >/dev/null
  mouse down "$display" "$x1" "$y1" >/dev/null
  mouse drag "$display" "$(awk -v a="$x1" -v b="$x2" 'BEGIN { print (a + b) / 2 }')" "$(awk -v a="$y1" -v b="$y2" 'BEGIN { print (a + b) / 2 }')" >/dev/null
  mouse drag "$display" "$x2" "$y2" >/dev/null
  mouse up "$display" "$x2" "$y2" >/dev/null
}

# area_result: waits for the overlay to finish; sets EDITOR_N and HELPER_PID when Capture N opened.
area_result() {
  local reply
  # Nothing is left from the Capture before: a Capture that did not open must not read as the one that did.
  EDITOR_N=""
  HELPER_PID=""
  reply="$(send_slow "$APP_SOCK" overlay-wait)"
  AREA_REPLY="$reply"
  if [[ "$reply" == opened\ * ]]; then
    EDITOR_N="${reply#opened }"
    HELPER_PID="$(helper_pid)"
    return 0
  fi
  return 1
}

# area_png_check <label> <scale> <crop w> <crop h> <full w> <full h> <x> <y> <profile name> <profile sha> <pHYs>
# Copies the Capture open in the Editor and checks the PNG is that crop of the fixture, pixel by
# pixel, with the display's profile and the right resolution.
area_png_check() {
  local label="$1" scale="$2" cw="$3" ch="$4" fw="$5" fh="$6" x="$7" y="$8" profile="$9" sha="${10}" phys="${11}" info
  expect_contains "$label: the Editor shows the crop at native pixels" "pixels=${cw}x${ch}" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  send "$APP_SOCK" pasteboard-clear >/dev/null
  if copy_closes_editor; then pass "$label: ⌘C copies and the Editor closes"; else fail "$label: the Editor helper is still running after ⌘C"; fi
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/area.png" >/dev/null
  info="$("$INSPECT" info "$RUN_ROOT/area.png")"
  expect_equal "$label: the PNG is ${cw}x${ch}" "${cw}x${ch}" "$(png_field "$info" width)x$(png_field "$info" height)"
  expect_equal "$label: every pixel is the fixture's pixel at that place (offset $x,$y)" "mismatches=0" \
    "$("$INSPECT" verify-fixture "$RUN_ROOT/area.png" "$cw" "$ch" "$fw" "$fh" "$x" "$y" | grep '^mismatches=')"
  expect_equal "$label: the display's color profile is embedded" "$sha" "$(png_field "$info" icc_sha256)"
  expect_equal "$label: the profile is $profile" "$profile" "$(png_field "$info" profile_name)"
  expect_equal "$label: pHYs records $((72 * scale)) dpi" "$phys,$phys,1" "$(png_field "$info" phys)"
  rm -f "$RUN_ROOT/area.png"
}

# This flow is the Capture on release behaviour: letting go takes the Capture. (The Action bar, the
# default, has its own flow, 42-action-bar.sh.)
send "$APP_SOCK" "defaults-set afterSelectingArea captureOnRelease" >/dev/null

SRGB_SHA_AREA="$("$INSPECT" profile-sha srgb)"
P3_SHA_AREA="$("$INSPECT" profile-sha displayP3)"
AREA_AT_REST="$(footprint_mb "$APP_PID")"

# 1. The menu item and the Shortcut exist, in the right order.
expect_in_order "the menu offers Capture Area before Capture Screen" "$(send "$APP_SOCK" menu-titles)" "Capture Area" "Capture Screen"
expect_equal "Area Shortcut defaults to control-option-command-4" "21 control,option,command" "$(send "$APP_SOCK" "shortcut-combo capture-area")"
expect_equal "the menu item shows the Area Shortcut" "4 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.area")"
expect_in_order "the Area Shortcut is bound" "$(send "$APP_SOCK" bound-shortcuts)" "capture-area"

# 2. The overlay at 1x: what the window server and the facts say.
send "$APP_SOCK" "fixture-extra-display none" >/dev/null
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
expect_equal "no overlay is showing before the Shortcut" "" "$(overlay_panels)"
expect_equal "the Shortcut shows the overlay" "ok" "$(area_start "press-shortcut capture-area")"
expect_equal "one overlay panel covers the fixture display, at the screen-saver level" "1" "$(overlay_panels | grep -c '^301x187 ')"
FACTS="$(send "$APP_SOCK" overlay-facts)"
expect_contains "the overlay's scene is layer-hosted: no view draws" "view=layer-hosted-scene" "$FACTS"
OVERLAY_PANEL_PIDS_OK=1
HELPER_NOW="$(helper_pid)"
if [[ -n "$HELPER_NOW" && -n "$("$INSPECT" overlay-windows "$HELPER_NOW")" ]]; then OVERLAY_PANEL_PIDS_OK=0; fi
expect_equal "the overlay is the menu bar app's, never the Editor helper's" "1" "$OVERLAY_PANEL_PIDS_OK"
expect_equal "a second Shortcut while the overlay is up does nothing" "ok" "$(area_start "press-shortcut capture-area")"
expect_equal "still one overlay panel" "1" "$(overlay_panels | grep -c '^301x187 ')"
# macOS posts the displays-changed notification for a Dock that moved too (a virtual machine posts it for
# nothing): with the displays as they were, the overlay stays.
send "$APP_SOCK" overlay-screens-noise >/dev/null
expect_equal "a displays-changed notification with the same displays does not end the overlay" "1" "$(overlay_panels | grep -c '^301x187 ')"
expect_equal "and the overlay still answers" "ok" "$(mouse move 0 10 10)"

# Hover: the window under the pointer is highlighted. The fixture's windows: front 60,40 100x60
# over back 20,20 200x130.
mouse move 0 10 10 >/dev/null
expect_equal "no window under the pointer: nothing highlighted" "none" "$(fact hover)"
mouse move 0 30 30 >/dev/null
expect_equal "the pointer over the back window highlights it" "20,20 200x130" "$(fact hover)"
mouse move 0 70 50 >/dev/null
expect_equal "the pointer over the front window highlights it, not the one behind" "60,40 100x60" "$(fact hover)"

# The scene as rendered: dimmed outside the selection, the frozen pixels inside it.
mouse move 0 10 10 >/dev/null
send "$APP_SOCK" "overlay-snapshot 0 $RUN_ROOT/overlay.png" >/dev/null
read -r R G B <<<"$("$INSPECT" pixel "$RUN_ROOT/overlay.png" 290 14)"
# The fixture pixel at 290,14 is 246,19,200 (not on a crosshair line); the dim is black at 40%.
if awk -v r="$R" -v g="$G" -v b="$B" 'BEGIN { exit !(r >= 143 && r <= 152 && g >= 8 && g <= 15 && b >= 116 && b <= 124) }'; then
  pass "the overlay dims the frozen frame ($R,$G,$B where the fixture is 246,19,200)"
else
  fail "the dim is wrong: got $R,$G,$B where the fixture is 246,19,200 (expected about 147,11,120)"
fi
mouse down 0 50 40 >/dev/null
mouse drag 0 120 90 >/dev/null
mouse drag 0 200 150 >/dev/null
expect_equal "dragging selects an Area, on the display it started on" "0 50,40 150x110" "$(fact area)"
send "$APP_SOCK" "overlay-snapshot 0 $RUN_ROOT/overlay.png" >/dev/null
read -r R G B <<<"$("$INSPECT" pixel "$RUN_ROOT/overlay.png" 190 50)"
# Fixture at 190,50: 161,68,200, shown undimmed inside the selection.
if awk -v r="$R" -v g="$G" -v b="$B" 'BEGIN { exit !(r >= 159 && r <= 163 && g >= 66 && g <= 70 && b >= 198 && b <= 202) }'; then
  pass "the selection shows the frozen pixels undimmed ($R,$G,$B where the fixture is 161,68,200)"
else
  fail "inside the selection got $R,$G,$B where the fixture is 161,68,200"
fi
read -r R G B <<<"$("$INSPECT" pixel "$RUN_ROOT/overlay.png" 290 14)"
if awk -v r="$R" 'BEGIN { exit !(r >= 143 && r <= 152) }'; then pass "outside the selection stays dimmed"; else fail "outside the selection got $R,$G,$B, not dimmed"; fi
rm -f "$RUN_ROOT/overlay.png"

# Letting go takes the Capture: the overlay goes and the Editor opens on exactly that Area.
mouse up 0 200 150 >/dev/null
if area_result; then pass "letting go captures: Capture $EDITOR_N opens in the Editor"; else fail "the Capture finished with '$AREA_REPLY'"; fi
expect_equal "the overlay is gone once the Capture is taken" "" "$(overlay_panels)"
expect_equal "no overlay is left to drive" "none" "$(send "$APP_SOCK" overlay-facts)"
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Area at 1x" 1 150 110 301 187 50 40 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi

# 3. The same at 2x (Display P3), with fractional point positions: both edges round to the nearest
#    device pixel. 20.3,30.4 to 120.8,90.6 points is pixels 41,61 to 242,181: 201 x 120.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
area_start "menu-click capture.area" >/dev/null
expect_equal "the menu item shows the overlay too" "1" "$(overlay_panels | grep -c '^301x187 ')"
area_drag 0 20.3 30.4 120.8 90.6
if area_result; then pass "2x: Capture $EDITOR_N opens in the Editor"; else fail "2x: the Capture finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Area at 2x" 2 201 120 602 374 41 61 "Display P3" "$P3_SHA_AREA" 5669
fi

# (The fixture's windows also include one crossing the first display's left edge and one crossing its
# top edge, for the displays at negative coordinates in 6b.)
# 4. A click on a highlighted window captures that window; below 3 pt a press is still a click.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
mouse drag 0 71 50 >/dev/null
mouse up 0 71 50 >/dev/null
if area_result; then pass "a click on a highlighted window captures it (a 1 pt jitter is still a click)"; else fail "the window click finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "front window at 1x" 1 100 60 301 187 60 40 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi

# A click on empty desktop does nothing; the overlay carries on until Esc.
FILES_BEFORE="$(capture_files)"
area_start "press-shortcut capture-area" >/dev/null
mouse move 0 10 170 >/dev/null
mouse down 0 10 170 >/dev/null
mouse up 0 10 170 >/dev/null
expect_equal "a click away from every window captures nothing" "1" "$(overlay_panels | grep -c '^301x187 ')"
expect_equal "no Capture file was made by the click" "$FILES_BEFORE" "$(capture_files)"
# A drag that stays inside 3 pt is a click as well.
mouse down 0 10 170 >/dev/null
mouse drag 0 12 171 >/dev/null
mouse up 0 12 171 >/dev/null
expect_equal "a drag under 3 pt selects nothing" "none" "$(fact area | sed 's/^[^ ]* //')"
expect_equal "the overlay is still up" "1" "$(overlay_panels | grep -c '^301x187 ')"

# 5. Esc cancels: the overlay closes, nothing is captured, and the Shortcut works at once.
send "$APP_SOCK" pasteboard-clear >/dev/null
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone after Esc" "" "$(overlay_panels)"
expect_equal "no Editor opened for a cancelled Capture" "" "$(open_editors 2>/dev/null)"
expect_equal "no Capture file was made by the cancelled Capture" "$FILES_BEFORE" "$(capture_files)"
expect_equal "a cancelled Capture puts nothing on the pasteboard" "" "$(send "$APP_SOCK" pasteboard-types)"
expect_equal "the Shortcut works again straight after Esc" "ok" "$(area_start "press-shortcut capture-area")"
expect_equal "and shows the overlay again" "1" "$(overlay_panels | grep -c '^301x187 ')"
mouse down 0 100 100 >/dev/null
mouse drag 0 150 130 >/dev/null
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels in the middle of a drag" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone after Esc in a drag" "" "$(overlay_panels)"
expect_equal "no Editor opened for the cancelled drag" "" "$(open_editors 2>/dev/null)"

# 6. A second display, with its own scale. An Area stays on the display where the drag started:
#    the pointer is clamped to it, and the other display's panel is ignored while dragging.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" "fixture-extra-display 2 200 150" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
expect_equal "one panel per display" "2" "$(overlay_panels | grep -c .)"
expect_equal "each panel has its display's size" "1" "$(overlay_panels | grep -c '^200x150 ')"
mouse down 1 20 20 >/dev/null
mouse drag 1 120 90 >/dev/null
mouse drag 0 100 100 >/dev/null   # a drag event on the other display's panel is ignored
expect_equal "an event on the other display does not move the selection" "1 20,20 100x70" "$(fact area)"
mouse drag 1 400 300 >/dev/null   # far outside the second display
expect_equal "the Area stops at the edge of the display it started on" "1 20,20 180x130" "$(fact area)"
mouse up 1 400 300 >/dev/null
if area_result; then pass "the Area on the second display is captured"; else fail "the second display's Capture finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  # Pixels at 2x: 40,40 to 400,300 of the second display's 400 x 300 fixture.
  area_png_check "Area on the second display (2x)" 2 360 260 400 300 40 40 "Display P3" "$P3_SHA_AREA" 5669
fi
send "$APP_SOCK" "fixture-extra-display none" >/dev/null

# 6b. Displays at negative coordinates: a second display to the left of, and one above, the first.
#     The fixture's window list is in the primary display's top-left space; a window that crosses
#     the primary's edge shows up on the second display only if the AppKit-to-window-list
#     conversion of its origin is right.
send "$APP_SOCK" "fixture-extra-display 1 200 150 left" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
expect_equal "a display to the left: two panels" "2" "$(overlay_panels | grep -c .)"
mouse move 1 150 50 >/dev/null
expect_equal "left display: the window that crosses the edge is highlighted on it, cut at the edge" "140,30 60x60" "$(fact hover)"
mouse move 0 5 50 >/dev/null
expect_equal "left display: and on the first display" "0,30 20x60" "$(fact hover)"
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
send "$APP_SOCK" "fixture-extra-display 1 200 150 above" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
mouse move 1 130 120 >/dev/null
expect_equal "a display above: the window that crosses the edge is highlighted on it, cut at the edge" "100,110 60x40" "$(fact hover)"
mouse move 0 130 20 >/dev/null
expect_equal "above: and on the first display" "100,0 60x40" "$(fact hover)"
mouse down 1 20 30 >/dev/null
mouse drag 1 90 100 >/dev/null
mouse up 1 90 100 >/dev/null
if area_result; then pass "an Area on the display above is captured"; else fail "the display above's Capture finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Area on the display above (1x)" 1 70 70 200 150 20 30 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi
send "$APP_SOCK" "fixture-extra-display none" >/dev/null

# 6c. A frozen frame that is not premultiplied BGRA (BGRX from a plain bitmap, the fourth byte 0):
#     the engine's in-place crop does not take it, so the Capture goes through the fallback, and
#     every pixel must still be the fixture's, opaque.
send "$APP_SOCK" "fixture-pixel-layout skip-first" >/dev/null
for scale in 1 2; do
  send "$APP_SOCK" "fixture-display $scale 301 187" >/dev/null
  area_start "press-shortcut capture-area" >/dev/null
  area_drag 0 20.3 30.4 120.8 90.6
  if area_result; then pass "skip-first frame at ${scale}x: Capture $EDITOR_N opens in the Editor"; else fail "skip-first frame at ${scale}x: the Capture finished with '$AREA_REPLY'"; fi
  if [[ -n "${EDITOR_N:-}" ]]; then
    if ((scale == 1)); then
      # 20.3,30.4 to 120.8,90.6 points at 1x is pixels 20,30 to 121,91: 101 x 61.
      area_png_check "skip-first frame at 1x" 1 101 61 301 187 20 30 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
    else
      area_png_check "skip-first frame at 2x" 2 201 120 602 374 41 61 "Display P3" "$P3_SHA_AREA" 5669
    fi
  fi
done
send "$APP_SOCK" "fixture-pixel-layout alpha-first" >/dev/null
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null

# 7. Memory returns to baseline over repeated Captures. A 5120 x 2880 pixel display (56 MB of
#    pixels): a frozen frame or Capture kept after the overlay closes would show.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100.5 100.5 600.5 500.5
area_result && copy_closes_editor   # warm up allocator pools
sleep 1
AREA_BASELINE="$(footprint_mb "$APP_PID")"
OVERLAY_PEAK=0
for _ in 1 2 3 4 5; do
  area_start "press-shortcut capture-area" >/dev/null
  mouse move 0 400 300 >/dev/null
  NOW="$(footprint_mb "$APP_PID")"
  OVERLAY_PEAK="$(awk -v a="$OVERLAY_PEAK" -v b="$NOW" 'BEGIN { print (b > a ? b : a) }')"
  area_drag 0 100.5 100.5 600.5 500.5
  area_result && copy_closes_editor
done
expect_memory_returns "memory returns to baseline after five Area Captures of a 5120 x 2880 display" "$APP_PID" "$AREA_BASELINE" "$(pixels_mb 5120 2880)"
expect_memory_returns "memory is back near the at-rest footprint" "$APP_PID" "$AREA_AT_REST" "$(pixels_mb 5120 2880)"
expect_peak_proportionate "the overlay: a frozen frame held on screen" "$OVERLAY_PEAK" "$AREA_BASELINE" "$(pixels_mb 5120 2880)"
if [[ -z "$(helper_pid)" ]]; then pass "no helper process is left after the Editors closed"; else fail "an Editor helper is still running"; fi

# 8. The overlay on a 1920 x 1080 display at 1x (an 8 MB frame) holds a peak proportionate to its frame on top of the
#    at-rest footprint.
send "$APP_SOCK" "fixture-display 1 1920 1080" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
mouse move 0 900 500 >/dev/null
OVERLAY_1080="$(footprint_mb "$APP_PID")"
expect_peak_proportionate "the overlay on a 1920 x 1080 display" "$OVERLAY_1080" "$AREA_AT_REST" "$(pixels_mb 1920 1080)"

# 9. Moving the pointer draws no view: 200 synthetic moves reach the layers (the scene updated) and leave
#    memory where it was.
UPDATES_BEFORE="$(fact scene-updates)"
for i in $(seq 1 200); do mouse move 0 $((100 + i * 7 % 1700)) $((100 + i * 13 % 800)) >/dev/null; done
UPDATES_AFTER="$(fact scene-updates)"
if awk -v a="$UPDATES_AFTER" -v b="$UPDATES_BEFORE" 'BEGIN { exit !(a - b >= 100) }'; then
  pass "the moves reached the overlay's layers (${UPDATES_BEFORE} to ${UPDATES_AFTER} scene updates)"
else
  fail "the moves did not update the scene (${UPDATES_BEFORE} to ${UPDATES_AFTER})"
fi
expect_contains "no view draws after the moves" "view=layer-hosted-scene" "$(send "$APP_SOCK" overlay-facts)"
expect_memory_returns "memory over 200 pointer moves" "$APP_PID" "$OVERLAY_1080" "$(pixels_mb 1920 1080)"
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null

area_start "press-shortcut capture-area" >/dev/null
expect_not_spinning "the menu bar app with the overlay up" "$APP_PID" 5
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null

# 10. The Editor helper warms up when the Area Shortcut is pressed (the Capture has started), while
#     the displays are frozen and the Area is chosen. Esc, a failed start and a display change end
#     the Capture without one and quit the helper; a Capture opens in the warm helper.
area_warm_state() { send "$APP_SOCK" "editor-warm-up state"; }
area_warm_is() { [[ "$(area_warm_state)" == "$1" ]]; }
area_helper_count() { pgrep -f "$HELPER_EXE" | wc -l | tr -d ' '; }
area_no_helper() { [[ "$(area_helper_count)" == "0" ]]; }

send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" "fixture-delay 0" >/dev/null
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 area_no_helper
expect_equal "no helper process at rest before the Area warm-up checks" "0" "$(area_helper_count)"

# The Shortcut warms the helper up: an agent, hidden, with no window.
area_start "press-shortcut capture-area" >/dev/null
if wait_until 10 area_warm_is warm; then pass "the Area Shortcut warms the Editor helper up"; else fail "no warm helper after the Area Shortcut (state '$(area_warm_state)')"; fi
AREA_WARM_PID="$(helper_pid)"
expect_equal "the warm helper is an agent: no Dock icon" "UIElement" "$(app_type "$AREA_WARM_PID")"
expect_equal "the warm helper has no window on screen" "0" "$(onscreen_windows "$AREA_WARM_PID")"
expect_equal "the warm helper has no panel at the overlay's level either" "" "$("$INSPECT" overlay-windows "$AREA_WARM_PID")"
expect_equal "the overlay is showing while the helper warms up" "1" "$(overlay_panels | grep -c '^301x187 ')"

# Esc cancels the Capture and the helper that never showed anything goes.
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels with a warm helper" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
if wait_until 10 gone "$AREA_WARM_PID"; then pass "Esc quits the helper that was warming up"; else fail "the warm helper is still running after Esc"; fi
expect_equal "no helper process at rest after Esc" "0" "$(area_helper_count)"
expect_equal "Esc leaves the warm-up idle" "idle" "$(area_warm_state)"

# A display change ends the overlay the same way.
area_start "press-shortcut capture-area" >/dev/null
wait_until 10 area_warm_is warm
expect_equal "a display change is delivered to the overlay" "ok" "$(send "$APP_SOCK" overlay-screens-changed)"
expect_equal "a display change cancels the Capture" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone after a display change" "" "$(overlay_panels)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
if wait_until 10 area_no_helper; then pass "a display change quits the helper that was warming up"; else fail "the helper is still running after a display change"; fi

# A start that fails (the displays could not be frozen) is a Capture that ends without one.
send "$APP_SOCK" "fixture-fail on" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
send "$APP_SOCK" "fixture-fail off" >/dev/null
expect_equal "a failed start shows no overlay" "" "$(overlay_panels)"
expect_equal "a failed start is reported" "failed" "$(send_slow "$APP_SOCK" overlay-wait | cut -d' ' -f1)"
if wait_until 10 area_no_helper; then pass "a failed start quits the helper that was warming up"; else fail "the helper is still running after a failed start"; fi
expect_equal "a failed start leaves the warm-up idle" "idle" "$(area_warm_state)"
expect_equal "the Shortcut works again after a failed start" "ok" "$(area_start "press-shortcut capture-area")"
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 area_no_helper

# A Capture opens in the warm helper: the Editor was built before the Area was chosen.
area_start "press-shortcut capture-area" >/dev/null
wait_until 10 area_warm_is warm
area_drag 0 50 40 200 150
if area_result; then
  expect_contains "the Editor was built before its Capture" "warm=yes" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  expect_equal "the warm Editor is on screen once it opened" "1" "$(onscreen_windows "$HELPER_PID")"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
else
  fail "the Area Capture with a warm helper finished with '$AREA_REPLY'"
fi

# The same on a 5K display with an Area that covers nearly all of it, three times over.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
for round in 1 2 3; do
  area_start "press-shortcut capture-area" >/dev/null
  if ! wait_until 10 area_warm_is warm; then fail "Area warm round $round: the helper did not warm up"; fi
  area_drag 0 1 1 2559 1439
  if area_result; then
    expect_contains "Area warm round $round: the Editor was built before its Capture" "warm=yes" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
    send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
    wait_until 10 gone "$HELPER_PID"
  else
    fail "Area warm round $round finished with '$AREA_REPLY'"
  fi
done
expect_equal "no helper process is left after the Area warm-up checks" "0" "$(area_helper_count)"
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
