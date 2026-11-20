# Flow: the Editor's tools. Select, Arrow, Rectangle and Oval draw, pick, move and resize
# Annotations with synthetic mouse events delivered through the window; ⌘Z, ⇧⌘Z and ⌫ work from
# the keyboard; every check reads what a user could see: the Export's pixels (Copy puts the
# flattened Capture on the private pasteboard, read back with the independent decoder in
# png-inspect), the canvas's own rendering, and which toolbar items are enabled. The fixture at
# scale 2 is a 301 x 187 point Capture of 602 x 374 pixels in Display P3, so an Annotation in
# image points lands on twice the pixels, and a flipped or shifted transform shows up as pixels
# changed in the wrong place. Sourced by scripts/check-run.sh, after flow 35.
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

  # Nothing to undo, redo or delete in a fresh Editor.
  expect_disabled "Undo is disabled with nothing to undo" undo
  expect_disabled "Redo is disabled with nothing to redo" redo
  expect_disabled "Delete Annotation is disabled with nothing selected" delete-annotation
  expect_contains "pressing a disabled item does nothing" "error toolbar item is disabled" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N undo")"

  # 1. A solid Rectangle, dragged from (40,30) to (120,90) points: pixels (80,60) to (240,180).
  keystroke r >/dev/null
  style fill solid >/dev/null
  expect_equal "the Rectangle drag replies ok" "ok" "$(drag 40 30 120 90)"
  expect_selected "the new Annotation is selected: Delete Annotation is enabled"
  expect_enabled "Undo is enabled after a drag" undo
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

  # 2. Undo and Redo: one drag is one step.
  expect_equal "⌘Z replies ok" "ok" "$(keystroke undo)"
  expect_equal "one ⌘Z takes the whole Rectangle back: the Export is the untouched Capture" "mismatches=0" "$("$INSPECT" verify-fixture "$(export_png undone)" $W $H | grep '^mismatches=')"
  expect_disabled "Undo is disabled again" undo
  expect_enabled "Redo is enabled" redo
  expect_equal "⇧⌘Z replies ok" "ok" "$(keystroke redo)"
  expect_equal "after Redo the Export has the Rectangle again" "bbox=80,60,240,180" "$(fixture_diff "$(export_png redone)" $W $H | grep '^bbox=')"
  expect_disabled "Redo is disabled again" redo

  # 3. Select: move, resize, fill and delete, each one Undo step.
  keystroke v >/dev/null
  drag 80 60 130 100 >/dev/null  # from inside the Rectangle: moves it by (+50, +40) points
  expect_equal "the moved Rectangle is at its new pixels" "bbox=180,140,340,260" "$(fixture_diff "$(export_png moved)" $W $H | grep '^bbox=')"
  keystroke undo >/dev/null
  expect_equal "one Undo puts the Rectangle back where it was" "bbox=80,60,240,180" "$(fixture_diff "$(export_png unmoved)" $W $H | grep '^bbox=')"
  keystroke redo >/dev/null
  drag 170 130 200 150 >/dev/null  # the bottom right handle of the moved box (90,70)-(170,130)
  expect_equal "the resized Rectangle spans its new corner" "bbox=180,140,400,300" "$(fixture_diff "$(export_png resized)" $W $H | grep '^bbox=')"
  keystroke undo >/dev/null
  expect_equal "one Undo puts the old size back" "bbox=180,140,340,260" "$(fixture_diff "$(export_png unresized)" $W $H | grep '^bbox=')"
  keystroke redo >/dev/null

  drag 200 150 200 150 >/dev/null  # a press and release on the handle, not moved
  keystroke undo >/dev/null
  expect_equal "a click that moves nothing records no Undo step (Undo took back the resize)" "bbox=180,140,340,260" "$(fixture_diff "$(export_png noclickstep)" $W $H | grep '^bbox=')"
  keystroke redo >/dev/null

  send "$EDITOR_SOCK" "editor-press $EDITOR_N annotation-fill" >/dev/null  # solid to outline: one Undo step
  EXPORT="$(export_png outline)"
  OUTLINE_DIFF="$(fixture_diff "$EXPORT" $W $H 190 150 390 290)"
  expect_equal "an outline Rectangle is 5 points of stroke around its edge" "bbox=175,135,405,305" "$(printf '%s\n' "$OUTLINE_DIFF" | grep '^bbox=')"
  expect_equal "the inside of an outline Rectangle is still the Capture" "inside=0" "$(printf '%s\n' "$OUTLINE_DIFF" | grep '^inside=')"
  keystroke undo >/dev/null
  expect_equal "one Undo turns the fill back to solid" "changed=35200" "$(fixture_diff "$(export_png solid-again)" $W $H | grep '^changed=')"

  expect_equal "⌫ replies ok" "ok" "$(keystroke delete)"
  expect_unchanged "⌫ deletes the selected Annotation: the Export is the untouched Capture" "$(export_png deleted)" $W $H
  expect_nothing_selected "nothing is selected after the delete"
  keystroke undo >/dev/null
  expect_equal "Undo takes the deletion back" "bbox=180,140,400,300" "$(fixture_diff "$(export_png undeleted)" $W $H | grep '^bbox=')"
  click 140 110 >/dev/null  # Undo does not bring the selection back: pick it again
  keystroke delete >/dev/null
  expect_unchanged "the restored Annotation can be deleted again" "$(export_png redeleted)" $W $H

  # A drag that leaves nothing to see or click draws nothing, and a resize that collapses an
  # Annotation is undone.
  keystroke r >/dev/null
  drag 100 100 101 101 >/dev/null
  expect_unchanged "a tiny drag draws nothing" "$(export_png tiny)" $W $H
  keystroke a >/dev/null
  drag 100 100 100 100 >/dev/null
  expect_unchanged "a drag that ends where it started draws no Arrow" "$(export_png no-arrow)" $W $H

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
  expect_unchanged "⌫ deletes it: the Export is the Capture again" "$(export_png oval-gone)" $W $H

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
  expect_unchanged "⌫ deletes the outline Oval" "$(export_png outline-oval-gone)" $W $H

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
  drag 30 150 20 140 >/dev/null  # the tail handle: the tail goes to pixel (40,280)
  expect_red "dragging the tail handle moves the tail" "$(pixel "$(export_png tail-moved)" 44 282)"
  keystroke undo >/dev/null
  expect_equal "one Undo puts the tail back" "$(fixture_pixel 44 282 $W $H)" "$(pixel "$(export_png tail-back)" 44 282)"
  keystroke delete >/dev/null
  expect_unchanged "⌫ deletes the Arrow" "$(export_png arrow-gone)" $W $H

  # Keys work with Caps Lock on, and ⌫ works when it reaches the window as a plain key press
  # (the window is not offered it as a key equivalent first).
  keystroke caps-r >/dev/null
  drag 40 30 120 90 >/dev/null
  if (($(changed_pixels "$(export_png caps)" $W $H) > 0)); then pass "the R key picks Rectangle with Caps Lock on"; else fail "no Rectangle was drawn after Caps Lock R"; fi
  keystroke caps-undo >/dev/null
  expect_unchanged "⌘Z undoes with Caps Lock on" "$(export_png caps-undone)" $W $H
  keystroke caps-redo >/dev/null
  if (($(changed_pixels "$(export_png caps-redone)" $W $H) > 0)); then pass "⇧⌘Z redoes with Caps Lock on"; else fail "Redo did nothing with Caps Lock on"; fi
  keystroke v >/dev/null
  click 40 60 >/dev/null  # an outline Rectangle is picked on its line
  expect_selected "the Rectangle is selected"
  keystroke plain-delete >/dev/null
  expect_unchanged "⌫ as a plain key press deletes the selected Annotation" "$(export_png plain-delete)" $W $H

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
  expect_blue "a new Editor starts with the remembered solid blue Rectangle" "$(pixel "$(export_png remembered)" 160 120)"
  keystroke a >/dev/null
  drag 30 150 120 170 >/dev/null  # the shaft crosses pixel x=120 at y=313.3
  expect_blue "the remembered width is 8 points: the Arrow is blue 7 pixels from its centre line" "$(pixel "$(export_png remembered-width)" 120 307)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null

# 7. The canvas shows what Export draws, and kinds Export draws first lie beneath the others.
if capture_into_editor "menu-click capture.screen"; then
  style fill solid >/dev/null
  keystroke r >/dev/null; drag 40 30 120 90 >/dev/null
  keystroke o >/dev/null  # a drawing tool starts with nothing selected, so the style is for the next Annotation only
  style fill outline >/dev/null
  drag 150 20 250 100 >/dev/null
  keystroke a >/dev/null; drag 30 150 120 170 >/dev/null
  PARITY="$("$INSPECT" compare "$(export_png parity)" "$(preview_png)")"
  expect_equal "the canvas's own rendering (the preview) is the Export, to within anti-aliasing" "over_8=0" "$(printf '%s\n' "$PARITY" | grep '^over_8=')"

  # A kind Export draws before the Annotations (as Redaction will be) is added after the
  # Rectangle, overlapping it: it still lies beneath it, and Select picks the Rectangle first.
  send "$EDITOR_SOCK" "editor-inject-effect $EDITOR_N 80 60 160 120" >/dev/null
  PREVIEW="$(preview_png)"
  expect_red "where the Rectangle and the later kind overlap, the preview shows the Rectangle" "$(pixel "$PREVIEW" 200 150)"
  expect_green "where only the later kind is, the preview shows it" "$(pixel "$PREVIEW" 280 220)"
  EXPORT="$(export_png effect)"
  expect_red "the Export draws the Rectangle there too" "$(pixel "$EXPORT" 200 150)"
  expect_equal "the Annotations stage does not draw a kind another stage owns" "$(fixture_pixel 280 220 $W $H)" "$(pixel "$EXPORT" 280 220)"
  keystroke v >/dev/null
  click 100 75 >/dev/null
  keystroke delete >/dev/null
  expect_green "Select picked the Rectangle (the topmost), not the later kind: deleting it shows the kind beneath" "$(pixel "$(preview_png)" 200 150)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi

# 8. The first click on a background Editor: with two Editors open the first is in the
#    background. Synthetic mouse events go through its window like a real click, onto the canvas,
#    a tool in the rail and a toolbar item, and each does its job on that very first click. A
#    click on Delete Capture only brings the Editor forward.
if capture_into_editor "menu-click capture.screen"; then
  FIRST_N="$EDITOR_N"
  if capture_into_editor "menu-click capture.screen"; then
    SECOND_N="$EDITOR_N"
    EDITOR_N="$FIRST_N"
    CONTROLS="$(send "$EDITOR_SOCK" "editor-controls $FIRST_N")"
    expect_contains "the toolbars' controls are found by their tooltips" "control Rectangle (R)" "$CONTROLS"
    expect_contains "Undo is among them" "control Undo (⌘Z)" "$CONTROLS"
    expect_contains "Delete Capture is among them" "control Delete Capture" "$CONTROLS"
    expect_contains "the Editor is in the background" "key=no" "$(send "$EDITOR_SOCK" "editor-background $FIRST_N")"
    expect_contains "a click on a tool in the rail of a background Editor is not lost" "ok" "$(click_on "$FIRST_N" tool rectangle)"
    background_editor "$FIRST_N"
    expect_equal "a drag on the canvas of a background Editor draws, from its very first press" "ok" "$(drag 40 30 120 90)"
    EXPORT="$(export_png first-click-canvas)"
    expect_equal "the Rectangle tool picked by that first click drew an outline Rectangle (pixels in place)" "bbox=75,55,245,185" "$(fixture_diff "$EXPORT" $W $H | grep '^bbox=')"
    background_editor "$FIRST_N"
    expect_contains "a click on Undo in a background Editor is not lost" "ok" "$(click_on "$FIRST_N" item undo)"
    expect_unchanged "and it undid the Rectangle" "$(export_png first-click-undo)" $W $H

    # The control: Delete Capture refuses the first click.
    EDITOR_N="$SECOND_N"
    CAPTURE_FILE="$RUN_ROOT/captures/capture-$SECOND_N.pixels"
    expect_contains "the second Editor is in the background" "key=no" "$(send "$EDITOR_SOCK" "editor-background $SECOND_N")"
    FIRST_CLICK="$(click_on "$SECOND_N" item delete-capture)"
    sleep 1  # a Delete Capture that did run would have closed the Editor and removed the file by now
    if [[ -f "$CAPTURE_FILE" ]]; then pass "the first click on Delete Capture in a background Editor leaves the Capture in place"; else fail "Delete Capture deleted the Capture on a background Editor's first click"; fi
    expect_equal "and leaves both Editors open" "$(printf '%s\n%s' "$FIRST_N" "$SECOND_N")" "$(open_editors)"
    expect_contains "that click only brought the window forward" "key-before=no key-after=yes" "$FIRST_CLICK"
    # The second click, now the Editor is in front, deletes at once: no question, with edits.
    click_on "$SECOND_N" item delete-capture >/dev/null
    if wait_until 5 bash -c "[[ \"\$(printf 'editors\n' | nc -U -w 2 '$EDITOR_SOCK')\" == '$FIRST_N' ]]"; then pass "the next click on Delete Capture deletes: the Editor closes at once"; else fail "a second click on Delete Capture did not close the Editor"; fi
    if [[ ! -e "$CAPTURE_FILE" ]]; then pass "and its Capture is removed"; else fail "the Capture is still there after Delete Capture"; fi
    expect_equal "and no question was asked" "none" "$(send "$EDITOR_SOCK" editor-prompt)"
    send "$EDITOR_SOCK" "editor-key $FIRST_N escape" >/dev/null
    wait_until 10 gone "$HELPER_PID"
  fi
fi

# 9. A 1x Capture is sRGB and its pixels are its points: the color can be checked exactly.
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

# 10. A Capture bigger than the window is shown scaled down. The mouse events are placed by asking
#     the canvas's layers where the Capture is on screen, so a wrong zoom or offset in the pointer
#     mapping shows as pixels in the wrong place.
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

# 11. Memory: Capture, draw, Copy, close. The menu bar app stays flat and no helper is left behind.
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
