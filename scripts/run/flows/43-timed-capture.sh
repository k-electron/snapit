# Flow: Timed Capture. The Action bar's timer slider (1-10 s, remembered across launches) and
# "Capture in N s". Starting one takes the overlay away and leaves a click-through border around
# the Area and a countdown badge with a ✕ (real panels, seen through the window server); the ✕
# (on mouse-up) and the Area Shortcut cancel; at zero a FRESH Capture is taken (the fixture's frames
# change per call: a stamp in the corner counts them) with snapit's own windows excluded (the fixture
# paints any that are not), cropped to the Area and opened in the Editor. Checks the pixels at 1x
# and 2x, the Editor warm-up and a helper that quit during the countdown, a failed Capture at zero,
# memory, and that the slider's value survives a relaunch. Uses the helpers of
# 40-area-capture.sh and 42-action-bar.sh. Sourced by scripts/check-run.sh.
# shellcheck shell=bash

timed() { send "$APP_SOCK" timed-facts | sed -n "s/^$1=//p"; }
timed_is() { [[ "$(timed "$1")" == "$2" ]]; }
tmouse() { send "$APP_SOCK" "timed-mouse $*"; }
timer_title() { send "$APP_SOCK" overlay-actionbar | awk -F'|' '$1 == "item timed-capture" { print $2 }'; }
slider_title() { send "$APP_SOCK" overlay-actionbar | awk -F'|' '$1 == "item timer" { print $2 }'; }
# slider_press <dx>: a press on the slider tile, dx points in from its left edge (dx may lie outside
# the tile); slider_drag moves the held pointer; slider_release lets go at the pointer's last place.
SLIDER_Y=17
slider_point() { read -r SX SY <<<"$(tile_point timer 0 "$SLIDER_Y" | awk -v dx="$1" '{ printf "%s %s", $1 + dx, $2 }')"; }
slider_press() {
  slider_point "$1"
  mouse move 0 "$SX" "$SY" >/dev/null
  mouse down 0 "$SX" "$SY" >/dev/null
}
slider_drag() {
  slider_point "$1"
  mouse drag 0 "$SX" "$SY" >/dev/null
}
slider_release() { mouse up 0 "$SX" "$SY" >/dev/null; }
# slider_to <dx>: a whole click on the slider.
slider_to() { slider_press "$1"; slider_release; }
overlay_gone() { [[ "$(overlay_panels | grep -c '^600x400 ')" == "0" ]]; }
countdown_windows() { overlay_panels | grep -c .; }
no_countdown_windows() { [[ "$(countdown_windows)" == "0" ]]; }
no_helper_running() { [[ "$(helper_count)" == "0" ]]; }
# timed_png <path>: copies the Capture open in the Editor (which closes it) and saves the PNG.
timed_png() {
  rm -f "$1"  # a Capture that did not open must not be read as the file of the one before
  send "$APP_SOCK" pasteboard-clear >/dev/null
  copy_closes_editor
  send "$APP_SOCK" "pasteboard-dump-png $1" >/dev/null
}
# timed_start <x1> <y1> <x2> <y2>: shows the overlay, drags an Area and presses "Capture in N s".
timed_start() {
  area_start "press-shortcut capture-area" >/dev/null
  area_drag 0 "$1" "$2" "$3" "$4"
  press_tile timed-capture 10 10
  wait_until 5 timed_is state counting || fail "a countdown did not start after 'Capture in N s' (the Capture is '$(send "$APP_SOCK" overlay-facts | head -1)', countdown '$(timed state)')"
}
SRGB_SHA_TIMED="$("$INSPECT" profile-sha srgb)"
P3_SHA_TIMED="$("$INSPECT" profile-sha displayP3)"

send "$APP_SOCK" "fixture-extra-display none" >/dev/null
send "$APP_SOCK" "fixture-delay 0" >/dev/null
send "$APP_SOCK" "fixture-fail off" >/dev/null
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
send "$APP_SOCK" "defaults-set afterSelectingArea nonsense" >/dev/null
wait_until 10 no_helper_running

# 1. The bar offers the timer and "Capture in N s" between Capture and Cancel; the timer is 3 s
#    until the slider moves; both have a tooltip and a whole tile of at least 60 x 30 points.
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 200 100 400 300
ITEMS="$(send "$APP_SOCK" overlay-actionbar)"
expect_in_order "the Action bar offers Capture, the timer, Capture in N s and Cancel, in that order" \
  "$(printf '%s\n' "$ITEMS" | grep '^item ' | cut -d'|' -f1)" "item capture" "item timer" "item timed-capture" "item cancel"
expect_equal "the timer is 3 s before the slider moves" "Capture in 3 s" "$(timer_title)"
expect_contains "the timer has a tooltip" "item timer|Timer 3 s|Timer: 1 to 10 s for a Timed Capture|" "$ITEMS"
expect_contains "Capture in N s has a tooltip" "item timed-capture|Capture in 3 s|Capture this Area after the countdown|" "$ITEMS"
TIMED_TILES="$(printf '%s\n' "$ITEMS" | awk -F'|' -v bar="$(bar_frame)" '
  BEGIN { split(bar, b, /[ ,x]/) }
  $1 == "item timer" || $1 == "item timed-capture" {
    split($5, f, /[ ,x]/)
    n++
    if (f[3] < 60 || f[4] < 30) small++
    if (f[1] < b[1] || f[2] < b[2] || f[1] + f[3] > b[1] + b[3] || f[2] + f[4] > b[2] + b[4]) outside++
  }
  END { printf "tiles=%d small=%d outside=%d\n", n, small, outside }')"
expect_equal "the timer and Capture in N s are whole tiles of at least 60 x 30 points, inside the bar" "tiles=2 small=0 outside=0" "$TIMED_TILES"
BAR0="$(bar_frame)"
if in_display "$BAR0" 600 400; then pass "the bar with the timer is on screen at this display's width"; else fail "the bar ($BAR0) does not fit a 600 x 400 display"; fi

# 2. The slider: a press sets the whole second under the pointer, a drag follows it past the ends of
#    the tile, and the value is stored when it changes (the button's words follow). Nothing is captured.
slider_to 72
expect_equal "a press at the slider's right end is 10 s" "Capture in 10 s" "$(timer_title)"
expect_equal "and the timer's value is stored" "10" "$(send "$APP_SOCK" "defaults-get timedCaptureSeconds")"
slider_to 16
expect_equal "a press at the slider's left end is 1 s" "Capture in 1 s" "$(timer_title)"
slider_press 47
expect_equal "a press at 47 points is 6 s" "Capture in 6 s" "$(timer_title)"
slider_drag 28
expect_equal "dragging left follows the pointer to 3 s" "Capture in 3 s" "$(timer_title)"
slider_drag 84
slider_drag 130
expect_equal "dragging past the right end stays at 10 s" "Capture in 10 s" "$(timer_title)"
slider_drag -30
expect_equal "dragging past the left end stays at 1 s" "Capture in 1 s" "$(timer_title)"
slider_drag 47
mouse drag 0 "$SX" 380 >/dev/null
mouse up 0 "$SX" 380 >/dev/null
expect_equal "letting go away from the tile keeps the value (6 s)" "Capture in 6 s" "$(timer_title)"
expect_equal "the slider's own title follows" "Timer 6 s" "$(slider_title)"
expect_equal "using the slider captures nothing and leaves the overlay adjusting" "adjusting" "$(fact state)"
expect_equal "the bar keeps its frame while the slider moves" "$BAR0" "$(bar_frame)"
# A press on "Capture in N s" that is let go away from it starts nothing.
read -r TX TY <<<"$(tile_point timed-capture 10 10)"
mouse move 0 "$TX" "$TY" >/dev/null
mouse down 0 "$TX" "$TY" >/dev/null
mouse up 0 100 380 >/dev/null
expect_equal "a press on Capture in N s let go elsewhere starts no countdown" "none" "$(timed state)"
expect_equal "and the overlay is still up" "adjusting" "$(fact state)"
slider_to 28
expect_equal "a press at 28 points is 3 s" "Capture in 3 s" "$(timer_title)"
area_cancel

# 2b. A bar wider than the display is centred on it: it overflows both sides equally.
send "$APP_SOCK" "fixture-display 1 300 400" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 20 100 120 200
NARROW_BAR="$(bar_frame)"
expect_equal "a bar wider than a 300 point display is centred on it" "150" "$(printf '%s\n' "$NARROW_BAR" | awk '{ split($1, p, ","); split($2, s, "x"); printf "%.0f", p[1] + s[1] / 2 }')"
area_cancel
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null

# 3. A countdown of 3 s: the overlay goes, a click-through border and a badge stay, the ticks run
#    3, 2, 1, and nothing is captured until zero. The Capture at zero is fresh and opens in the
#    Editor with exactly the Area's pixels.
FRESH0="$(timed fresh-captures)"
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 200 100 400 300
press_tile timed-capture 10 10
if wait_until 5 timed_is state counting; then pass "Capture in N s starts a countdown"; else fail "no countdown started ('$(timed state)')"; fi
expect_equal "the overlay is gone while the countdown runs" "none" "$(send "$APP_SOCK" overlay-facts)"
expect_equal "no full-display panel is left" "1" "$(overlay_gone && echo 1 || echo 0)"
expect_equal "the countdown is of 3 s" "3" "$(timed seconds)"
expect_equal "a tick is scheduled while it counts" "yes" "$(timed ticking)"
expect_equal "the border sits just outside the Area (2 points)" "198,98 204x204" "$(timed border)"
expect_equal "the Area is the selection" "200,100 200x200" "$(timed area)"
expect_equal "the border is four panels" "4" "$(timed border-panels)"
expect_equal "every border panel lets clicks through" "yes" "$(timed border-click-through)"
expect_equal "the badge takes clicks (its ✕ is the one clickable thing)" "no" "$(timed badge-click-through)"
PANELS="$(overlay_panels)"
expect_equal "the window server shows two panels of 204 x 2 points" "2" "$(printf '%s\n' "$PANELS" | grep -c '^204x2 ')"
expect_equal "and two of 2 x 200 points" "2" "$(printf '%s\n' "$PANELS" | grep -c '^2x200 ')"
expect_equal "and the badge, 84 x 30 points" "1" "$(printf '%s\n' "$PANELS" | grep -c '^84x30 ')"
expect_equal "and nothing else: five panels" "5" "$(countdown_windows)"
expect_equal "no Capture is taken while it counts" "$FRESH0" "$(timed fresh-captures)"
expect_equal "the badge is below the border, aligned to its right edge" "318,308 84x30" "$(timed badge)"
# macOS posts the displays-changed notification for a Dock that moved too (and a virtual machine posts it
# for nothing): with the displays as they were, the countdown goes on.
send "$APP_SOCK" overlay-screens-noise >/dev/null
expect_equal "a displays-changed notification with the same displays does not end the countdown" "counting" "$(timed state)"
SEQ=""
LAST=""
for _ in $(seq 1 40); do
  R="$(timed remaining)"
  if [[ -n "$R" && "$R" != "$LAST" ]]; then SEQ="$SEQ $R"; LAST="$R"; fi
  [[ "$(timed state)" == "none" ]] && break
  sleep 0.2
done
expect_contains "the badge counts down 3, 2, 1" " 3 2 1" "$SEQ"
area_result
expect_equal "at zero the Capture opens in the Editor" "opened" "${AREA_REPLY%% *}"
expect_equal "the countdown is gone" "none" "$(timed state)"
expect_equal "and so is its tick" "no" "$(timed ticking)"
expect_equal "a fresh Capture was taken, once" "$((FRESH0 + 1))" "$(timed fresh-captures)"
FRESH_AFTER="$(timed fresh-after)"
if awk -v s="$FRESH_AFTER" 'BEGIN { exit !(s + 0 >= 3 && s + 0 < 4.5) }'; then
  pass "it was taken at zero: ${FRESH_AFTER} s after the countdown started"
else
  fail "the fresh Capture was taken ${FRESH_AFTER} s after the start (expected 3 s)"
fi
if (($(timed fresh-excluded) >= 5)); then pass "the content filter excluded snapit's border and badge ($(timed fresh-excluded) windows)"; else fail "excluded only $(timed fresh-excluded) windows"; fi
expect_equal "the border and the badge are gone from the screen" "1" "$(no_countdown_windows && echo 1 || echo 0)"
area_png_check "Timed Capture at 1x" 1 200 200 600 400 200 100 "sRGB IEC61966-2.1" "$SRGB_SHA_TIMED" 2835

# 4. The Capture is fresh, not the frozen frame: the fixture stamps a 4 x 4 pixel square in the
#    display's corner with the number of fresh Captures so far, and the frozen frame has none.
#    An Area from the corner holds the stamp.
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 0 0 150 100
press_tile timed-capture 10 10
wait_until 5 timed_is state counting
area_result
STAMP_N="$(timed fresh-captures)"
timed_png "$RUN_ROOT/timed.png"
expect_equal "the Capture holds the fresh frame's stamp at its corner (Capture number $STAMP_N)" "250,$STAMP_N,77" "$("$INSPECT" raw-pixel "$RUN_ROOT/timed.png" 0 0)"
expect_equal "the stamp is 4 x 4 pixels" "250,$STAMP_N,77" "$("$INSPECT" raw-pixel "$RUN_ROOT/timed.png" 3 3)"
expect_equal "and ends there: the pixel beside it is the fixture's" "1,2,40" "$("$INSPECT" raw-pixel "$RUN_ROOT/timed.png" 4 4)"
rm -f "$RUN_ROOT/timed.png"

# 5. snapit's own windows are never in the Capture. An Area over the whole display leaves the badge
#    no room outside it, so it sits inside the Area's corner: the only changes to the fixture are the
#    stamp. With the fixture told to let the windows through, the same Capture shows the badge.
for SCALE in 1 2; do
  send "$APP_SOCK" "fixture-display $SCALE 600 400" >/dev/null
  PX=$((600 * SCALE))
  PY=$((400 * SCALE))
  send "$APP_SOCK" "fixture-fresh-ignores-exclusions off" >/dev/null
  timed_start 0 0 600 400
  expect_equal "an Area over the whole display puts the badge inside its corner at ${SCALE}x" "1" "$(timed badge | awk '{ split($1, p, ","); print (p[1] > 400 && p[2] < 40) ? 1 : 0 }')"
  area_result
  timed_png "$RUN_ROOT/timed.png"
  DIFF="$("$INSPECT" diff-fixture "$RUN_ROOT/timed.png" "$PX" "$PY")"
  expect_equal "no border or badge in the whole-display Capture at ${SCALE}x: only the 16 stamp pixels differ" "changed=16" "$(printf '%s\n' "$DIFF" | grep '^changed=')"
  expect_equal "at the display's corner" "bbox=0,0,4,4" "$(printf '%s\n' "$DIFF" | grep '^bbox=')"

  send "$APP_SOCK" "fixture-fresh-ignores-exclusions on" >/dev/null
  timed_start 0 0 600 400
  area_result
  timed_png "$RUN_ROOT/timed.png"
  DIFF="$("$INSPECT" diff-fixture "$RUN_ROOT/timed.png" "$PX" "$PY")"
  CHANGED="$(printf '%s\n' "$DIFF" | sed -n 's/^changed=//p')"
  if ((CHANGED > 1000 * SCALE * SCALE)); then
    pass "a Capture that let the windows through would show the badge at ${SCALE}x ($CHANGED pixels differ): the check can fail"
  else
    fail "with exclusions ignored the Capture changed only $CHANGED pixels at ${SCALE}x"
  fi
  send "$APP_SOCK" "fixture-fresh-ignores-exclusions off" >/dev/null
  rm -f "$RUN_ROOT/timed.png"
done

# 6. Fresh pixels at 2x, Display P3: an Area at fractional points snaps to device pixels and the
#    crop of the fresh frame is the fixture's pixels at that place.
send "$APP_SOCK" "fixture-display 2 600 400" >/dev/null
timed_start 50.5 40.25 250.5 190.25
area_result
area_png_check "Timed Capture at 2x" 2 400 300 1200 800 101 81 "Display P3" "$P3_SHA_TIMED" 5669
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null

# 7. The badge's ✕ cancels, on mouse-up only: a press on it let go elsewhere, or a press on the
#    seconds, does nothing. Resting on the ✕ shows its tooltip in the badge's own layer-level panel.
FRESH1="$(timed fresh-captures)"
timed_start 200 100 400 300
tmouse move cross >/dev/null
if wait_until 5 timed_is tooltip "Cancel the countdown"; then pass "resting on the ✕ shows its tooltip"; else fail "no tooltip on the ✕ ('$(timed tooltip)')"; fi
expect_equal "the tooltip is a sixth panel" "6" "$(countdown_windows)"
tmouse move away >/dev/null
expect_equal "moving off the ✕ takes it away" "none" "$(timed tooltip)"
tmouse down cross >/dev/null
expect_equal "a press on the ✕ alone does not cancel" "counting" "$(timed state)"
tmouse up away >/dev/null
expect_equal "a press on the ✕ let go away from it does not cancel" "counting" "$(timed state)"
tmouse down body >/dev/null
tmouse up body >/dev/null
expect_equal "a click on the badge's seconds does not cancel" "counting" "$(timed state)"
tmouse down cross >/dev/null
tmouse up cross >/dev/null
CANCEL_REPLY="$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "the ✕ on mouse-up cancels cleanly" "cancelled" "$CANCEL_REPLY"
expect_equal "the countdown and its tick are gone" "none,no" "$(timed state),$(timed ticking)"
expect_equal "no panel is left" "1" "$(no_countdown_windows && echo 1 || echo 0)"
expect_equal "nothing was captured" "$FRESH1" "$(timed fresh-captures)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
if wait_until 10 no_helper_running; then pass "cancelling quits the helper that warmed up for the Capture"; else fail "a helper is still running after the ✕"; fi
expect_equal "and the warm-up is over" "idle" "$(send "$APP_SOCK" "editor-warm-up state")"
# ... and well past the old zero nothing more happens.
sleep 3.5
expect_equal "no Capture is taken after a cancel" "$FRESH1" "$(timed fresh-captures)"

# 8. The Area Shortcut cancels the countdown too; the Screen, Window and Pick Color Shortcuts do not
#    start anything (they meet the busy Capture). The Shortcut works again at once.
timed_start 200 100 400 300
expect_equal "the Screen Shortcut during a countdown does nothing" "ok" "$(send_slow "$APP_SOCK" "press-shortcut capture-screen")"
expect_equal "the countdown is still running" "counting" "$(timed state)"
expect_equal "the Window Shortcut during a countdown does nothing" "ok" "$(send_slow "$APP_SOCK" "press-shortcut capture-window")"
expect_equal "the countdown is still running after the Window Shortcut" "counting" "$(timed state)"
expect_equal "and no window overlay opened" "none" "$(send "$APP_SOCK" overlay-facts)"
expect_equal "the Pick Color Shortcut during a countdown does nothing" "ok" "$(send_slow "$APP_SOCK" "press-shortcut pick-color")"
expect_equal "the countdown is still running after the Pick Color Shortcut" "counting" "$(timed state)"
expect_equal "and no Color picker overlay opened" "none" "$(send "$APP_SOCK" overlay-facts)"
expect_equal "the Area Shortcut during the countdown replies" "ok" "$(send_slow "$APP_SOCK" "press-shortcut capture-area")"
expect_equal "and cancels it" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "no countdown, tick or panel is left" "none,no,1" "$(timed state),$(timed ticking),$(no_countdown_windows && echo 1 || echo 0)"
expect_equal "nothing was captured" "$FRESH1" "$(timed fresh-captures)"
if wait_until 10 no_helper_running; then pass "the Shortcut's cancel quits the helper that warmed up"; else fail "a helper is still running after the Shortcut's cancel"; fi
area_start "press-shortcut capture-area" >/dev/null
expect_contains "the Area Shortcut starts a new overlay after a cancelled countdown" "state=" "$(send "$APP_SOCK" overlay-facts)"
area_cancel

# 9. A display change cancels a countdown, as it ends the overlay.
timed_start 200 100 400 300
send "$APP_SOCK" overlay-screens-changed >/dev/null
expect_equal "a change of displays cancels the countdown" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
expect_equal "no countdown, tick or panel is left" "none,no,1" "$(timed state),$(timed ticking),$(no_countdown_windows && echo 1 || echo 0)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 no_helper_running

# 10. The Editor warm-up goes with the Capture: it starts when the Area Shortcut is pressed and the
#     helper is warm while the seconds run. A helper that quit meanwhile (the last Editor closed:
#     the warm state is stale) does not stop the Capture: it opens, in a new helper.
timed_start 200 100 400 300
if wait_until 8 warm_is warm; then pass "the Editor helper is warm during the countdown"; else fail "the helper is not warm during the countdown ('$(send "$APP_SOCK" "editor-warm-up state")')"; fi
area_result
expect_equal "the Capture opens in the warm helper" "opened" "${AREA_REPLY%% *}"
expect_equal "the helper is no longer in a warm-up" "idle" "$(send "$APP_SOCK" "editor-warm-up state")"
timed_png "$RUN_ROOT/timed.png"
rm -f "$RUN_ROOT/timed.png"
wait_until 10 no_helper_running

capture_into_editor "menu-click capture.screen"
OPEN_EDITOR="$EDITOR_N"
OPEN_HELPER="$HELPER_PID"
timed_start 200 100 400 300
send "$EDITOR_SOCK" "editor-key $OPEN_EDITOR close" >/dev/null
wait_until 3 gone "$OPEN_HELPER"
echo "     warm-up state after the helper quit during the countdown: $(send "$APP_SOCK" "editor-warm-up state")"
area_result
expect_equal "a helper that quit during the countdown does not stop the Capture" "opened" "${AREA_REPLY%% *}"
expect_equal "the Capture is in a helper again" "1" "$([[ -n "$(helper_pid)" ]] && echo 1 || echo 0)"
expect_contains "and the Editor shows the Area at native pixels" "pixels=200x200" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
area_png_check "Timed Capture in a helper that was started again" 1 200 200 600 400 200 100 "sRGB IEC61966-2.1" "$SRGB_SHA_TIMED" 2835
wait_until 10 no_helper_running
expect_equal "the warm-up is over after the Capture" "idle" "$(send "$APP_SOCK" "editor-warm-up state")"

# 11. A cancel with a stale warm state: the helper (and its last Editor) quit during the countdown,
#     then the ✕ cancels: no helper process is left behind.
capture_into_editor "menu-click capture.screen"
OPEN_EDITOR="$EDITOR_N"
OPEN_HELPER="$HELPER_PID"
timed_start 200 100 400 300
send "$EDITOR_SOCK" "editor-key $OPEN_EDITOR close" >/dev/null
wait_until 3 gone "$OPEN_HELPER"
tmouse down cross >/dev/null
tmouse up cross >/dev/null
expect_equal "the ✕ cancels after the helper quit" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
if wait_until 10 no_helper_running; then pass "no helper is left after a cancel with a stale warm state"; else fail "a helper is still running after the cancel"; fi
expect_equal "and the warm state is idle" "idle" "$(send "$APP_SOCK" "editor-warm-up state")"

# 12. A Capture that fails at zero ends cleanly: panels and tick gone, the failure reported, the
#     gate open again.
timed_start 200 100 400 300
send "$APP_SOCK" "fixture-fail on" >/dev/null
FAIL_REPLY="$(send_slow "$APP_SOCK" overlay-wait)"
send "$APP_SOCK" "fixture-fail off" >/dev/null
expect_contains "a Capture that fails at zero is reported" "failed" "$FAIL_REPLY"
expect_equal "no countdown, tick or panel is left after the failure" "none,no,1" "$(timed state),$(timed ticking),$(no_countdown_windows && echo 1 || echo 0)"
if wait_until 10 no_helper_running; then pass "no helper is left after the failure"; else fail "a helper is still running after the failure"; fi
area_start "press-shortcut capture-area" >/dev/null
expect_contains "a new Capture can start after the failure" "state=" "$(send "$APP_SOCK" overlay-facts)"
area_cancel

# 13. Memory: with a 5K display, the countdown holds no frozen frame (the overlay and its 56 MB image
#     are gone while it counts), and five Timed Captures leave memory where it was.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
TIMED_REST="$(footprint_mb "$APP_PID")"
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 100 100 1400 800
press_tile timed-capture 10 10
wait_until 5 timed_is state counting || fail "no countdown started for the memory check ('$(timed state)')"
# The Capture that is taken at zero is ten seconds away: the frame goes when the overlay does, and the
# process's footprint follows within a few seconds.
expect_memory_returns "the countdown holds no frozen frame" "$APP_PID" "$TIMED_REST" "$(pixels_mb 5120 2880)"
area_result && copy_closes_editor
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
send "$APP_SOCK" "timed-seconds-store 1" >/dev/null
wait_until 10 no_helper_running
sleep 1
TIMED_BASELINE="$(footprint_mb "$APP_PID")"
for _ in 1 2 3 4 5; do
  timed_start 200 100 400 300
  area_result && copy_closes_editor
done
expect_memory_returns "memory returns to baseline after five Timed Captures" "$APP_PID" "$TIMED_BASELINE"
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 no_helper_running
expect_equal "no tick is scheduled at rest" "no" "$(timed ticking)"

# 14. The slider's value is remembered across launches: the Action bar shows it after snapit quits
#     and starts again. A stored value out of range is kept within 1-10 and one that is not a number
#     is 3. This runs in a second snapit under its own root, so the run's own snapit is never
#     relaunched (a relaunched snapit's test defaults cannot change a key an earlier launch stored,
#     which the flows after this one need to do).
send "$APP_SOCK" "timed-seconds-store 3" >/dev/null
MAIN_APP_SOCK="$APP_SOCK"
MAIN_APP_PID="$APP_PID"
TIMED_ROOT="$(mktemp -d /tmp/snapit-run2.XXXXXX)"
APP_SOCK="$TIMED_ROOT/app.sock"
launch_app "$TIMED_ROOT"
if wait_until 15 answers "$APP_SOCK"; then pass "a second snapit starts for the relaunch check"; else fail "the second snapit did not start"; fi
APP_PID="$(pgrep -f "$APP_EXE" | grep -v "^$MAIN_APP_PID\$" | head -1)"
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
for ENTRY in "99:Capture in 10 s" "0:Capture in 1 s" "nonsense:Capture in 3 s" "4:Capture in 4 s"; do
  send "$APP_SOCK" "timed-seconds-store ${ENTRY%%:*}" >/dev/null
  area_start "press-shortcut capture-area" >/dev/null
  area_drag 0 200 100 400 300
  expect_equal "a stored '${ENTRY%%:*}' shows as '${ENTRY#*:}'" "${ENTRY#*:}" "$(timer_title)"
  area_cancel
done
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 200 100 400 300
slider_to 60
expect_equal "the slider moved to 8 s" "Capture in 8 s" "$(timer_title)"
area_cancel
send "$APP_SOCK" quit >/dev/null
if wait_until 60 gone "$APP_PID"; then pass "snapit quits"; else fail "snapit did not quit"; fi
launch_app "$TIMED_ROOT"
if wait_until 15 answers "$APP_SOCK"; then pass "snapit starts again"; else fail "snapit did not start again"; fi
APP_PID="$(pgrep -f "$APP_EXE" | grep -v "^$MAIN_APP_PID\$" | head -1)"
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 200 100 400 300
expect_equal "the timer is still 8 s after a relaunch: the button says so" "Capture in 8 s" "$(timer_title)"
expect_equal "and the slider says so" "Timer 8 s" "$(slider_title)"
area_cancel
send "$APP_SOCK" quit >/dev/null
wait_until 60 gone "$APP_PID"
APP_SOCK="$MAIN_APP_SOCK"
APP_PID="$MAIN_APP_PID"
chmod -R u+w "$TIMED_ROOT" 2>/dev/null
rm -rf "$TIMED_ROOT"
expect_equal "this run's snapit was not disturbed" "$APP_PID" "$(pid_of "$APP_EXE")"

# Leave what the next flows expect: no helper, a small fixture display, nothing on the pasteboard.
send_slow "$APP_SOCK" "editor-warm-up settle" >/dev/null
wait_until 10 no_helper_running
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
