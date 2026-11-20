# Flow: Screen Capture to the clipboard. Drives the menu item and the Shortcut against fixture
# images at 1x and 2x, then reads the PNG back off the private pasteboard and checks its
# pixels and metadata with an independent decoder (png-inspect). Sourced by scripts/check-run.sh.
#
# To add a flow, copy this file's shape: switch the fixture, drive the app through a command
# (`menu-click`, `press-shortcut`, or one of your own), then assert on what is observable.
# shellcheck shell=bash

# 1. Every edge is the test one before anything is driven.
SEAMS="$(send "$APP_SOCK" test-seams)"
expect_contains "test mode: the root is this run's temporary folder" "root=$RUN_ROOT" "$SEAMS"
expect_contains "test mode: the pasteboard is private and named after the run" "pasteboard=dev.snapit.test.$(basename "$RUN_ROOT")" "$SEAMS"
expect_contains "test mode: Save location is inside the root" "save=$RUN_ROOT/save" "$SEAMS"
expect_contains "test mode: the cache folder is the root" "cache=$RUN_ROOT" "$SEAMS"
expect_contains "test mode: defaults live inside the root" "defaults=$RUN_ROOT/defaults.plist" "$SEAMS"
expect_contains "test mode: Screen Recording reports granted" "permission=granted" "$SEAMS"
expect_equal "test mode: the Capture source is the fixture" "fixture" "$(send "$APP_SOCK" capture-source)"
expect_equal "test mode: Shortcuts are injected, no hot key is registered" "capture-screen" "$(send "$APP_SOCK" bound-shortcuts)"

SRGB_SHA="$("$INSPECT" profile-sha srgb)"
P3_SHA="$("$INSPECT" profile-sha displayP3)"

# capture_check <label> <trigger command> <scale> <points w> <points h> <profile name> <profile sha> <pHYs>
# Chooses the fixture display, triggers the Capture, and checks the PNG on the pasteboard.
capture_check() {
  local label="$1" trigger="$2" scale="$3" pw="$4" ph="$5" profile="$6" sha="$7" phys="$8"
  local w=$((pw * scale)) h=$((ph * scale)) info

  send "$APP_SOCK" "fixture-display $scale $pw $ph" >/dev/null
  send "$APP_SOCK" pasteboard-clear >/dev/null
  expect_equal "$label: the pasteboard starts empty" "" "$(send "$APP_SOCK" pasteboard-types)"

  expect_equal "$label: the Capture finishes" "ok" "$(send_slow "$APP_SOCK" "$trigger")"
  expect_equal "$label: the Capture ends with a PNG on the clipboard" "copied(width: $w, height: $h" "$(send "$APP_SOCK" capture-outcome | cut -d, -f1,2)"
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

# 3. Memory returns to baseline after Captures, and the app idles at 0% CPU afterwards.
#    A 5120 x 2880 pixel display (59 MB of pixels): a leak would be impossible to miss.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null   # warm up allocator pools
sleep 1
BASELINE="$(footprint_mb "$APP_PID")"
for _ in 1 2 3 4 5; do
  send_slow "$APP_SOCK" "menu-click capture.screen" >/dev/null
  send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
done
sleep 1
AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$AFTER" -v b="$BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory returns to baseline after ten 5K Captures (${BASELINE} MB before, ${AFTER} MB after)"
else
  fail "memory grew from ${BASELINE} MB to ${AFTER} MB over ten 5K Captures (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/big.png" >/dev/null
BIG_INFO="$("$INSPECT" info "$RUN_ROOT/big.png")"
expect_equal "the 5K Capture's PNG has the full pixel size" "5120x2880" "$(png_field "$BIG_INFO" width)x$(png_field "$BIG_INFO" height)"
rm -f "$RUN_ROOT/big.png"
assert_idle_cpu "menu bar app after the Captures" "$APP_PID" 5
send "$APP_SOCK" pasteboard-clear >/dev/null
