# Flow: the Highlighter. A translucent stroke: the Export's pixels under it are the Capture's, 40%
# toward the Annotation color, computed here from the fixture formula and not read from the app. It
# has its own width presets, remembered apart from the line width, and Select picks it by its stroke.
# Sourced by scripts/check-run.sh.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
send "$APP_SOCK" "defaults-set highlighterWidth 22" >/dev/null

send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  W=301
  H=187
  keystroke h >/dev/null
  expect_equal "the H key picks the Highlighter" "highlighter" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N" | sed -n 's/^tool=//p')"
  drag 40 30 120 30 >/dev/null  # 22 points thick, square ends: pixels x 40..120, y 19..41
  EXPORT="$(export_png highlight)"
  DIFF="$(fixture_diff "$EXPORT" $W $H 40 19 120 41)"
  expect_equal "the stroke covers its length and thickness, with square ends" "bbox=40,19,120,41" "$(printf '%s\n' "$DIFF" | grep '^bbox=')"
  expect_equal "nothing outside it changed" "outside=0" "$(printf '%s\n' "$DIFF" | grep '^outside=')"
  for point in "80 30" "45 20" "115 40"; do
    read -r X Y <<<"$point"
    expect_within "the pixel at $X,$Y is the Capture's, 40% toward the Annotation color" 2 \
      "$(blend "$(fixture_pixel "$X" "$Y" $W $H)" "255,59,48" 40)" "$(pixel "$EXPORT" "$X" "$Y")"
  done
  # A second stroke over the first blends again: the overlap is darker than either.
  drag 80 10 80 60 >/dev/null  # vertical, crossing the first at x 69..91
  EXPORT="$(export_png highlight-overlap)"
  ONCE="$(blend "$(fixture_pixel 80 15 $W $H)" "255,59,48" 40)"
  TWICE="$(blend "$(blend "$(fixture_pixel 80 30 $W $H)" "255,59,48" 40)" "255,59,48" 40)"
  expect_within "where two strokes cross, the Capture is blended twice" 2 "$TWICE" "$(pixel "$EXPORT" 80 30)"
  expect_within "where only the second is, once" 2 "$ONCE" "$(pixel "$EXPORT" 80 15)"
  PARITY="$("$INSPECT" compare "$EXPORT" "$(preview_png)")"
  expect_equal "the canvas's own rendering of the strokes is the Export" "over_8=0" "$(printf '%s\n' "$PARITY" | grep '^over_8=')"

  # Select picks it by its stroke.
  keystroke v >/dev/null
  click 100 120 >/dev/null
  expect_nothing_selected "a click beside the strokes selects nothing"
  click 100 30 >/dev/null
  expect_selected "a click on the stroke selects it"
  keystroke undo >/dev/null
  keystroke undo >/dev/null
  expect_unchanged "two Undos take both strokes back" "$(export_png highlight-undone)" $W $H
  keystroke redo >/dev/null
  keystroke redo >/dev/null

  # The Highlighter's width has its own presets and is remembered apart from the line width.
  keystroke h >/dev/null
  expect_contains "the Highlighter's presets are thick: 34 points" "ok" "$(send "$EDITOR_SOCK" "editor-click $EDITOR_N control Width:%2034%20pt")"
  expect_equal "the Highlighter's thickness is remembered" "34" "$(send "$APP_SOCK" "defaults-get highlighterWidth")"
  expect_equal "and the line width is not" "5" "$(send "$APP_SOCK" "defaults-get annotationWidth")"
  drag 20 150 100 150 >/dev/null  # 34 points thick: y 133..167
  EXPORT="$(export_png highlight-thick)"
  expect_within "the next stroke is 34 points thick: its top row is blended" 2 \
    "$(blend "$(fixture_pixel 60 133 $W $H)" "255,59,48" 40)" "$(pixel "$EXPORT" 60 133)"
  expect_within "and its bottom row" 2 "$(blend "$(fixture_pixel 60 166 $W $H)" "255,59,48" 40)" "$(pixel "$EXPORT" 60 166)"
  expect_equal "the row above it is the Capture" "$(fixture_pixel 60 132 $W $H)" "$(pixel "$EXPORT" 60 132)"
  expect_equal "the row below it is the Capture" "$(fixture_pixel 60 167 $W $H)" "$(pixel "$EXPORT" 60 167)"
  keystroke a >/dev/null
  expect_contains "an Arrow's presets are the thin ones" "ok" "$(send "$EDITOR_SOCK" "editor-click $EDITOR_N control Width:%208%20pt")"
  expect_equal "choosing an Arrow's width leaves the Highlighter's alone" "34" "$(send "$APP_SOCK" "defaults-get highlighterWidth")"
  expect_equal "and sets the line width" "8" "$(send "$APP_SOCK" "defaults-get annotationWidth")"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
send "$APP_SOCK" "defaults-set highlighterWidth 22" >/dev/null
