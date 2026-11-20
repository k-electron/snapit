# Flow: the Color picker. It opens from the Action bar's Pick Color button and its P key, from the
# menu's Pick Color and from its Shortcut (unassigned by default). A loupe outlines the one device
# pixel being sampled, with a swatch and `#RRGGBB`; the arrow keys nudge that pixel by one device
# pixel (Shift: ten); a click or Enter copies the uppercase hex to the private pasteboard and shows a
# "Copied #…" toast; Esc returns to the Action bar, or cancels when the picker was opened from the
# menu or the Shortcut. The hex is the pixel as the frozen frame stores it, in the display's own color
# space (a Display P3 display gives Display P3 values), so it is checked against the fixture formula
# at 1x (sRGB) and 2x (Display P3), at the display's edges, on a second display at negative
# coordinates, and under either "After selecting an Area" setting. No Editor is warmed up for a pick
# from the menu or the Shortcut. Uses the helpers of 40-area-capture.sh and 42-action-bar.sh
# (area_start, mouse, fact, overlay_panels, area_drag, area_cancel, press_tile, tile_point,
# tooltip_is, precise_mb, area_no_helper). Sourced by scripts/check-run.sh. It runs before 45- on
# purpose: after the Save flow's Editors the test store no longer takes a value the menu bar app
# changes, and this flow changes "After selecting an Area".
# shellcheck shell=bash

# fixture_hex <scale> <points w> <points h> <pixel x> <pixel y>: the fixture's pixel as `#RRGGBB`.
fixture_hex() {
  awk -v s="$1" -v pw="$2" -v ph="$3" -v x="$4" -v y="$5" 'BEGIN {
    w = s * pw; h = s * ph
    r = int(x * 255 / (w - 1)); g = int(y * 255 / (h - 1))
    b = 200
    if ((int(x / 8) + int(y / 8)) % 2 == 0) b = 40
    printf "#%02X%02X%02X", r, g, b
  }'
}
pfact() { send "$APP_SOCK" overlay-picker | sed -n "s/^$1=//p"; }
toast_gone() { [[ "$(send "$APP_SOCK" color-toast)" == none ]]; }
# expect_pick <label> <scale> <points w> <points h> <pixel x> <pixel y>: the picker samples that
# device pixel and shows the fixture's color for it.
expect_pick() {
  expect_equal "$1: the sampled pixel" "$5,$6" "$(pfact pixel)"
  expect_equal "$1: its hex is the fixture's" "$(fixture_hex "$2" "$3" "$4" "$5" "$6")" "$(pfact hex)"
}
# rgb_of <#RRGGBB>: `r g b`.
rgb_of() { local h="${1#\#}"; printf '%d %d %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }
# snapshot_pixel <display> <fact name>: `r g b` of the snapshot at the point the picker fact names
# (display points; the snapshot has one pixel per device pixel, so it is scaled).
snapshot_pixel() {
  local scale="$3" x y
  send "$APP_SOCK" "overlay-snapshot $1 $RUN_ROOT/picker.png" >/dev/null
  read -r x y <<<"$(pfact "$2" | awk -F, -v s="$scale" '{ printf "%d %d", $1 * s, $2 * s }')"
  "$INSPECT" pixel "$RUN_ROOT/picker.png" "$x" "$y"
}
# near <r g b> <r g b> <tolerance>
near() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { split(a, p, " "); split(b, q, " "); for (i = 1; i <= 3; i++) { d = p[i] - q[i]; if (d < 0) d = -d; if (d > t) exit 1 } exit 0 }'; }
picker_click() { # <display> <x> <y>
  mouse move "$1" "$2" "$3" >/dev/null
  mouse down "$1" "$2" "$3" >/dev/null
  mouse up "$1" "$2" "$3" >/dev/null
}
# picked <label> <expected hex>: the overlay ended with that pick, the pasteboard holds it, the toast says so.
picked() {
  local reply
  reply="$(send_slow "$APP_SOCK" overlay-wait)"
  expect_equal "$1: the overlay ends with the pick" "picked $2" "$reply"
  expect_equal "$1: the pasteboard holds the uppercase hex" "$2" "$(send "$APP_SOCK" pasteboard-string)"
  expect_equal "$1: the toast says it was copied" "Copied $2" "$(send "$APP_SOCK" color-toast)"
}

# set_after_selecting <value>: stores the setting while no Editor helper runs (in the test store's
# file a running helper neither sees a key another process wrote nor lets it stand; see
# 45-save-and-drag-out.sh) and reads it back, so a dropped command shows here.
set_after_selecting() {
  local try
  send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
  wait_until 10 area_no_helper
  for try in 1 2 3; do
    send "$APP_SOCK" "defaults-set afterSelectingArea $1" >/dev/null
    [[ "$(send "$APP_SOCK" "defaults-get afterSelectingArea")" == "$1" ]] && return 0
  done
  fail "the setting 'After selecting an Area' would not take $1 (reads '$(send "$APP_SOCK" "defaults-get afterSelectingArea")', helper '$(helper_pid)')"
}

send "$APP_SOCK" "fixture-extra-display none" >/dev/null
send "$APP_SOCK" "fixture-pixel-layout alpha-first" >/dev/null
send "$APP_SOCK" "fixture-delay 0" >/dev/null
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
set_after_selecting showActionBar
PICK_BEFORE="$(precise_mb "$APP_PID")"

# 1. The menu item and the Shortcut: Pick Color after Capture Screen, unassigned until the user records one.
expect_in_order "the menu offers Pick Color after Capture Screen" "$(send "$APP_SOCK" menu-titles)" "Capture Screen" "Pick Color"
expect_in_order "the Pick Color Shortcut is bound" "$(send "$APP_SOCK" bound-shortcuts)" "pick-color"
expect_equal "the Pick Color Shortcut is unassigned by default" "none" "$(send "$APP_SOCK" "shortcut-combo pick-color")"
expect_equal "so the menu item shows no Shortcut" "none" "$(send "$APP_SOCK" "menu-shortcut capture.pick-color")"
send "$APP_SOCK" "shortcut-set pick-color 20 control option command" >/dev/null
expect_equal "the menu item follows a recorded Shortcut" "3 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.pick-color")"
send "$APP_SOCK" "shortcut-set pick-color none" >/dev/null
expect_equal "and shows none again when it is unassigned" "none" "$(send "$APP_SOCK" "menu-shortcut capture.pick-color")"

# 2. From the Action bar: the button, with its tooltip, opens the picker over the selection.
area_start "press-shortcut capture-area" >/dev/null
send "$APP_SOCK" "overlay-key p" >/dev/null
expect_equal "P does nothing before there is a selection and an Action bar" "idle" "$(fact state)"
area_drag 0 100 60 300 160
ITEMS="$(send "$APP_SOCK" overlay-actionbar)"
expect_contains "the Action bar offers Pick Color, with P as its key and a tooltip" "item pick-color|Pick Color|Pick a color from the screen (P)|p|" "$ITEMS"
read -r TX TY <<<"$(tile_point pick-color 10 10)"
mouse move 0 "$TX" "$TY" >/dev/null
expect_equal "the pointer is over the Pick Color tile" "pick-color" "$(fact hovered)"
if wait_until 5 tooltip_is "Pick a color from the screen (P)"; then pass "resting on Pick Color shows its tooltip"; else fail "no tooltip for Pick Color ('$(fact tooltip)')"; fi
read -r DX DY <<<"$(tile_point pick-color 3 3)"
press_tile pick-color 3 3   # near the tile's top-left corner, away from its glyph and title
expect_equal "clicking Pick Color opens the picker" "pickingColor" "$(fact state)"
expect_equal "the Action bar is hidden while picking" "none" "$(fact action-bar)"
expect_equal "no handle shows while picking" "0" "$(fact handles)"
expect_equal "the overlay's own crosshair loupe is hidden" "hidden" "$(fact loupe)"
expect_equal "the selection is kept for Esc to return to" "0 100,60 200x100" "$(fact selection)"
expect_equal "the picker knows it came from the Action bar" "bar" "$(pfact origin)"
if [[ "$(pfact loupe)" != none ]]; then pass "the picker's loupe is showing ($(pfact loupe))"; else fail "the picker's loupe is not showing"; fi
expect_contains "the overlay is still layer-hosted with the picker up" "view=layer-hosted-scene" "$(send "$APP_SOCK" overlay-facts)"
expect_equal "no tooltip shows while picking" "none" "$(fact tooltip)"
# The second click of a double-click on the button is the button's: it picks nothing.
mouse down 0 "$DX" "$DY" 2 >/dev/null
mouse up 0 "$DX" "$DY" >/dev/null
expect_equal "the second click of a double-click on Pick Color does not pick" "pickingColor" "$(fact state)"
expect_equal "and nothing reached the pasteboard" "none" "$(send "$APP_SOCK" pasteboard-string)"

# Aiming: the pixel under the pointer is the sampled one, outlined in the loupe's middle cell.
mouse move 0 120.5 90.5 >/dev/null
expect_pick "1x aim" 1 600 400 120 90
expect_equal "the sampled pixel is on the first display" "0" "$(pfact display)"
read -r R G B <<<"$(rgb_of "$(pfact hex)")"
if near "$(snapshot_pixel 0 outlined 1)" "$R $G $B" 1; then pass "the outlined cell shows the sampled pixel's color ($R,$G,$B)"; else fail "the outlined cell shows '$(snapshot_pixel 0 outlined 1)', not $R,$G,$B"; fi
if near "$(snapshot_pixel 0 swatch 1)" "$R $G $B" 1; then pass "the swatch shows the sampled pixel's color"; else fail "the swatch shows '$(snapshot_pixel 0 swatch 1)', not $R,$G,$B"; fi
# The cell to the right of the outlined one is the next pixel, not the same one.
send "$APP_SOCK" "overlay-key right" >/dev/null
expect_pick "nudge right" 1 600 400 121 90
send "$APP_SOCK" "overlay-key down" >/dev/null
expect_pick "nudge down" 1 600 400 121 91
send "$APP_SOCK" "overlay-key left" >/dev/null
send "$APP_SOCK" "overlay-key left" >/dev/null
expect_pick "two nudges left" 1 600 400 119 91
send "$APP_SOCK" "overlay-key up" >/dev/null
expect_pick "nudge up" 1 600 400 119 90
send "$APP_SOCK" "overlay-key 124 shift" >/dev/null
expect_pick "Shift nudges ten pixels" 1 600 400 129 90
expect_equal "a nudge does not move the pointer" "120.5,90.5" "$(fact cursor)"
read -r R G B <<<"$(rgb_of "$(pfact hex)")"
if near "$(snapshot_pixel 0 outlined 1)" "$R $G $B" 1; then pass "after nudges the outlined cell still shows the sampled pixel ($R,$G,$B)"; else fail "after nudges the outlined cell shows '$(snapshot_pixel 0 outlined 1)', not $R,$G,$B"; fi
# The pointer takes the sampled pixel back.
mouse move 0 300.9 200.9 >/dev/null
expect_pick "the pointer aims again" 1 600 400 300 200
# The frame's corners: nudges stop at the edge; the loupe shows only the pixels that exist.
mouse move 0 0 0 >/dev/null
send "$APP_SOCK" "overlay-key left" >/dev/null
send "$APP_SOCK" "overlay-key up" >/dev/null
send "$APP_SOCK" "overlay-key 123 shift" >/dev/null
expect_pick "top-left corner" 1 600 400 0 0
read -r R G B <<<"$(rgb_of "$(pfact hex)")"
if near "$(snapshot_pixel 0 outlined 1)" "$R $G $B" 1; then pass "at the corner the outlined cell is the corner pixel ($R,$G,$B)"; else fail "at the corner the outlined cell shows '$(snapshot_pixel 0 outlined 1)', not $R,$G,$B"; fi
mouse move 0 599.9 399.9 >/dev/null
send "$APP_SOCK" "overlay-key right" >/dev/null
send "$APP_SOCK" "overlay-key down" >/dev/null
send "$APP_SOCK" "overlay-key 125 shift" >/dev/null
expect_pick "bottom-right corner" 1 600 400 599 399
read -r R G B <<<"$(rgb_of "$(pfact hex)")"
if near "$(snapshot_pixel 0 outlined 1)" "$R $G $B" 1; then pass "at the far corner the outlined cell is the corner pixel ($R,$G,$B)"; else fail "at the far corner the outlined cell shows '$(snapshot_pixel 0 outlined 1)', not $R,$G,$B"; fi
rm -f "$RUN_ROOT/picker.png"
assert_idle_cpu "menu bar app with the Color picker showing" "$APP_PID" 3

# Esc goes back to the Action bar, with the selection where it was; nothing was copied.
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc returns to the Action bar" "adjusting" "$(fact state)"
expect_equal "the selection is where it was" "0 100,60 200x100" "$(fact selection)"
if [[ "$(fact action-bar)" != none ]]; then pass "the Action bar shows again"; else fail "no Action bar after Esc from the picker"; fi
expect_equal "and its eight handles" "8" "$(fact handles)"
expect_equal "the picker is gone" "none" "$(send "$APP_SOCK" overlay-picker)"
expect_equal "Esc copied nothing" "none" "$(send "$APP_SOCK" pasteboard-string)"
expect_equal "and showed no toast" "none" "$(send "$APP_SOCK" color-toast)"

# P opens it again; Enter copies. The Editor that warmed up for the Area Capture goes.
mouse move 0 250.5 140.5 >/dev/null
send "$APP_SOCK" "overlay-key p" >/dev/null
expect_equal "P opens the picker from the Action bar" "pickingColor" "$(fact state)"
send "$APP_SOCK" "overlay-key p" >/dev/null
expect_equal "P again does nothing" "pickingColor" "$(fact state)"
expect_pick "P opens on the pixel under the pointer" 1 600 400 250 140
send "$APP_SOCK" "overlay-key enter" >/dev/null
picked "Enter" "$(fixture_hex 1 600 400 250 140)"
expect_equal "only the toast is on screen: the overlay is gone" "0" "$(overlay_panels | grep -c '^600x400 ')"
expect_equal "and the toast is one window" "1" "$(overlay_panels | grep -c .)"
assert_idle_cpu "menu bar app with the toast showing" "$APP_PID" 1
if wait_until 5 toast_gone; then pass "the toast goes away by itself"; else fail "the toast is still showing"; fi
expect_equal "and its window is gone" "" "$(overlay_panels)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
if wait_until 10 area_no_helper; then pass "no Editor helper is left after a pick from the Action bar"; else fail "an Editor helper is still running after the pick"; fi

# A click picks too, wherever the button goes up; Esc then does nothing more than the Action bar.
send "$APP_SOCK" pasteboard-clear >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
press_tile pick-color -3 -3
picker_click 0 200.5 100.5
picked "A click" "$(fixture_hex 1 600 400 200 100)"
wait_until 5 toast_gone
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null

# 3. From the menu: the overlay opens in the picker with no selection and no Action bar. No
#    Editor is warmed up (no Capture opens), Esc cancels, and a drag-and-release picks where it ends.
send "$APP_SOCK" pasteboard-clear >/dev/null
expect_equal "the menu's Pick Color opens the overlay" "ok" "$(area_start "menu-click capture.pick-color")"
expect_equal "it opens in the Color picker" "pickingColor" "$(fact state)"
expect_equal "the picker knows it came from the menu" "entry" "$(pfact origin)"
expect_equal "one panel covers the display" "1" "$(overlay_panels | grep -c '^600x400 ')"
expect_equal "there is no selection" "none none" "$(fact selection)"
expect_equal "and no Action bar" "none" "$(fact action-bar)"
expect_equal "the Editor is not warmed up for a pick" "idle" "$(send "$APP_SOCK" "editor-warm-up state")"
expect_equal "and no Editor helper process exists" "" "$(helper_pid)"
expect_equal "the picker starts on the pixel under the pointer, the middle of the display" "300,200" "$(pfact pixel)"
expect_equal "a second Pick Color while it is up does nothing" "ok" "$(area_start "menu-click capture.pick-color")"
expect_equal "(still one panel)" "1" "$(overlay_panels | grep -c '^600x400 ')"
send "$APP_SOCK" "overlay-key p" >/dev/null
expect_equal "P does nothing in the picker" "pickingColor" "$(fact state)"
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels a picker opened from the menu" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone" "" "$(overlay_panels)"
expect_equal "nothing was copied" "none" "$(send "$APP_SOCK" pasteboard-string)"
expect_equal "and there is no toast" "none" "$(send "$APP_SOCK" color-toast)"

area_start "menu-click capture.pick-color" >/dev/null
mouse move 0 10.5 10.5 >/dev/null
mouse down 0 10.5 10.5 >/dev/null
mouse drag 0 100.5 50.5 >/dev/null
mouse drag 0 400.5 300.5 >/dev/null
expect_pick "dragging in the picker follows the pointer" 1 600 400 400 300
mouse up 0 400.5 300.5 >/dev/null
picked "Drag and release" "$(fixture_hex 1 600 400 400 300)"
expect_equal "no Editor helper was started by a pick from the menu" "" "$(helper_pid)"
expect_equal "the Editor is still not warmed up" "idle" "$(send "$APP_SOCK" "editor-warm-up state")"
wait_until 5 toast_gone

# A second pick while the first toast is still up replaces it: one toast window.
area_start "press-shortcut pick-color" >/dev/null
expect_equal "the Shortcut opens the picker" "pickingColor" "$(fact state)"
send "$APP_SOCK" "overlay-key enter" >/dev/null
picked "The Shortcut and Enter" "$(fixture_hex 1 600 400 300 200)"
area_start "press-shortcut pick-color" >/dev/null
picker_click 0 50.5 50.5
picked "A second pick" "$(fixture_hex 1 600 400 50 50)"
expect_equal "a new toast replaces the old one" "1" "$(overlay_panels | wc -l | tr -d ' ')"
wait_until 5 toast_gone
expect_equal "the toast window is gone" "" "$(overlay_panels)"

# 4. Either "After selecting an Area" setting: with Capture on release, a drag in the picker picks, never captures.
set_after_selecting captureOnRelease
area_start "menu-click capture.pick-color" >/dev/null
expect_contains "the setting reads Capture on release" "after-selecting=captureOnRelease" "$(send "$APP_SOCK" overlay-facts)"
mouse move 0 40.5 40.5 >/dev/null
mouse down 0 40.5 40.5 >/dev/null
mouse drag 0 200.5 120.5 >/dev/null
mouse up 0 200.5 120.5 >/dev/null
picked "Capture on release" "$(fixture_hex 1 600 400 200 120)"
expect_equal "no Capture was taken" "" "$(helper_pid)"
wait_until 5 toast_gone
area_start "press-shortcut capture-area" >/dev/null
send "$APP_SOCK" "overlay-key p" >/dev/null
expect_equal "with Capture on release there is no Action bar, so P does nothing" "idle" "$(fact state)"
area_cancel
set_after_selecting showActionBar
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null

# 5. 2x, Display P3: the hex is the stored value (the fixture formula), with the loupe on the right device pixel.
send "$APP_SOCK" "fixture-display 2 600 400" >/dev/null
area_start "menu-click capture.pick-color" >/dev/null
expect_equal "at 2x the picker starts on the device pixel under the pointer" "600,400" "$(pfact pixel)"
mouse move 0 7.75 20.25 >/dev/null
expect_pick "2x aim at 7.75,20.25 points" 2 600 400 15 40
expect_equal "the frame is 1200 x 800 device pixels" "1200x800" "$(pfact frame)"
send "$APP_SOCK" "overlay-snapshot 0 $RUN_ROOT/picker.png" >/dev/null
CELL="$(snapshot_pixel 0 outlined 2)"
RIGHT="$(send "$APP_SOCK" overlay-picker | sed -n 's/^outlined=//p' | awk -F, '{ printf "%d %d", ($1 + 16) * 2, $2 * 2 }')"
read -r _ _ B1 <<<"$CELL"
read -r _ _ B2 <<<"$("$INSPECT" pixel "$RUN_ROOT/picker.png" $RIGHT)"
if ((B1 < 120 && B2 > 130)); then pass "pixel 15 is a 40-blue cell and the next device pixel to its right a 200-blue one (blue $B1, then $B2)"; else fail "the loupe's cells at the checkerboard edge: blue $B1 then $B2"; fi
if near "$(snapshot_pixel 0 swatch 2)" "$CELL" 3; then pass "the swatch matches the outlined cell at 2x"; else fail "the swatch '$(snapshot_pixel 0 swatch 2)' differs from the outlined cell '$CELL'"; fi
# One row up from the checkerboard edge: the cells to the right and below the outlined one are the
# 40-blue ones, so a loupe that is off by one in any direction shows.
mouse move 0 7.75 19.75 >/dev/null
expect_pick "2x aim at 7.75,19.75 points" 2 600 400 15 39
CELL="$(snapshot_pixel 0 outlined 2)"
BELOW="$(pfact outlined | awk -F, '{ printf "%d %d", $1 * 2, ($2 + 16) * 2 }')"
RIGHT="$(pfact outlined | awk -F, '{ printf "%d %d", ($1 + 16) * 2, $2 * 2 }')"
read -r _ _ B0 <<<"$CELL"
read -r _ _ B1 <<<"$("$INSPECT" pixel "$RUN_ROOT/picker.png" $RIGHT)"
read -r _ _ B2 <<<"$("$INSPECT" pixel "$RUN_ROOT/picker.png" $BELOW)"
if ((B0 > 130 && B1 < 120 && B2 < 120)); then pass "pixel (15,39) is 200-blue with 40-blue cells to its right and below (blue $B0, $B1, $B2)"; else fail "the loupe's cells around (15,39): blue $B0, right $B1, below $B2"; fi
mouse move 0 7.75 20.25 >/dev/null
send "$APP_SOCK" "overlay-key right" >/dev/null
expect_pick "2x nudge right is one device pixel" 2 600 400 16 40
read -r _ _ B1 <<<"$(snapshot_pixel 0 outlined 2)"
if ((B1 > 130)); then pass "after the nudge the outlined cell is the 200-blue pixel (blue $B1)"; else fail "after the nudge the outlined cell has blue $B1"; fi
expect_equal "a nudge of one device pixel is half a point: the pointer has not moved" "7.75,20.25" "$(fact cursor)"
send "$APP_SOCK" "overlay-key down" >/dev/null
send "$APP_SOCK" "overlay-key down" >/dev/null
expect_pick "2x two nudges down" 2 600 400 16 42
mouse move 0 599.75 399.75 >/dev/null
expect_pick "2x far corner" 2 600 400 1199 799
send "$APP_SOCK" "overlay-key right" >/dev/null
expect_pick "a nudge at the far corner stays" 2 600 400 1199 799
mouse move 0 123.5 77.25 >/dev/null
rm -f "$RUN_ROOT/picker.png"
send "$APP_SOCK" "overlay-key enter" >/dev/null
picked "2x Enter" "$(fixture_hex 2 600 400 247 154)"
wait_until 5 toast_gone

# The frozen frame's own pixel layout does not change the hex (BGRX, no alpha byte).
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
send "$APP_SOCK" "fixture-pixel-layout skip-first" >/dev/null
area_start "menu-click capture.pick-color" >/dev/null
picker_click 0 77.5 33.5
picked "BGRX frame" "$(fixture_hex 1 600 400 77 33)"
send "$APP_SOCK" "fixture-pixel-layout alpha-first" >/dev/null
wait_until 5 toast_gone

# 6. A second display of another scale, to the left (negative coordinates) and above: each display
#    samples its own frame, in its own device pixels.
for PLACE in left above; do
  send "$APP_SOCK" "fixture-extra-display 2 400 300 $PLACE" >/dev/null
  area_start "menu-click capture.pick-color" >/dev/null
  expect_equal "$PLACE: the picker starts on the first display" "0" "$(pfact display)"
  expect_equal "$PLACE: one panel per display" "1" "$(overlay_panels | grep -c '^400x300 ')"
  mouse move 1 399.75 10.5 >/dev/null
  expect_equal "$PLACE: the picker moved to the second display" "1" "$(pfact display)"
  expect_pick "$PLACE: second display, last column" 2 400 300 799 21
  send "$APP_SOCK" "overlay-key left" >/dev/null
  expect_pick "$PLACE: a nudge on the second display" 2 400 300 798 21
  expect_equal "$PLACE: the loupe is on the second display" "1" "$(send "$APP_SOCK" overlay-picker | grep -c '^loupe=[0-9]')"
  mouse move 1 0.25 0.25 >/dev/null
  expect_pick "$PLACE: second display, first pixel" 2 400 300 0 0
  mouse move 0 100.5 50.5 >/dev/null
  expect_equal "$PLACE: back on the first display" "0" "$(pfact display)"
  expect_pick "$PLACE: first display (1x) after the second" 1 600 400 100 50
  mouse move 1 200.25 150.75 >/dev/null
  mouse down 1 200.25 150.75 >/dev/null
  mouse up 1 200.25 150.75 >/dev/null
  picked "$PLACE: a click on the second display" "$(fixture_hex 2 400 300 400 301)"
  wait_until 5 toast_gone
done
send "$APP_SOCK" "fixture-extra-display none" >/dev/null

# 7. Memory and CPU. A 2560 x 1600 pixel display (16 MB of pixels): ten picks leave memory where it
#    was, the picker holds the frozen frame once, and nothing runs while it shows.
send "$APP_SOCK" "fixture-display 2 1280 800" >/dev/null
area_start "menu-click capture.pick-color" >/dev/null
picker_click 0 400.5 300.5
send_slow "$APP_SOCK" overlay-wait >/dev/null
wait_until 5 toast_gone
sleep 1
PICK_BASELINE="$(precise_mb "$APP_PID")"
PICK_PEAK=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  area_start "menu-click capture.pick-color" >/dev/null
  mouse move 0 $((100 + i * 10)).5 200.5 >/dev/null
  send "$APP_SOCK" "overlay-key right" >/dev/null
  send "$APP_SOCK" "overlay-key down" >/dev/null
  NOW="$(precise_mb "$APP_PID")"
  PICK_PEAK="$(awk -v a="$PICK_PEAK" -v b="$NOW" 'BEGIN { print (b > a ? b : a) }')"
  send "$APP_SOCK" "overlay-key enter" >/dev/null
  send_slow "$APP_SOCK" overlay-wait >/dev/null
  wait_until 5 toast_gone
done
sleep 1
PICK_AFTER="$(precise_mb "$APP_PID")"
if awk -v a="$PICK_AFTER" -v b="$PICK_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory returns to baseline after ten picks (${PICK_BASELINE} MB before, ${PICK_AFTER} MB after)"
else
  fail "memory grew from ${PICK_BASELINE} MB to ${PICK_AFTER} MB over ten picks (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
echo "     Color picker peak ${PICK_PEAK} MB with a 16 MB frozen frame on screen (${PICK_BASELINE} MB at rest)"
if awk -v peak="$PICK_PEAK" -v base="$PICK_BASELINE" 'BEGIN { exit !(peak - base <= 16 + 10) }'; then
  pass "the picker holds the frozen frame once: peak ${PICK_PEAK} MB over a ${PICK_BASELINE} MB base"
else
  fail "the picker peaks at ${PICK_PEAK} MB over a ${PICK_BASELINE} MB base: more than one copy of a 16 MB frame"
fi
if awk -v a="$PICK_AFTER" -v b="$PICK_BEFORE" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory is where it was before the first pick (${PICK_BEFORE} MB then, ${PICK_AFTER} MB now)"
else
  fail "memory is ${PICK_AFTER} MB after the picks, ${PICK_BEFORE} MB before the first (limit +${FOOTPRINT_FROM_REST_MB_MAX} MB)"
fi
area_start "menu-click capture.pick-color" >/dev/null
assert_idle_cpu "menu bar app with the Color picker over a large display" "$APP_PID" 4
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
assert_idle_cpu "menu bar app after the Color picker" "$APP_PID" 4
expect_equal "no Editor helper process exists after the picks" "" "$(helper_pid)"

# Leave what the next flows expect, and hold the process to its baseline here, not in a later flow.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
sleep 1
PICK_END="$(precise_mb "$APP_PID")"
if awk -v a="$PICK_END" -v b="$PICK_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory is where the ten picks left it after the Color picker flow (${PICK_BASELINE} MB, ${PICK_END} MB now)"
else
  fail "memory is ${PICK_END} MB after the Color picker flow, ${PICK_BASELINE} MB before the ten picks (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
