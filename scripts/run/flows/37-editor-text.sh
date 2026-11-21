# Flow: the Text tool. Text is drawn with Core Text into the Export; a click away commits a text and
# starts no new one; typing never changes the tool or deletes the Annotation; ⌘Z takes back typing
# first and then the Annotations. Every check reads what a user could see: the Export's pixels (Copy
# puts the flattened Capture on the private pasteboard, read back with the independent decoder in
# png-inspect), the canvas's own rendering and which toolbar items are enabled. Sourced by
# scripts/check-run.sh, after flow 36.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
send "$APP_SOCK" "defaults-set annotationTextSize 32" >/dev/null

# text_count: how many Texts the open Editor has.
text_count() { send "$EDITOR_SOCK" "editor-text $EDITOR_N" | grep -c '^text '; }
# text_field <id> <field>: one field of a Text's line in `editor-text`: size x y width height text.
text_line() { send "$EDITOR_SOCK" "editor-text $EDITOR_N" | grep "^text $1 "; }
editing() { send "$EDITOR_SOCK" "editor-text $EDITOR_N" | sed -n 's/^editing=//p'; }
type_text() { send "$EDITOR_SOCK" "editor-type $EDITOR_N $1"; }

# 1x: the Capture's pixels are its points, and the sRGB color is exact.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  W=301
  H=187
  TOOLBAR="$(send "$EDITOR_SOCK" "editor-toolbar $EDITOR_N")"
  expect_in_order "Text and Highlighter are on the left toolbar after Oval" \
    "$(printf '%s\n' "$TOOLBAR" | grep '^tool ' | cut -d' ' -f2)" select arrow rectangle oval text highlighter
  expect_contains "Text has its tooltip and key" "tool text 500 Text (T)" "$TOOLBAR"
  expect_contains "Highlighter has its tooltip and key" "tool highlighter 600 Highlighter (H)" "$TOOLBAR"

  # A Text: click where it starts, type, click away.
  keystroke t >/dev/null
  expect_equal "the T key picks the Text tool" "text" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N" | sed -n 's/^tool=//p')"
  click 30 40 >/dev/null
  expect_equal "a click with the Text tool starts typing" "yes" "$(editing)"
  expect_equal "typing replies ok" "ok" "$(type_text T)"
  click 200 120 >/dev/null
  expect_equal "a click away commits the text" "no" "$(editing)"
  expect_equal "the committed text is one Annotation" "1" "$(text_count)"
  expect_equal "and the click away did not start a new text box" "1" "$(text_count)"
  expect_equal "the committed text says what was typed" "T" "$(text_line 1 | cut -d' ' -f8)"
  expect_enabled "Undo is enabled after a text is committed" undo
  TEXT_LINE="$(text_line 1)"
  read -r _ _ SIZE BX BY BW BH _ <<<"$TEXT_LINE"
  expect_equal "the text has the remembered size" "32" "$SIZE"
  EXPORT="$(export_png text-t)"
  X0="$(awk -v x="$BX" 'BEGIN { printf "%d", x - 1 }')"
  Y0="$(awk -v y="$BY" 'BEGIN { printf "%d", y - 1 }')"
  X1="$(awk -v x="$BX" -v w="$BW" 'BEGIN { printf "%d", x + w + 1 }')"
  Y1="$(awk -v y="$BY" -v h="$BH" 'BEGIN { printf "%d", y + h + 1 }')"
  TEXT_DIFF="$(fixture_diff "$EXPORT" $W $H "$X0" "$Y0" "$X1" "$Y1")"
  expect_equal "the Export has no pixel changed outside the text's box" "outside=0" "$(printf '%s\n' "$TEXT_DIFF" | grep '^outside=')"
  CHANGED="$(png_field "$TEXT_DIFF" changed)"
  if ((CHANGED > 40)); then pass "Core Text drew the glyph into the Export ($CHANGED pixels changed)"; else fail "the text drew only $CHANGED pixels"; fi
  IFS=, read -r GX0 GY0 GX1 GY1 <<<"$(png_field "$TEXT_DIFF" bbox)"
  if awk -v gx="$GX0" -v bx="$BX" 'BEGIN { exit !(gx >= bx - 1 && gx <= bx + 8) }'; then pass "the glyph starts at the text's left edge (x $GX0, box $BX)"; else fail "the glyph starts at x $GX0, the box at $BX"; fi
  # An upright T has its bar on top: the top quarter of its rows has far more ink than the bottom quarter.
  QUARTER=$(((GY1 - GY0) / 4))
  TOP_INK="$(png_field "$(fixture_diff "$EXPORT" $W $H "$GX0" "$GY0" "$GX1" $((GY0 + QUARTER)))" inside)"
  BOTTOM_INK="$(png_field "$(fixture_diff "$EXPORT" $W $H "$GX0" $((GY1 - QUARTER)) "$GX1" "$GY1")" inside)"
  if ((TOP_INK > BOTTOM_INK * 2)); then pass "the text is upright: its bar is on top ($TOP_INK pixels above, $BOTTOM_INK below)"; else fail "the T is flipped or mirrored ($TOP_INK pixels in its top quarter, $BOTTOM_INK in its bottom)"; fi
  # The baseline (a T's bottom) lies in the lower part of the box: ascent is most of a line.
  if awk -v gy="$GY1" -v by="$BY" -v bh="$BH" 'BEGIN { f = (gy - by) / bh; exit !(f >= 0.65 && f <= 0.9) }'; then pass "the baseline is where the text's box puts it"; else fail "the glyph ends at y $GY1 in a box from $BY, $BH high"; fi
  STEM_X=$(((GX0 + GX1) / 2))
  STEM_Y=$((GY1 - 3))
  expect_red "the glyph is drawn in the Annotation color" "$(pixel "$EXPORT" "$STEM_X" "$STEM_Y")"
  expect_equal "away from the text the Capture is untouched" "$(fixture_pixel 250 150 $W $H)" "$(pixel "$EXPORT" 250 150)"

  # The canvas shows the same text as the Export.
  PARITY="$("$INSPECT" compare "$EXPORT" "$(preview_png)")"
  expect_equal "the canvas's own rendering of the text is the Export, to within anti-aliasing" "over_8=0" "$(printf '%s\n' "$PARITY" | grep '^over_8=')"

  # Typing is typing: a tool's key is a letter and ⌫ deletes a character, never the Annotation.
  keystroke t >/dev/null
  click 150 120 >/dev/null
  type_text var >/dev/null
  expect_equal "typing v, a and r does not change the tool" "text" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N" | sed -n 's/^tool=//p')"
  expect_equal "and the text is still being typed" "yes" "$(editing)"
  keystroke delete >/dev/null
  expect_equal "⌫ while typing deletes a character and not the Annotation" "yes" "$(editing)"
  click 270 20 >/dev/null
  SECOND_ID="$(send "$EDITOR_SOCK" "editor-text $EDITOR_N" | grep '^text ' | tail -1 | cut -d' ' -f2)"
  expect_equal "the typed letters are the text, less the deleted one" "va" "$(text_line "$SECOND_ID" | cut -d' ' -f8)"
  expect_equal "the earlier text was not deleted" "2" "$(text_count)"

  # ⌘Z takes typing back first, then the Annotations.
  keystroke t >/dev/null
  click 20 150 >/dev/null
  type_text Q >/dev/null
  expect_enabled "Undo is enabled while typing" undo
  keystroke undo >/dev/null
  expect_equal "the first ⌘Z undoes the typing, and the text is still open" "yes" "$(editing)"
  expect_equal "and nothing was undone yet" "2" "$(text_count)"
  keystroke undo >/dev/null
  expect_equal "the next ⌘Z, with no typing left, closes the empty text and undoes the last Annotation" "1" "$(text_count)"
  expect_equal "the text before it is still there" "T" "$(text_line 1 | cut -d' ' -f8)"
  keystroke redo >/dev/null
  expect_equal "⇧⌘Z brings it back" "2" "$(text_count)"

  # A double click on a Text with Select edits it: one Undo step for the whole edit.
  keystroke v >/dev/null
  expect_equal "the double click replies ok" "ok" "$(send "$EDITOR_SOCK" "editor-double-click $EDITOR_N 35 55")"
  expect_equal "a double click on a Text edits it" "yes" "$(editing)"
  type_text X >/dev/null
  click 280 170 >/dev/null
  expect_equal "the edited text is committed" "TX" "$(text_line 1 | cut -d' ' -f8)"
  expect_equal "and no text was added" "2" "$(text_count)"
  keystroke undo >/dev/null
  expect_equal "one Undo takes the whole edit back" "T" "$(text_line 1 | cut -d' ' -f8)"
  keystroke redo >/dev/null
  # Emptying a Text removes it.
  send "$EDITOR_SOCK" "editor-double-click $EDITOR_N 160 130" >/dev/null
  keystroke delete >/dev/null
  keystroke delete >/dev/null
  keystroke delete >/dev/null
  click 280 170 >/dev/null
  expect_equal "a Text edited down to nothing is removed" "1" "$(text_count)"
  keystroke undo >/dev/null

  # Esc commits the typing and leaves the Editor open.
  keystroke t >/dev/null
  click 150 20 >/dev/null
  type_text E >/dev/null
  COUNT_BEFORE="$(text_count)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  expect_equal "Esc while typing commits the text" "no" "$(editing)"
  expect_equal "and the text is an Annotation" "$((COUNT_BEFORE + 1))" "$(text_count)"
  expect_contains "and the Editor is still open" "$EDITOR_N" "$(open_editors)"

  # Copy while typing includes the text.
  click 200 150 >/dev/null
  type_text C >/dev/null
  EXPORT="$(export_png copy-typing)"
  expect_equal "Copy commits the text being typed" "no" "$(editing)"
  if (($(png_field "$(fixture_diff "$EXPORT" $W $H 198 148 260 200)" inside) > 20)); then pass "and the Export has that text"; else fail "the Export has no text where it was typed"; fi

  # ⌘A, ⌘X, ⌘C and ⌘V are the text's own while typing: ⌘C must not Export the Capture.
  send "$APP_SOCK" pasteboard-clear >/dev/null
  click 20 60 >/dev/null
  type_text Hi >/dev/null
  send "$EDITOR_SOCK" "editor-key-command $EDITOR_N a" >/dev/null
  send "$EDITOR_SOCK" "editor-key-command $EDITOR_N c" >/dev/null
  expect_equal "⌘C while typing leaves the text open" "yes" "$(editing)"
  expect_contains "and the Editor open" "$EDITOR_N" "$(open_editors)"
  expect_equal "the private pasteboard holds the selected text" "Hi" "$(send "$EDITOR_SOCK" editor-pasteboard-string | cut -d' ' -f1)"
  expect_equal "and no Export of the Capture" "no" "$(send "$EDITOR_SOCK" editor-pasteboard-string | grep -q 'public.png' && echo yes || echo no)"
  type_text x >/dev/null  # replaces the selection
  send "$EDITOR_SOCK" "editor-key-command $EDITOR_N v" >/dev/null
  click 280 170 >/dev/null
  LAST_ID="$(send "$EDITOR_SOCK" "editor-text $EDITOR_N" | grep '^text ' | tail -1 | cut -d' ' -f2)"
  expect_equal "⌘V pastes the copied text after the typed one" "xHi" "$(text_line "$LAST_ID" | cut -d' ' -f8)"
  click 20 60 >/dev/null  # Text tool: edits that Text
  send "$EDITOR_SOCK" "editor-key-command $EDITOR_N a" >/dev/null
  send "$EDITOR_SOCK" "editor-key-command $EDITOR_N x" >/dev/null
  expect_equal "⌘X cuts the selected text to the pasteboard" "xHi" "$(send "$EDITOR_SOCK" editor-pasteboard-string | cut -d' ' -f1)"
  click 280 170 >/dev/null
  expect_equal "and the Text, cut down to nothing, is gone" "$((COUNT_BEFORE + 2))" "$(text_count)"

  # A color and a size chosen while typing apply to that text.
  click 20 100 >/dev/null
  type_text S >/dev/null
  send "$EDITOR_SOCK" "editor-click $EDITOR_N control Blue" >/dev/null
  send "$EDITOR_SOCK" "editor-click $EDITOR_N control Text%20size:%2014%20pt" >/dev/null
  click 280 170 >/dev/null
  LAST_ID="$(send "$EDITOR_SOCK" "editor-text $EDITOR_N" | grep '^text ' | tail -1 | cut -d' ' -f2)"
  expect_equal "a size chosen while typing is the text's size" "14" "$(text_line "$LAST_ID" | cut -d' ' -f3)"
  expect_contains "a swatch clicked while typing colors the text" "annotation $LAST_ID text" "$(send "$EDITOR_SOCK" "editor-document $EDITOR_N")"
  expect_contains "in that color" "0a84ff" "$(send "$EDITOR_SOCK" "editor-document $EDITOR_N" | grep "^annotation $LAST_ID ")"

  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationTextSize 32" >/dev/null

# The toolbar's Undo and Redo buttons follow the typing: in an Editor with no Annotation yet they are
# greyed out until something is typed (read from the window's controls, as a user sees them).
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  control_enabled() { send "$EDITOR_SOCK" "editor-control-enabled $EDITOR_N ${1// /%20}"; }
  undo_is() { [[ "$(control_enabled 'Undo (⌘Z)')" == "$1" ]]; }
  redo_is() { [[ "$(control_enabled 'Redo (⇧⌘Z)')" == "$1" ]]; }
  keystroke t >/dev/null
  click 30 40 >/dev/null
  expect_equal "Undo is greyed out with nothing typed and nothing drawn" "no" "$(control_enabled 'Undo (⌘Z)')"
  type_text a >/dev/null
  if wait_until 3 undo_is yes; then pass "Undo lights up as soon as something is typed"; else fail "the Undo button did not follow the typing"; fi
  keystroke undo >/dev/null
  if wait_until 3 undo_is no; then pass "Undo goes grey when the typing is taken back"; else fail "the Undo button stayed enabled after the typing was undone"; fi
  if wait_until 3 redo_is yes; then pass "and Redo lights up"; else fail "the Redo button did not follow the typing"; fi
  keystroke redo >/dev/null
  type_text b >/dev/null
  click 280 170 >/dev/null
  expect_equal "the typing put back and extended is the text" "ab" "$(text_line 1 | cut -d' ' -f8)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi

# A Capture bigger than the window is shown scaled down: the text lies where it was typed, and the
# canvas's rendering is still the Export.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  W=5120
  H=2880
  ZOOM="$(document_field zoom)"
  if awk -v z="$ZOOM" 'BEGIN { exit !(z > 0 && z < 1) }'; then pass "the 2560 x 1440 point Capture is scaled to fit for the text check (zoom $ZOOM)"; else fail "the Capture is not scaled down (zoom $ZOOM)"; fi
  LAYOUT="$(send "$EDITOR_SOCK" "editor-layout $EDITOR_N")"
  expect_equal "no two controls overlap in a wide window" "overlapping-controls=0" "$(printf '%s\n' "$LAYOUT" | grep '^overlapping-controls=')"
  keystroke t >/dev/null
  click 200 100 >/dev/null
  type_text T >/dev/null
  click 800 600 >/dev/null
  read -r _ _ _ BX BY BW BH _ <<<"$(text_line 1)"
  EXPORT="$(export_png text-zoomed)"
  X0="$(awk -v x="$BX" 'BEGIN { printf "%d", x * 2 - 2 }')"
  Y0="$(awk -v y="$BY" 'BEGIN { printf "%d", y * 2 - 2 }')"
  X1="$(awk -v x="$BX" -v w="$BW" 'BEGIN { printf "%d", (x + w) * 2 + 2 }')"
  Y1="$(awk -v y="$BY" -v h="$BH" 'BEGIN { printf "%d", (y + h) * 2 + 2 }')"
  TEXT_DIFF="$(fixture_diff "$EXPORT" $W $H "$X0" "$Y0" "$X1" "$Y1")"
  expect_equal "on a scaled-down Capture the text is where it was clicked: nothing changed outside its box" "outside=0" "$(printf '%s\n' "$TEXT_DIFF" | grep '^outside=')"
  IFS=, read -r GX0 GY0 GX1 GY1 <<<"$(png_field "$TEXT_DIFF" bbox)"
  if awk -v gx="$GX0" -v bx="$BX" -v gy="$GY0" -v by="$BY" 'BEGIN { exit !(gx >= bx * 2 - 2 && gx <= bx * 2 + 16 && gy >= by * 2 - 2 && gy <= by * 2 + 24) }'; then pass "the glyph starts at the text's top left, in pixels ($GX0,$GY0 for a box at $BX,$BY points)"; else fail "the glyph starts at $GX0,$GY0, the box at $BX,$BY points"; fi
  PARITY="$("$INSPECT" compare "$EXPORT" "$(preview_png)")"
  expect_equal "on a scaled-down Capture the canvas's own rendering of the text is the Export" "over_8=0" "$(printf '%s\n' "$PARITY" | grep '^over_8=')"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi

# The helper's memory stays flat over many commits and edits of Texts in one open Editor.
send "$APP_SOCK" "fixture-display 1 1200 700" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  for _ in 1 2 3; do  # warm up: layers, fonts and the text system settle
    keystroke t >/dev/null
    click 100 100 >/dev/null; type_text Warm >/dev/null; click 800 500 >/dev/null
    keystroke undo >/dev/null
  done
  sleep 1
  HELPER_BASELINE="$(footprint_mb "$HELPER_PID")"
  for _ in $(seq 1 20); do
    keystroke t >/dev/null
    click 100 100 >/dev/null
    type_text Hello%0Aworld >/dev/null
    click 800 500 >/dev/null  # commit
    keystroke v >/dev/null
    send "$EDITOR_SOCK" "editor-double-click $EDITOR_N 110 110" >/dev/null  # edit it
    type_text x >/dev/null
    click 800 500 >/dev/null
    keystroke undo >/dev/null
    keystroke undo >/dev/null
  done
  expect_memory_returns "the Editor helper's memory over 20 Text commit and edit cycles" "$HELPER_PID" "$HELPER_BASELINE"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi

# 2x: a Display P3 Capture with twice as many pixels as points.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  W=602
  H=374
  keystroke t >/dev/null
  click 30 40 >/dev/null
  type_text T >/dev/null
  click 200 150 >/dev/null
  read -r _ _ _ BX BY BW BH _ <<<"$(text_line 1)"
  EXPORT="$(export_png text-2x)"
  X0="$(awk -v x="$BX" 'BEGIN { printf "%d", x * 2 - 2 }')"
  Y0="$(awk -v y="$BY" 'BEGIN { printf "%d", y * 2 - 2 }')"
  X1="$(awk -v x="$BX" -v w="$BW" 'BEGIN { printf "%d", (x + w) * 2 + 2 }')"
  Y1="$(awk -v y="$BY" -v h="$BH" 'BEGIN { printf "%d", (y + h) * 2 + 2 }')"
  TEXT_DIFF="$(fixture_diff "$EXPORT" $W $H "$X0" "$Y0" "$X1" "$Y1")"
  expect_equal "at 2x the text stays within its box, in pixels" "outside=0" "$(printf '%s\n' "$TEXT_DIFF" | grep '^outside=')"
  IFS=, read -r GX0 GY0 GX1 GY1 <<<"$(png_field "$TEXT_DIFF" bbox)"
  if (((GX1 - GX0) >= 14 && (GY1 - GY0) >= 30)); then pass "at 2x the glyph has twice the pixels ($((GX1 - GX0)) x $((GY1 - GY0)))"; else fail "the 2x glyph is only $((GX1 - GX0)) x $((GY1 - GY0)) pixels"; fi
  expect_red "at 2x the glyph is in the Annotation color" "$(pixel "$EXPORT" $(((GX0 + GX1) / 2)) $((GY1 - 6)))"
  PARITY="$("$INSPECT" compare "$EXPORT" "$(preview_png)")"
  expect_equal "at 2x the canvas's own rendering of the text is the Export" "over_8=0" "$(printf '%s\n' "$PARITY" | grep '^over_8=')"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationTextSize 20" >/dev/null

# Memory: Capture, type, highlight, recolor, Copy, close. The menu bar app stays flat and no helper is left.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null
TEXT_BASELINE="$(footprint_mb "$APP_PID")"
for _ in 1 2 3; do
  if capture_into_editor "menu-click capture.screen"; then
    keystroke t >/dev/null
    click 100 100 >/dev/null
    type_text Hello%0Aworld >/dev/null
    click 800 600 >/dev/null
    keystroke h >/dev/null
    drag 100 300 900 300 >/dev/null
    send "$EDITOR_SOCK" "editor-click $EDITOR_N control Blue" >/dev/null
    copy_closes_editor
  fi
done
expect_memory_returns "the menu bar app's memory is flat over Capture, Text, Highlighter, Copy cycles" "$APP_PID" "$TEXT_BASELINE"
if [[ -z "$(helper_pid)" ]]; then pass "no helper process is left after the Text cycles"; else fail "a helper is still running after the Text cycles"; fi
expect_equal "no Editor is left open by the Text flow" "" "$(open_editors)"
send "$APP_SOCK" pasteboard-clear >/dev/null
