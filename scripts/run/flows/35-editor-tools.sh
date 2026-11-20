# Flow: the Editor's tools. Select, Arrow, Rectangle and Oval draw, pick, move and resize
# Annotations with synthetic pointer input on the canvas; ⌘Z, ⇧⌘Z and ⌫ work from the keyboard;
# every check reads the Export's pixels (Copy puts the flattened Capture on the private
# pasteboard) with the independent decoder in png-inspect. The fixture at scale 2 is a
# 301 x 187 point Capture of 602 x 374 pixels in Display P3, so an Annotation in image points
# lands on twice the pixels, and a flipped or shifted transform shows up as pixels changed in the
# wrong place. Sourced by scripts/check-run.sh, after flow 30.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
W=602
H=374

if capture_into_editor "menu-click capture.screen"; then
  TOOLBAR="$(send "$EDITOR_SOCK" "editor-toolbar $EDITOR_N")"
  expect_in_order "the tools are on the left toolbar in order" \
    "$(printf '%s\n' "$TOOLBAR" | grep '^tool ' | cut -d' ' -f2)" select arrow rectangle oval
  expect_contains "Arrow has its tooltip and key" "tool arrow 200 Arrow (A)" "$TOOLBAR"
  expect_contains "Rectangle has its tooltip and key" "tool rectangle 300 Rectangle (R)" "$TOOLBAR"
  expect_contains "Oval has its tooltip and key" "tool oval 400 Oval (O)" "$TOOLBAR"
  expect_contains "Undo has its tooltip" "item undo history Undo (⌘Z)" "$TOOLBAR"
  expect_contains "Redo has its tooltip" "item redo history Redo (⇧⌘Z)" "$TOOLBAR"
  expect_contains "Delete Annotation has its tooltip" "item delete-annotation history Delete Annotation (⌫)" "$TOOLBAR"
  expect_contains "the outline and solid fill control is in the options pill" "item annotation-fill options" "$TOOLBAR"
  NO_TOOLTIP="$(printf '%s\n' "$TOOLBAR" | awk 'NF < 4' | wc -l | tr -d ' ')"
  expect_equal "every tool and toolbar item still has a tooltip" "0" "$NO_TOOLTIP"
  MENUS="$(send "$EDITOR_SOCK" main-menu)"
  expect_in_order "the Edit menu lists Undo, Redo, Delete Annotation and Copy" "$(menu_items "$MENUS" Edit)" "Undo" "Redo" "Delete Annotation" "Copy"
  MENU_KEYS="$(send "$EDITOR_SOCK" editor-menu-keys)"
  expect_contains "the Edit menu shows ⌘Z for Undo" "Undo key=7a modifiers=1048576" "$MENU_KEYS"
  expect_contains "the Edit menu shows ⇧⌘Z for Redo" "Redo key=7a modifiers=1179648" "$MENU_KEYS"
  expect_contains "the Edit menu shows ⌫ for Delete Annotation" "Delete Annotation key=8 modifiers=0" "$MENU_KEYS"

  # Every control accepts the first click on a background Editor, except Delete Capture's host.
  FIRST_CLICK="$(send "$EDITOR_SOCK" "editor-first-click $EDITOR_N")"
  expect_equal "exactly one control host refuses the first click" "1" "$(printf '%s\n' "$FIRST_CLICK" | grep -c ' no$')"
  expect_contains "the host that refuses it is Delete Capture's" "NoFirstMouseHost" "$(printf '%s\n' "$FIRST_CLICK" | grep ' no$')"
  if (($(printf '%s\n' "$FIRST_CLICK" | grep -c ' yes$') >= 4)); then pass "the canvas, the tool rail and the toolbar pills accept the first click"; else fail "too few controls accept the first click: $FIRST_CLICK"; fi

  # Nothing to undo, redo or delete in a fresh Editor.
  expect_contains "Undo is disabled with nothing to undo" "error toolbar item is disabled" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N undo")"
  expect_contains "Delete Annotation is disabled with no selection" "error toolbar item is disabled" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N delete-annotation")"

  # 1. A solid Rectangle, dragged from (40,30) to (120,90) points: pixels (80,60) to (240,180).
  keystroke r >/dev/null
  expect_equal "the R key picks Rectangle" "rectangle" "$(document_field tool)"
  style fill solid >/dev/null
  expect_equal "the Rectangle drag replies ok" "ok" "$(drag 40 30 120 90)"
  expect_equal "one Rectangle was made" "1" "$(annotation_count)"
  expect_selected "the new Annotation is selected"
  expect_equal "one drag is one Undo step" "1" "$(document_field undo-steps)"
  EXPORT="$(export_png rect)"
  RECT_DIFF="$(fixture_diff "$EXPORT" $W $H 80 60 240 180)"
  expect_equal "the solid Rectangle covers exactly its pixels" "bbox=80,60,240,180" "$(printf '%s\n' "$RECT_DIFF" | grep '^bbox=')"
  expect_equal "no pixel outside the Rectangle changed (the mirrored position is still the Capture)" "outside=0" "$(printf '%s\n' "$RECT_DIFF" | grep '^outside=')"
  expect_equal "every pixel inside the solid Rectangle changed" "changed=19200" "$(printf '%s\n' "$RECT_DIFF" | grep '^changed=')"
  expect_red "the Rectangle is drawn in the Annotation color" "$(pixel "$EXPORT" 160 120)"
  EXPORT_INFO="$("$INSPECT" info "$EXPORT")"
  expect_equal "the annotated Export keeps the display's ICC profile byte for byte" "$P3_SHA" "$(png_field "$EXPORT_INFO" icc_sha256)"
  expect_equal "the annotated Export is the Capture's pixel size" "602" "$(png_field "$EXPORT_INFO" width)"
  expect_contains "the Capture's own mapping stays read-only" "capture-mapping=read-only" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"

  # 2. Undo and Redo.
  expect_equal "⌘Z replies ok" "ok" "$(keystroke undo)"
  expect_equal "Undo removes the Rectangle" "0" "$(annotation_count)"
  expect_equal "after Undo the Export is the untouched Capture" "mismatches=0" "$("$INSPECT" verify-fixture "$(export_png undone)" $W $H | grep '^mismatches=')"
  expect_equal "⇧⌘Z replies ok" "ok" "$(keystroke redo)"
  expect_equal "Redo brings the Rectangle back" "1" "$(annotation_count)"
  expect_equal "after Redo the Export has the Rectangle again" "bbox=80,60,240,180" "$(fixture_diff "$(export_png redone)" $W $H | grep '^bbox=')"

  # 3. Select: move, resize, fill and delete, each one Undo step.
  keystroke v >/dev/null
  expect_equal "the V key picks Select" "select" "$(document_field tool)"
  drag 80 60 130 100 >/dev/null  # from inside the Rectangle: moves it by (+50, +40) points
  expect_equal "moving is one more Undo step" "2" "$(document_field undo-steps)"
  expect_equal "the moved Rectangle is at its new pixels" "bbox=180,140,340,260" "$(fixture_diff "$(export_png moved)" $W $H | grep '^bbox=')"
  keystroke undo >/dev/null
  expect_equal "Undo puts the Rectangle back where it was" "bbox=80,60,240,180" "$(fixture_diff "$(export_png unmoved)" $W $H | grep '^bbox=')"
  keystroke redo >/dev/null
  drag 170 130 200 150 >/dev/null  # the bottom right handle of the moved box (90,70)-(170,130)
  expect_equal "resizing is an Undo step too" "3" "$(document_field undo-steps)"
  expect_equal "the resized Rectangle spans its new corner" "bbox=180,140,400,300" "$(fixture_diff "$(export_png resized)" $W $H | grep '^bbox=')"
  keystroke undo >/dev/null
  expect_equal "Undo puts the old size back" "bbox=180,140,340,260" "$(fixture_diff "$(export_png unresized)" $W $H | grep '^bbox=')"
  keystroke redo >/dev/null

  send "$EDITOR_SOCK" "editor-press $EDITOR_N annotation-fill" >/dev/null  # solid to outline: one Undo step
  EXPORT="$(export_png outline)"
  OUTLINE_DIFF="$(fixture_diff "$EXPORT" $W $H 190 150 390 290)"
  expect_equal "an outline Rectangle is 5 points of stroke around its edge" "bbox=175,135,405,305" "$(printf '%s\n' "$OUTLINE_DIFF" | grep '^bbox=')"
  expect_equal "the inside of an outline Rectangle is still the Capture" "inside=0" "$(printf '%s\n' "$OUTLINE_DIFF" | grep '^inside=')"
  keystroke undo >/dev/null
  expect_equal "Undo turns the fill back to solid" "changed=35200" "$(fixture_diff "$(export_png solid-again)" $W $H | grep '^changed=')"
  expect_equal "the fill change was one Undo step, taken back" "3" "$(document_field undo-steps)"

  expect_equal "⌫ replies ok" "ok" "$(keystroke delete)"
  expect_equal "⌫ deletes the selected Annotation" "0" "$(annotation_count)"
  expect_unchanged "after ⌫ the Export is the untouched Capture" "$(export_png deleted)" $W $H
  keystroke undo >/dev/null
  expect_equal "Undo takes the deletion back" "1" "$(annotation_count)"
  expect_equal "the restored Annotation is drawn again" "bbox=180,140,400,300" "$(fixture_diff "$(export_png undeleted)" $W $H | grep '^bbox=')"
  click 140 110 >/dev/null  # Undo does not bring the selection back: pick it again
  keystroke delete >/dev/null
  expect_equal "the restored Annotation can be deleted again" "0" "$(annotation_count)"

  # 4. Oval: a filled Oval is hit inside the ellipse only, not in the corners of its box.
  style fill solid >/dev/null
  keystroke o >/dev/null
  drag 150 20 250 100 >/dev/null  # box pixels (300,40) to (500,200)
  OVAL="$(export_png oval)"
  OVAL_DIFF="$(fixture_diff "$OVAL" $W $H 300 40 500 200)"
  expect_equal "the Oval stays inside its box" "outside=0" "$(printf '%s\n' "$OVAL_DIFF" | grep '^outside=')"
  expect_equal "the Oval reaches the edges of its box" "bbox=300,40,500,200" "$(printf '%s\n' "$OVAL_DIFF" | grep '^bbox=')"
  OVAL_CHANGED="$(png_field "$OVAL_DIFF" changed)"
  if ((OVAL_CHANGED > 24500 && OVAL_CHANGED < 25800)); then pass "the Oval fills an ellipse, about pi/4 of its box ($OVAL_CHANGED of 32000 pixels)"; else fail "the Oval changed $OVAL_CHANGED pixels, an ellipse in a 200 x 160 box is about 25133"; fi
  expect_equal "a corner of the Oval's box is still the Capture" "$(fixture_pixel 304 44 $W $H)" "$(pixel "$OVAL" 304 44)"
  keystroke v >/dev/null
  click 20 120 >/dev/null  # empty canvas: deselects, so no handle is near the corner
  click 151 21 >/dev/null
  expect_nothing_selected "a click in the corner of a filled Oval's box selects nothing"
  expect_contains "so Delete Annotation has nothing to delete" "error toolbar item is disabled" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N delete-annotation")"
  expect_equal "and the Oval is still in the Export" "bbox=300,40,500,200" "$(fixture_diff "$(export_png oval-kept)" $W $H | grep '^bbox=')"
  click 200 60 >/dev/null
  expect_selected "a click inside the Oval selects it"
  keystroke delete >/dev/null
  expect_equal "⌫ deletes it" "0" "$(annotation_count)"
  expect_unchanged "the Export is the Capture again" "$(export_png oval-gone)" $W $H

  # An outline Oval is hit on its line only.
  style fill outline >/dev/null
  keystroke o >/dev/null
  drag 150 20 250 100 >/dev/null
  OUTLINE_OVAL="$(export_png oval-outline)"
  expect_equal "the middle of an outline Oval is the Capture" "$(fixture_pixel 400 120 $W $H)" "$(pixel "$OUTLINE_OVAL" 400 120)"
  expect_equal "an outline Oval's line is on its box's edge" "bbox=295,35,505,205" "$(fixture_diff "$OUTLINE_OVAL" $W $H | grep '^bbox=')"
  keystroke v >/dev/null
  click 200 60 >/dev/null
  expect_nothing_selected "a click inside an outline Oval selects nothing"
  click 150 60 >/dev/null  # the leftmost point of its line
  expect_selected "a click on its line selects it"
  keystroke delete >/dev/null
  expect_equal "⌫ deletes the outline Oval" "0" "$(annotation_count)"

  # 5. Arrow: from (30,150) to (120,170) points, pixels (60,300) to (240,340).
  keystroke a >/dev/null
  drag 30 150 120 170 >/dev/null
  ARROW="$(export_png arrow)"
  ARROW_DIFF="$(fixture_diff "$ARROW" $W $H 50 290 250 365)"
  expect_equal "the Arrow stays within the box around its line and head" "outside=0" "$(printf '%s\n' "$ARROW_DIFF" | grep '^outside=')"
  if (($(png_field "$ARROW_DIFF" inside) > 1000)); then pass "the Arrow draws its shaft and head"; else fail "the Arrow changed too few pixels: $ARROW_DIFF"; fi
  expect_red "the Arrow's shaft is in the Annotation color" "$(pixel "$ARROW" 120 313)"
  expect_equal "away from the Arrow the Capture is untouched" "$(fixture_pixel 120 61 $W $H)" "$(pixel "$ARROW" 120 61)"
  keystroke v >/dev/null
  click 75 172 >/dev/null
  expect_nothing_selected "a click beside the Arrow's line selects nothing"
  click 75 160 >/dev/null
  expect_selected "a click on the Arrow's line selects it"
  STEPS_BEFORE="$(document_field undo-steps)"
  drag 30 150 20 140 >/dev/null  # the tail handle
  expect_equal "dragging the Arrow's tail handle is one Undo step" "$((STEPS_BEFORE + 1))" "$(document_field undo-steps)"
  expect_contains "the tail moved" "annotation 4 arrow 20.0 140.0 120.0 170.0" "$(send "$EDITOR_SOCK" "editor-document $EDITOR_N")"
  keystroke undo >/dev/null
  keystroke delete >/dev/null
  expect_equal "⌫ deletes the Arrow" "0" "$(annotation_count)"

  # 6. The color, width and fill used last are remembered across launches.
  style fill solid >/dev/null
  style color 0a84ff >/dev/null
  style width 8 >/dev/null
  expect_equal "the fill is stored through the shared defaults" "1" "$(send "$APP_SOCK" "defaults-get annotationFilled")"
  expect_equal "the Annotation color is stored" "0a84ff" "$(send "$APP_SOCK" "defaults-get annotationColor")"
  expect_equal "the width is stored" "8" "$(send "$APP_SOCK" "defaults-get annotationWidth")"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Esc closes the Editor"; else fail "the helper is still running after Esc"; fi
fi

if capture_into_editor "menu-click capture.screen"; then
  keystroke r >/dev/null
  drag 40 30 120 90 >/dev/null
  expect_contains "a new Rectangle in the next Editor starts solid, blue and 8 points wide" "annotation 1 rectangle 40.0 30.0 120.0 90.0 0a84ff 8.0 solid" "$(send "$EDITOR_SOCK" "editor-document $EDITOR_N")"
  BLUE="$(pixel "$(export_png remembered)" 160 120)"
  if (($(channel "$BLUE" 2) >= 200 && $(channel "$BLUE" 0) <= 100)); then pass "and its pixels are blue"; else fail "the remembered color is not blue in the Export: $BLUE"; fi
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null

# 7. A 1x Capture is sRGB and its pixels are its points: the color can be checked exactly.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 40 30 120 90 >/dev/null
  EXPORT="$(export_png one-x)"
  ONE_X="$(fixture_diff "$EXPORT" 301 187 40 30 120 90)"
  expect_equal "at 1x the Rectangle covers exactly its points" "bbox=40,30,120,90" "$(printf '%s\n' "$ONE_X" | grep '^bbox=')"
  expect_equal "at 1x nothing outside it changed" "outside=0" "$(printf '%s\n' "$ONE_X" | grep '^outside=')"
  expect_near "at 1x the Annotation color is exact in sRGB" "255,59,48" "$(pixel "$EXPORT" 80 60)"
  expect_equal "the 1x Export keeps the sRGB profile" "$SRGB_SHA" "$(png_field "$("$INSPECT" info "$EXPORT")" icc_sha256)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null

# 8. A Capture bigger than the window is shown scaled down; the pointer still lands on the right pixels.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  ZOOM="$(document_field zoom)"
  if awk -v z="$ZOOM" 'BEGIN { exit !(z > 0 && z < 1) }'; then pass "the 2560 x 1440 point Capture is scaled to fit the window (zoom $ZOOM)"; else fail "the large Capture is not scaled down (zoom $ZOOM)"; fi
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 200 100 700 400 >/dev/null  # pixels (400,200) to (1400,800)
  BIG_DIFF="$(fixture_diff "$(export_png big)" 5120 2880 398 198 1402 802)"
  expect_equal "a Rectangle drawn on the scaled-down Capture stays within a pixel of its place" "outside=0" "$(printf '%s\n' "$BIG_DIFF" | grep '^outside=')"
  BIG_BBOX="$(png_field "$BIG_DIFF" bbox)"
  IFS=, read -r BX0 BY0 BX1 BY1 <<<"$BIG_BBOX"
  if ((BX0 >= 399 && BX0 <= 401 && BY0 >= 199 && BY0 <= 201 && BX1 >= 1399 && BX1 <= 1401 && BY1 >= 799 && BY1 <= 801)); then pass "its edges are at (400,200) and (1400,800) pixels ($BIG_BBOX)"; else fail "the Rectangle's pixels are $BIG_BBOX, expected 400,200,1400,800"; fi
  # With an Annotation selected the canvas rests: nothing animates.
  sleep 1
  assert_idle_cpu "the Editor helper with an Annotation selected on a large Capture" "$HELPER_PID" 3
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null

# 9. Memory: Capture, draw, Copy, close. The menu bar app stays flat and no helper is left behind.
send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null
TOOLS_BASELINE="$(footprint_mb "$APP_PID")"
for _ in 1 2 3; do
  if capture_into_editor "menu-click capture.screen"; then
    keystroke r >/dev/null; drag 100 100 600 500 >/dev/null
    keystroke o >/dev/null; drag 700 100 1200 500 >/dev/null
    keystroke a >/dev/null; drag 100 700 900 1100 >/dev/null
    copy_closes_editor
  fi
done
sleep 1
TOOLS_AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$TOOLS_AFTER" -v b="$TOOLS_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app's memory is flat over Capture, draw, Copy cycles (${TOOLS_BASELINE} MB before, ${TOOLS_AFTER} MB after)"
else
  fail "the menu bar app went from ${TOOLS_BASELINE} MB to ${TOOLS_AFTER} MB over drawing cycles (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
if [[ -z "$(helper_pid)" ]]; then pass "no helper process is left after the drawing cycles"; else fail "a helper is still running after the drawing cycles"; fi
assert_idle_cpu "menu bar app after the drawing cycles" "$APP_PID" 3
send "$APP_SOCK" pasteboard-clear >/dev/null
