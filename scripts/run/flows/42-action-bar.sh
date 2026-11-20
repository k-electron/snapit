# Flow: Area Capture with "After selecting an Area" at Show Action bar, the default. Letting go of the
# mouse keeps the selection on screen with eight handles and the Action bar; the handles resize it
# (past the opposite edge too), a drag inside moves it, Enter, a double-click inside it and the bar's
# Capture button capture it, Esc and Cancel end the Capture. Checks the bar stays on screen at every
# edge and corner, tooltips, a 3 pt jitter, pixel-exact Captures at 1x and 2x, the setting at Capture
# on release, memory and idle CPU. Uses the helpers of 40-area-capture.sh (area_start, mouse, fact,
# overlay_panels, area_drag, area_result, area_png_check). Sourced by scripts/check-run.sh.
# shellcheck shell=bash

bar_frame() { send "$APP_SOCK" overlay-actionbar | sed -n 's/^frame=//p'; }
# in_display <"x,y WxH"> <display w> <display h>: succeeds when the frame lies inside the display.
in_display() { awk -v f="$1" -v w="$2" -v h="$3" 'BEGIN { split(f, a, /[ ,x]/); exit !(a[1] >= 0 && a[2] >= 0 && a[1] + a[3] <= w + 0.001 && a[2] + a[4] <= h + 0.001) }'; }
# bar_side <bar frame> <selection frame>: below, above or inside.
bar_side() {
  awk -v b="$1" -v s="$2" 'BEGIN {
    split(b, p, /[ ,x]/); split(s, q, /[ ,x]/)
    if (p[2] >= q[2] + q[4] - 0.001) print "below"
    else if (p[2] + p[4] <= q[2] + 0.001) print "above"
    else print "inside"
  }'
}
selection_frame() { fact selection | sed 's/^[^ ]* //'; }
# tile_point <item id> <dx> <dy>: a point of the display <dx>,<dy> points in from the tile's top-left
# corner (a negative number counts from the opposite edge).
tile_point() {
  send "$APP_SOCK" overlay-actionbar | awk -F'|' -v id="$1" -v dx="$2" -v dy="$3" '
    $1 == "item " id {
      split($5, f, /[ ,x]/)
      printf "%s %s", (dx < 0 ? f[1] + f[3] + dx : f[1] + dx), (dy < 0 ? f[2] + f[4] + dy : f[2] + dy)
    }'
}
# press_tile <item id> <dx> <dy>: a real click (the pointer moves there, the button goes down and up).
press_tile() {
  local x y
  read -r x y <<<"$(tile_point "$@")"
  mouse move 0 "$x" "$y" >/dev/null
  mouse down 0 "$x" "$y" >/dev/null
  mouse up 0 "$x" "$y" >/dev/null
}
precise_mb() { footprint -f bytes -p "$1" 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "Footprint:") { printf "%.2f", $(i+1) / 1048576; exit } }'; }
BAR_FIRST_USE_MB_MAX="${SNAPIT_BAR_FIRST_USE_MB_MAX:-1}"
# The footprint before the first Action bar of this run (flow 40 shows overlays, never a bar).
BAR_FIRST_BEFORE="$(precise_mb "$APP_PID")"
area_cancel() {
  send "$APP_SOCK" "overlay-key escape" >/dev/null
  send_slow "$APP_SOCK" overlay-wait >/dev/null
}

send "$APP_SOCK" "fixture-extra-display none" >/dev/null
send "$APP_SOCK" "fixture-delay 0" >/dev/null
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
# A stored value that is not one of the two counts as the default.
send "$APP_SOCK" "defaults-set afterSelectingArea nonsense" >/dev/null

# 1. Letting go keeps the selection: eight handles, the Action bar, nothing captured.
FILES_BEFORE="$(capture_files)"
area_start "press-shortcut capture-area" >/dev/null
expect_contains "the default is Show Action bar" "after-selecting=showActionBar" "$(send "$APP_SOCK" overlay-facts)"
expect_equal "before a selection there are no handles" "0" "$(fact handles)"
expect_equal "before a selection there is no Action bar" "none" "$(fact action-bar)"
area_drag 0 100 60 300 160
expect_equal "letting go keeps the overlay up" "1" "$(overlay_panels | grep -c '^600x400 ')"
expect_equal "the overlay is adjusting the selection" "adjusting" "$(fact state)"
expect_equal "the selection stays where it was dragged" "0 100,60 200x100" "$(fact selection)"
expect_equal "the selection has eight handles" "8" "$(fact handles)"
expect_equal "nothing was captured" "$FILES_BEFORE" "$(capture_files)"
expect_equal "and the Capture has not finished" "" "$(open_editors 2>/dev/null)"
BAR="$(bar_frame)"
if [[ -n "$BAR" && "$BAR" != none ]]; then pass "the Action bar shows ($BAR)"; else fail "no Action bar after the selection ('$BAR')"; fi
expect_equal "the Action bar sits below the selection" "below" "$(bar_side "$BAR" "$(selection_frame)")"
expect_contains "the overlay is still layer-hosted with the bar up" "view=layer-hosted-scene" "$(send "$APP_SOCK" overlay-facts)"

# 2. The bar's items: Capture and Cancel, each with a tooltip and a whole tile to click.
ITEMS="$(send "$APP_SOCK" overlay-actionbar)"
expect_in_order "the Action bar offers Capture before Pick Color before Cancel" "$(printf '%s\n' "$ITEMS" | grep '^item ' | cut -d'|' -f1-4)" \
  "item capture|Capture|Capture this Area (Enter)|none" "item pick-color|Pick Color|Pick a color from the screen (P)|p" "item cancel|Cancel|Cancel (Esc)|none"
expect_contains "Capture has a tooltip that names Enter" "item capture|Capture|Capture this Area (Enter)|" "$ITEMS"
expect_contains "Cancel has a tooltip that names Esc" "item cancel|Cancel|Cancel (Esc)|" "$ITEMS"
TOOLTIPS_OK=1
while IFS='|' read -r head _title tip _rest; do
  [[ "$head" == item\ * && -z "$tip" ]] && TOOLTIPS_OK=0
done < <(printf '%s\n' "$ITEMS")
expect_equal "every button has a tooltip" "1" "$TOOLTIPS_OK"
# Each button's frame is its whole tile: at least 60 x 30 points and inside the bar.
TILES="$(printf '%s\n' "$ITEMS" | awk -F'|' -v bar="$BAR" '
  BEGIN { split(bar, b, /[ ,x]/) }
  /^item / {
    split($5, f, /[ ,x]/)
    n++
    if (f[3] < 60 || f[4] < 30) small++
    if (f[1] < b[1] || f[2] < b[2] || f[1] + f[3] > b[1] + b[3] || f[2] + f[4] > b[2] + b[4]) outside++
  }
  END { printf "items=%d small=%d outside=%d\n", n, small, outside }')"
expect_contains "each button is a whole tile of at least 60 x 30 points, inside the bar" "small=0 outside=0" "$TILES"

# Tooltips are drawn in the overlay (the system's tooltip window sits below it): resting the pointer
# on a tile shows its tooltip after a moment, moving to another tile or off the bar takes it away.
expect_equal "no tooltip before the pointer is on a tile" "none" "$(fact tooltip)"
read -r TX TY <<<"$(tile_point capture 10 10)"
mouse move 0 "$TX" "$TY" >/dev/null
expect_equal "the pointer is over the Capture tile" "capture" "$(fact hovered)"
expect_equal "its tooltip is not shown the moment the pointer arrives" "none" "$(fact tooltip)"
tooltip_is() { [[ "$(fact tooltip)" == "$1" ]]; }
if wait_until 5 tooltip_is "Capture this Area (Enter)"; then pass "resting on the Capture tile shows its tooltip"; else fail "no tooltip for Capture ('$(fact tooltip)')"; fi
assert_idle_cpu "menu bar app with a tooltip showing" "$APP_PID" 3
read -r TX TY <<<"$(tile_point cancel 10 10)"
mouse move 0 "$TX" "$TY" >/dev/null
expect_equal "moving to the Cancel tile takes the tooltip away" "none" "$(fact tooltip)"
if wait_until 5 tooltip_is "Cancel (Esc)"; then pass "resting on the Cancel tile shows its tooltip"; else fail "no tooltip for Cancel ('$(fact tooltip)')"; fi
mouse move 0 5 5 >/dev/null
expect_equal "moving off the bar takes the tooltip away" "none" "$(fact tooltip)"
expect_equal "and nothing is hovered" "none" "$(fact hovered)"
sleep 1
expect_equal "no tooltip appears later for a tile the pointer left" "none" "$(fact tooltip)"

# A press on the bar's padding is the bar's: it changes nothing and starts no selection.
read -r PX PY PX2 PY2 <<<"$(bar_frame | awk '{ split($1, a, ","); printf "%s %s %s %s", a[1] + 2, a[2] + 2, a[1] + 62, a[2] + 32 }')"
mouse down 0 "$PX" "$PY" >/dev/null
mouse drag 0 "$PX2" "$PY2" >/dev/null
mouse up 0 "$PX2" "$PY2" >/dev/null
expect_equal "a press and drag on the bar's padding changes nothing" "100,60 200x100" "$(selection_frame)"
expect_equal "and the overlay is still adjusting" "adjusting" "$(fact state)"
# A press on a tile that is released away from it is not a click.
read -r TX TY <<<"$(tile_point cancel 10 10)"
mouse move 0 "$TX" "$TY" >/dev/null
mouse down 0 "$TX" "$TY" >/dev/null
mouse up 0 500 350 >/dev/null
expect_equal "a press on Cancel released elsewhere does not cancel" "adjusting" "$(fact state)"
expect_equal "and the overlay is still up" "1" "$(overlay_panels | grep -c '^600x400 ')"

# 3. Keys: a key no item claims is ignored, Enter does nothing before a selection exists, and an
#    item's own key would run it (47-color-picker.sh drives P).
send "$APP_SOCK" "overlay-key z" >/dev/null
expect_equal "a key no Action bar item claims does nothing" "adjusting" "$(fact state)"
area_cancel
sleep 1
BAR_FIRST_AFTER="$(precise_mb "$APP_PID")"
if awk -v a="$BAR_FIRST_AFTER" -v b="$BAR_FIRST_BEFORE" -v max="$BAR_FIRST_USE_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the first Action bar costs at most ${BAR_FIRST_USE_MB_MAX} MB that stays (${BAR_FIRST_BEFORE} MB before, ${BAR_FIRST_AFTER} MB after it was cancelled)"
else
  fail "the first Action bar left the footprint at ${BAR_FIRST_AFTER} MB, from ${BAR_FIRST_BEFORE} MB (limit +${BAR_FIRST_USE_MB_MAX} MB)"
fi

area_start "press-shortcut capture-area" >/dev/null
send "$APP_SOCK" "overlay-key enter" >/dev/null
expect_equal "Enter with no selection captures nothing" "1" "$(overlay_panels | grep -c '^600x400 ')"
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
mouse drag 0 120 90 >/dev/null
send "$APP_SOCK" "overlay-key enter" >/dev/null
expect_equal "Enter in the middle of a drag captures nothing" "1" "$(overlay_panels | grep -c '^600x400 ')"
mouse up 0 120 90 >/dev/null
expect_equal "the drag still ends in an adjustable selection" "adjusting" "$(fact state)"
area_cancel

# 4. The Action bar stays on screen at every edge and corner, and is below the selection, else above
#    it, else inside it. Display 600 x 400.
placement() { # label x1 y1 x2 y2 expected-side
  local label="$1" x1="$2" y1="$3" x2="$4" y2="$5" side="$6" bar
  area_start "press-shortcut capture-area" >/dev/null
  area_drag 0 "$x1" "$y1" "$x2" "$y2"
  bar="$(bar_frame)"
  if in_display "$bar" 600 400; then pass "$label: the Action bar is on screen ($bar)"; else fail "$label: the Action bar is off screen ('$bar')"; fi
  expect_equal "$label: the Action bar is $side the selection" "$side" "$(bar_side "$bar" "$(selection_frame)")"
  area_cancel
}
placement "in the middle" 200 100 400 200 below
placement "top-left corner" 0 0 100 80 below
placement "top edge" 250 0 350 50 below
placement "top-right corner" 500 0 600 80 below
placement "bottom-left corner" 0 320 100 400 above
placement "bottom-right corner" 500 320 600 400 above
placement "bottom edge" 250 350 350 400 above
placement "full-height strip on the left" 0 0 100 400 inside
placement "full-height strip on the right" 500 0 600 400 inside
placement "the whole display" 0 0 600 400 inside

# 5. Resizing from every handle, past the opposite edge as well. Starting from 100,60 200x100.
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
expect_equal "an adjusted selection shows no loupe" "hidden" "$(fact loupe)"
mouse down 0 300 160 >/dev/null   # the bottom-right corner
mouse drag 0 350 200 >/dev/null
expect_equal "the loupe shows while a handle is dragged, for the exact pixel" "shown" "$(fact loupe)"
mouse up 0 350 200 >/dev/null
expect_equal "the loupe goes when the handle is let go" "hidden" "$(fact loupe)"
expect_equal "the bottom-right handle resizes" "0 100,60 250x140" "$(fact selection)"
mouse down 0 225 60 >/dev/null    # the top edge's handle
mouse drag 0 225 40 >/dev/null
mouse up 0 225 40 >/dev/null
expect_equal "the top handle resizes" "0 100,40 250x160" "$(fact selection)"
mouse down 0 100 120 >/dev/null   # the left edge's handle
mouse drag 0 80 120 >/dev/null
mouse up 0 80 120 >/dev/null
expect_equal "the left handle resizes" "0 80,40 270x160" "$(fact selection)"
mouse down 0 350 120 >/dev/null   # the right edge's handle
mouse drag 0 340 120 >/dev/null
mouse up 0 340 120 >/dev/null
expect_equal "the right handle resizes" "0 80,40 260x160" "$(fact selection)"
mouse down 0 210 200 >/dev/null   # the bottom edge's handle
mouse drag 0 210 190 >/dev/null
mouse up 0 210 190 >/dev/null
expect_equal "the bottom handle resizes" "0 80,40 260x150" "$(fact selection)"
mouse down 0 80 40 >/dev/null     # top-left
mouse drag 0 90 50 >/dev/null
mouse up 0 90 50 >/dev/null
expect_equal "the top-left handle resizes" "0 90,50 250x140" "$(fact selection)"
mouse down 0 340 50 >/dev/null    # top-right
mouse drag 0 330 60 >/dev/null
mouse up 0 330 60 >/dev/null
expect_equal "the top-right handle resizes" "0 90,60 240x130" "$(fact selection)"
mouse down 0 90 190 >/dev/null    # bottom-left
mouse drag 0 100 180 >/dev/null
mouse up 0 100 180 >/dev/null
expect_equal "the bottom-left handle resizes" "0 100,60 230x120" "$(fact selection)"
expect_equal "still eight handles after resizing" "8" "$(fact handles)"
IN_BOUNDS="$(bar_frame)"
if in_display "$IN_BOUNDS" 600 400; then pass "the Action bar follows the resized selection and stays on screen"; else fail "the Action bar is off screen after resizing ($IN_BOUNDS)"; fi

# Past the opposite edge: the Area turns over. Selection is now 100,60 230x120 (right edge 330).
mouse down 0 330 120 >/dev/null   # the right edge's handle
mouse drag 0 200 120 >/dev/null
mouse drag 0 40 120 >/dev/null
mouse up 0 40 120 >/dev/null
expect_equal "the right handle dragged past the left edge turns the Area over" "0 40,60 60x120" "$(fact selection)"
mouse down 0 70 180 >/dev/null    # the bottom edge's handle
mouse drag 0 70 100 >/dev/null
mouse drag 0 70 20 >/dev/null
mouse up 0 70 20 >/dev/null
expect_equal "the bottom handle dragged past the top edge turns the Area over" "0 40,20 60x40" "$(fact selection)"
mouse down 0 40 20 >/dev/null     # the top-left corner, dragged past the opposite corner
mouse drag 0 200 150 >/dev/null
mouse up 0 200 150 >/dev/null
expect_equal "a corner dragged past the opposite corner turns the Area over on both axes" "0 100,60 100x90" "$(fact selection)"
mouse down 0 100 60 >/dev/null
mouse drag 0 -50 -50 >/dev/null
mouse up 0 -50 -50 >/dev/null
expect_equal "a handle stops at the display's edge" "0 0,0 200x150" "$(fact selection)"
mouse down 0 200 150 >/dev/null
mouse drag 0 200 150.5 >/dev/null  # under 3 pt: nothing moves
mouse up 0 200 150.5 >/dev/null
expect_equal "a handle press under 3 pt changes nothing" "0 0,0 200x150" "$(fact selection)"

# 6. Moving: a drag inside moves the Area, kept inside the display; a small jitter moves nothing.
mouse down 0 50 30 >/dev/null
mouse drag 0 150 130 >/dev/null
mouse up 0 150 130 >/dev/null
expect_equal "dragging inside moves the selection" "0 100,100 200x150" "$(fact selection)"
mouse down 0 150 130 >/dev/null
mouse drag 0 1000 1000 >/dev/null
mouse up 0 1000 1000 >/dev/null
expect_equal "the selection stops at the display's edge" "0 400,250 200x150" "$(fact selection)"
mouse down 0 500 320 >/dev/null
mouse drag 0 501 321 >/dev/null
mouse up 0 501 321 >/dev/null
expect_equal "a 1 pt jitter inside the selection moves nothing" "0 400,250 200x150" "$(fact selection)"
expect_equal "the moved selection keeps its handles" "8" "$(fact handles)"
if in_display "$(bar_frame)" 600 400; then pass "the Action bar stays on screen with the selection at the display's corner"; else fail "the Action bar is off screen at the display's corner"; fi

# 7. A plain click away from the selection changes nothing; a drag away starts a new selection.
mouse down 0 100 50 >/dev/null
mouse up 0 100 50 >/dev/null
expect_equal "a click away from the selection keeps it" "0 400,250 200x150" "$(fact selection)"
expect_equal "and it is still adjustable" "adjusting" "$(fact state)"
expect_equal "with its eight handles" "8" "$(fact handles)"
mouse down 0 100 50 >/dev/null
mouse drag 0 101 51 >/dev/null
mouse up 0 101 51 >/dev/null
expect_equal "a jitter under 3 pt away from the selection keeps it" "0 400,250 200x150" "$(fact selection)"
mouse down 0 20 300 >/dev/null
mouse drag 0 50 320 >/dev/null
mouse drag 0 80 340 >/dev/null
mouse up 0 80 340 >/dev/null
expect_equal "a drag away from the selection replaces it" "0 20,300 60x40" "$(fact selection)"
expect_equal "and it is adjustable" "adjusting" "$(fact state)"
expect_equal "with its eight handles on the new selection" "8" "$(fact handles)"
mouse move 0 10 10 >/dev/null
# Moving the pointer while adjusting changes nothing on screen: no layer work.
UPDATES_BEFORE="$(fact scene-updates)"
for i in $(seq 1 50); do mouse move 0 $((20 + i * 5)) $((20 + i * 3)) >/dev/null; done
expect_equal "pointer moves while adjusting redraw nothing" "$UPDATES_BEFORE" "$(fact scene-updates)"
area_cancel

# 8. Esc cancels with the Action bar up, and the Shortcut works again at once.
FILES_BEFORE="$(capture_files)"
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels with the Action bar showing" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone after Esc" "" "$(overlay_panels)"
expect_equal "no Editor opened" "" "$(open_editors 2>/dev/null)"
expect_equal "no Capture file was made" "$FILES_BEFORE" "$(capture_files)"
expect_equal "nothing reached the pasteboard" "" "$(send "$APP_SOCK" pasteboard-types)"
expect_equal "the Shortcut works again straight after Esc" "ok" "$(area_start "press-shortcut capture-area")"
expect_equal "and shows the overlay again" "1" "$(overlay_panels | grep -c '^600x400 ')"
area_drag 0 100 60 300 160
press_tile cancel -3 -3   # near the tile's bottom-right corner, away from its glyph and title
expect_equal "the Cancel button cancels, clicked near its corner" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the overlay is gone after Cancel" "" "$(overlay_panels)"
expect_equal "the Shortcut works again straight after Cancel" "ok" "$(area_start "press-shortcut capture-area")"
area_cancel

# 9. Capture: the button, Enter and a double-click inside the selection, pixel-exact.
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
press_tile capture 3 3   # near the tile's top-left corner, away from its glyph and title
if area_result; then pass "the Capture button: Capture $EDITOR_N opens in the Editor"; else fail "the Capture button finished with '$AREA_REPLY'"; fi
expect_equal "the overlay is gone once the Capture is taken" "" "$(overlay_panels)"
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Capture button at 1x" 1 200 100 600 400 100 60 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi

area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
mouse down 0 200 110 >/dev/null   # a click inside changes nothing; a resize does, and Enter captures that
mouse up 0 200 110 >/dev/null
mouse down 0 300 160 >/dev/null
mouse drag 0 340 180 >/dev/null
mouse up 0 340 180 >/dev/null
send "$APP_SOCK" "overlay-key enter" >/dev/null
if area_result; then pass "Enter captures the adjusted selection: Capture $EDITOR_N"; else fail "Enter finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Enter after resizing at 1x" 1 240 120 600 400 100 60 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi

# A double-click inside the selection captures; the jitter between its clicks moves nothing, so the
# Capture is exactly the selection that was on screen.
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
mouse down 0 200 110 1 >/dev/null
mouse drag 0 201 111 >/dev/null
mouse up 0 201 111 >/dev/null
expect_equal "a click and a little jitter inside the selection leave it where it is" "0 100,60 200x100" "$(fact selection)"
mouse down 0 201 111 2 >/dev/null
if area_result; then pass "a double-click inside the selection captures: Capture $EDITOR_N"; else fail "the double-click finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "double-click at 1x" 1 200 100 600 400 100 60 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi
# A double-click outside the selection does not capture.
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
mouse down 0 450 300 2 >/dev/null
mouse up 0 450 300 >/dev/null
expect_equal "a double-click away from the selection captures nothing" "1" "$(overlay_panels | grep -c '^600x400 ')"
area_cancel

# 10. At 2x with fractional points, both edges round to the nearest device pixel: 20.3,30.4 to
#     120.8,90.6 points is pixels 41,61 to 242,181: 201 x 120 of the 602 x 374 fixture.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 20.3 30.4 120.8 90.6
send "$APP_SOCK" "overlay-key enter" >/dev/null
if area_result; then pass "2x: Enter captures: Capture $EDITOR_N"; else fail "2x: Enter finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Action bar Capture at 2x" 2 201 120 602 374 41 61 "Display P3" "$P3_SHA_AREA" 5669
fi
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null

# 11. A click on a highlighted window becomes the selection, and the Action bar takes it from there.
area_start "press-shortcut capture-area" >/dev/null
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
mouse up 0 70 50 >/dev/null
expect_equal "a click on a highlighted window selects it" "0 60,40 100x60" "$(fact selection)"
expect_equal "the window selection is adjustable" "adjusting" "$(fact state)"
expect_equal "and has eight handles" "8" "$(fact handles)"
expect_equal "nothing was captured by the click" "1" "$(overlay_panels | grep -c '^600x400 ')"
if in_display "$(bar_frame)" 600 400; then pass "the Action bar shows for the window"; else fail "no Action bar for the window selection"; fi
send "$APP_SOCK" "overlay-key enter" >/dev/null
if area_result; then pass "Enter captures the selected window: Capture $EDITOR_N"; else fail "capturing the selected window finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "selected window at 1x" 1 100 60 600 400 60 40 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi
# A window click then a double-click captures that window: its jitter moves nothing.
area_start "press-shortcut capture-area" >/dev/null
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
mouse up 0 70 50 >/dev/null
mouse down 0 70 50 2 >/dev/null
if area_result; then pass "a double-click on a window captures it"; else fail "the window double-click finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "double-clicked window at 1x" 1 100 60 600 400 60 40 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi

# 12. With Capture on release the same gestures capture at once, so the ticket 5 behaviour is
#     unchanged; changing the setting takes effect at the next release.
send "$APP_SOCK" "defaults-set afterSelectingArea captureOnRelease" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
expect_contains "the setting reads Capture on release" "after-selecting=captureOnRelease" "$(send "$APP_SOCK" overlay-facts)"
area_drag 0 100 60 300 160
if area_result; then pass "Capture on release: letting go captures"; else fail "Capture on release finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Capture on release at 1x" 1 200 100 600 400 100 60 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi
area_start "press-shortcut capture-area" >/dev/null
mouse move 0 70 50 >/dev/null
mouse down 0 70 50 >/dev/null
mouse up 0 70 50 >/dev/null
if area_result; then pass "Capture on release: a click on a window captures it at once"; else fail "the window click finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "window with Capture on release at 1x" 1 100 60 600 400 60 40 "sRGB IEC61966-2.1" "$SRGB_SHA_AREA" 2835
fi
send "$APP_SOCK" "defaults-set afterSelectingArea showActionBar" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
expect_equal "back at Show Action bar the next release keeps the selection" "adjusting" "$(fact state)"
area_cancel

# 13. A second display (800 x 300 at 2x, the bar is about 450 pt wide, and over 570 pt with Pick Color): the selection and its bar stay on the display where the drag
#     started, and each display has its own ID.
send "$APP_SOCK" "fixture-extra-display 2 800 300" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
DISPLAY_IDS="$(fact display-ids)"
expect_equal "each display has an ID of its own" "2" "$(printf '%s\n' "$DISPLAY_IDS" | tr ',' '\n' | sort -u | grep -c .)"
area_drag 1 20 20 120 90
expect_equal "the selection is on the second display" "1 20,20 100x70" "$(fact selection)"
if in_display "$(bar_frame)" 800 300; then pass "the Action bar is on the second display"; else fail "the Action bar is not inside the second display ($(bar_frame))"; fi
expect_equal "eight handles on the second display" "8" "$(fact handles)"
send "$APP_SOCK" "overlay-key enter" >/dev/null
if area_result; then pass "the Area on the second display is captured with Enter"; else fail "the second display's Capture finished with '$AREA_REPLY'"; fi
if [[ -n "${EDITOR_N:-}" ]]; then
  area_png_check "Action bar Capture on the second display (2x)" 2 200 140 1600 600 40 40 "Display P3" "$P3_SHA_AREA" 5669
fi
send "$APP_SOCK" "fixture-extra-display none" >/dev/null

# 14. Bad input to the test command is refused.
area_start "press-shortcut capture-area" >/dev/null
expect_contains "overlay-mouse refuses a click count of 0" "error" "$(mouse down 0 10 10 0)"
expect_equal "overlay-mouse takes a click count" "ok" "$(mouse move 0 10 10 1)"
area_cancel

# 15. Memory and CPU. A 2560 x 1600 pixel display (16 MB of pixels): five Captures through the Action
#     bar leave memory where it was, the overlay with the bar up holds its frame once, and nothing
#     runs while the bar shows.
send "$APP_SOCK" "fixture-display 2 1280 800" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100.5 100.5 600.5 500.5
send "$APP_SOCK" "overlay-key enter" >/dev/null
area_result && copy_closes_editor   # warm up allocator pools
sleep 1
BAR_BASELINE="$(precise_mb "$APP_PID")"
BAR_PEAK=0
for _ in 1 2 3 4 5; do
  area_start "press-shortcut capture-area" >/dev/null
  area_drag 0 100.5 100.5 600.5 500.5
  mouse down 0 350 300 >/dev/null
  mouse drag 0 380 330 >/dev/null
  mouse up 0 380 330 >/dev/null
  NOW="$(precise_mb "$APP_PID")"
  BAR_PEAK="$(awk -v a="$BAR_PEAK" -v b="$NOW" 'BEGIN { print (b > a ? b : a) }')"
  send "$APP_SOCK" "overlay-key enter" >/dev/null
  area_result && copy_closes_editor
done
sleep 1
BAR_AFTER="$(precise_mb "$APP_PID")"
if awk -v a="$BAR_AFTER" -v b="$BAR_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory returns to baseline after five Action bar Captures (${BAR_BASELINE} MB before, ${BAR_AFTER} MB after)"
else
  fail "memory grew from ${BAR_BASELINE} MB to ${BAR_AFTER} MB over five Action bar Captures (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
if awk -v a="$BAR_AFTER" -v b="$BAR_FIRST_BEFORE" -v max="$BAR_FIRST_USE_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory is where it was before the first Action bar (${BAR_FIRST_BEFORE} MB then, ${BAR_AFTER} MB now, limit +${BAR_FIRST_USE_MB_MAX} MB)"
else
  fail "memory is ${BAR_AFTER} MB after the Action bar Captures, ${BAR_FIRST_BEFORE} MB before the first bar (limit +${BAR_FIRST_USE_MB_MAX} MB)"
fi
echo "     Action bar peak ${BAR_PEAK} MB with a 16 MB frozen frame on screen (${BAR_BASELINE} MB at rest)"
if awk -v peak="$BAR_PEAK" -v base="$BAR_BASELINE" 'BEGIN { exit !(peak - base <= 16 + 10) }'; then
  pass "the overlay with the Action bar holds the frozen frame once: peak ${BAR_PEAK} MB over a ${BAR_BASELINE} MB base"
else
  fail "the overlay with the Action bar peaks at ${BAR_PEAK} MB over a ${BAR_BASELINE} MB base: more than one copy of a 16 MB frame"
fi
if [[ -z "$(helper_pid)" ]]; then pass "no helper process is left after the Action bar Captures"; else fail "an Editor helper is still running"; fi

send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 60 300 160
assert_idle_cpu "menu bar app with the Action bar showing" "$APP_PID" 4
area_cancel
assert_idle_cpu "menu bar app after the Action bar Captures" "$APP_PID" 5

# Leave what the next flows expect: no helper, a small fixture display, nothing on the pasteboard.
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 area_no_helper
# The flows after this one see the process as flow 20 measured it at rest, plus what is allowed.
sleep 1
BAR_END="$(footprint_mb "$APP_PID")"
if awk -v a="$BAR_END" -v b="$AT_REST" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory is back near the at-rest footprint after the Action bar flow (${AT_REST} MB at rest, ${BAR_END} MB after)"
else
  fail "memory is ${BAR_END} MB after the Action bar flow, ${AT_REST} MB at rest (limit +${FOOTPRINT_FROM_REST_MB_MAX} MB)"
fi
if awk -v a="$BAR_END" -v max="$FOOTPRINT_MB_MAX" 'BEGIN { exit !(a > 0 && a <= max) }'; then
  pass "memory is under the ${FOOTPRINT_MB_MAX} MB ceiling after the Action bar flow (${BAR_END} MB)"
else
  fail "memory is ${BAR_END} MB after the Action bar flow (ceiling ${FOOTPRINT_MB_MAX} MB)"
fi
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
