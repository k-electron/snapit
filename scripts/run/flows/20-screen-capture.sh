# Flow: Screen Capture into the Editor, then Copy. Drives the menu item and the Shortcut against
# fixture images at 1x and 2x: the Capture opens in the Editor helper, ⌘C puts the PNG on the
# private pasteboard and closes the Editor, and the PNG is read back and checked pixel by pixel
# and for its metadata with an independent decoder (png-inspect). Sourced by scripts/check-run.sh.
#
# To add a flow, copy this file's shape: switch the fixture, drive the app through a command
# (`menu-click`, `press-shortcut`, or one of your own), then assert on what is observable.
# shellcheck shell=bash

# The at-rest footprint, before any Capture has run.
AT_REST="$(footprint_mb "$APP_PID")"

# 1. Every edge is the test one before anything is driven.
SEAMS="$(send "$APP_SOCK" test-seams)"
expect_contains "test mode: the root is this run's temporary folder" "root=$RUN_ROOT" "$SEAMS"
expect_contains "test mode: the pasteboard is private and named after the run" "pasteboard=dev.snapit.test.$(basename "$RUN_ROOT")" "$SEAMS"
expect_contains "test mode: Save location is inside the root" "save=$RUN_ROOT/save" "$SEAMS"
expect_contains "test mode: the cache folder is the root" "cache=$RUN_ROOT" "$SEAMS"
expect_contains "test mode: Screen Recording reports granted" "permission=granted" "$SEAMS"
expect_equal "test mode: the Capture source is the fixture" "fixture" "$(send "$APP_SOCK" capture-source)"
expect_in_order "test mode: Shortcuts are injected (capture-screen is bound, no hot key is registered)" \
  "$(send "$APP_SOCK" bound-shortcuts)" "capture-screen"
send "$APP_SOCK" "defaults-set probe from-menu-bar-app" >/dev/null
expect_equal "test mode: defaults are readable back through the test store" "from-menu-bar-app" "$(send "$APP_SOCK" "defaults-get probe")"

# The Shortcut seam: ⌃⌥⌘3 (key code 20) by default, shown on the menu item, and changeable.
expect_equal "Screen Shortcut defaults to control-option-command-3" "20 control,option,command" "$(send "$APP_SOCK" "shortcut-combo capture-screen")"
expect_equal "the menu item shows the current Shortcut" "3 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.screen")"
send "$APP_SOCK" "shortcut-set capture-screen 21 control option command" >/dev/null
expect_equal "the menu item follows a changed Shortcut" "4 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.screen")"
send "$APP_SOCK" "shortcut-set capture-screen none" >/dev/null
expect_equal "the menu item shows no Shortcut when it is unassigned" "none" "$(send "$APP_SOCK" "menu-shortcut capture.screen")"
send "$APP_SOCK" "shortcut-set capture-screen 20 control option command" >/dev/null

SRGB_SHA="$("$INSPECT" profile-sha srgb)"
P3_SHA="$("$INSPECT" profile-sha displayP3)"

# capture_check <label> <trigger command> <scale> <points w> <points h> <profile name> <profile sha> <pHYs>
# Chooses the fixture display, triggers the Capture, checks it opened in the Editor, copies it
# with ⌘C and checks the PNG on the pasteboard.
capture_check() {
  local label="$1" trigger="$2" scale="$3" pw="$4" ph="$5" profile="$6" sha="$7" phys="$8"
  local w=$((pw * scale)) h=$((ph * scale)) info

  send "$APP_SOCK" "fixture-display $scale $pw $ph" >/dev/null
  send "$APP_SOCK" pasteboard-clear >/dev/null
  expect_equal "$label: the pasteboard starts empty" "" "$(send "$APP_SOCK" pasteboard-types)"

  if ! capture_into_editor "$trigger"; then return; fi
  expect_contains "$label: the Capture opens in the Editor at its native pixel size" "pixels=${w}x${h}" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  expect_equal "$label: nothing is on the pasteboard until the user copies" "" "$(send "$APP_SOCK" pasteboard-types)"

  if copy_closes_editor; then pass "$label: ⌘C copies and the Editor closes (the helper quits)"; else fail "$label: the Editor helper is still running after ⌘C"; fi
  # macOS also advertises the TIFF it can convert a PNG to; PNG must come first.
  expect_equal "$label: the pasteboard holds the PNG" "public.png" "$(send "$APP_SOCK" pasteboard-types | head -1)"

  expect_contains "$label: the PNG is dumped" "ok " "$(send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/clip.png")"
  info="$("$INSPECT" info "$RUN_ROOT/clip.png")"
  expect_equal "$label: native pixel width" "$w" "$(png_field "$info" width)"
  expect_equal "$label: native pixel height" "$h" "$(png_field "$info" height)"
  expect_equal "$label: pHYs records $((72 * scale)) dpi (pixels per metre, unit metre)" "$phys,$phys,1" "$(png_field "$info" phys)"
  expect_equal "$label: the display's ICC profile is embedded byte for byte" "$sha" "$(png_field "$info" icc_sha256)"
  expect_equal "$label: the profile is $profile" "$profile" "$(png_field "$info" profile_name)"
  expect_equal "$label: no sRGB, gAMA or cHRM chunk competes with the profile" "0" \
    "$(png_field "$info" chunks | tr ',' '\n' | grep -cE '^(sRGB|gAMA|cHRM)$')"
  expect_equal "$label: every pixel matches the fixture, in the display's color space" \
    "mismatches=0" "$("$INSPECT" verify-fixture "$RUN_ROOT/clip.png" "$w" "$h" | grep '^mismatches=')"
  rm -f "$RUN_ROOT/clip.png"
}

# 2. The menu item and the Shortcut, at 1x (sRGB, 72 dpi) and 2x (Display P3, 144 dpi).
#    301 and 187 points: rows are not a multiple of the engine's row alignment.
capture_check "menu item at 1x" "menu-click capture.screen" 1 301 187 "sRGB IEC61966-2.1" "$SRGB_SHA" 2835
capture_check "Shortcut at 1x" "press-shortcut capture-screen" 1 301 187 "sRGB IEC61966-2.1" "$SRGB_SHA" 2835
capture_check "menu item at 2x" "menu-click capture.screen" 2 301 187 "Display P3" "$P3_SHA" 5669
capture_check "Shortcut at 2x" "press-shortcut capture-screen" 2 301 187 "Display P3" "$P3_SHA" 5669

expect_equal "an unknown Shortcut is refused" "error no shortcut nope" "$(send "$APP_SOCK" "press-shortcut nope")"
expect_equal "an unknown menu item is refused" "error no menu item nope" "$(send "$APP_SOCK" "menu-click nope")"

# 3. Memory returns to baseline after Captures.
#    A 5120 x 2880 pixel display (56 MB of pixels): a leak would be impossible to miss. Each
#    Capture opens an Editor in the helper and ⌘C closes it, so the helper quits every time.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
capture_into_editor "press-shortcut capture-screen" && copy_closes_editor   # warm up allocator pools
sleep 1
BASELINE="$(footprint_mb "$APP_PID")"
for _ in 1 2 3 4 5; do
  capture_into_editor "menu-click capture.screen" && copy_closes_editor
  capture_into_editor "press-shortcut capture-screen" && copy_closes_editor
done
expect_memory_returns "memory returns to baseline after ten 5K Captures" "$APP_PID" "$BASELINE" "$(pixels_mb 5120 2880)"
expect_memory_returns "memory is back near the at-rest footprint after the Captures" "$APP_PID" "$AT_REST" "$(pixels_mb 5120 2880)"
send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/big.png" >/dev/null
BIG_INFO="$("$INSPECT" info "$RUN_ROOT/big.png")"
expect_equal "the 5K Capture's PNG has the full pixel size" "5120x2880" "$(png_field "$BIG_INFO" width)x$(png_field "$BIG_INFO" height)"
rm -f "$RUN_ROOT/big.png"
if [[ -z "$(helper_pid)" ]]; then pass "no helper process is left after the Editors closed"; else fail "an Editor helper is still running"; fi
send "$APP_SOCK" pasteboard-clear >/dev/null
