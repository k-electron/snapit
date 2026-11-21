# Flow: Redaction and Crop. A Redaction pixelates what lies beneath it in bold averaged blocks;
# the engine draws both the canvas's preview and the Export, so the two match to the last bit, and
# the Export holds no original pixel under it. Crop trims the Capture: the Crop tool's handles,
# Enter or the toolbar button apply it, Undo takes it back, and Export flattens in the order
# crop, Redactions, Annotations. Every check reads what a user could see: the Export's pixels
# (Copy puts the flattened Capture on the private pasteboard, read back with the independent
# decoder in png-inspect, which recomputes every block mean from the fixture formula), the
# canvas's own rendering and which toolbar items are enabled.
#
# The block rule the checks apply (docs/development/testing.md): the block is a third of the Redaction's
# short side, between 14 and 48 points, at least 4 pixels; its grid starts at the Redaction's
# top left corner in pixels (after a crop, at the corner of what is left of it), and what is left
# over at the right and bottom edge is folded into the last tile, so no tile is a sliver.
#
# Fixture at scale 2: a 301 x 187 point Capture of 602 x 374 pixels in Display P3, so a point
# position lands on twice the pixels. Sourced by scripts/check-run.sh, after flow 36.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

SRGB_SHA="${SRGB_SHA:-$("$INSPECT" profile-sha srgb)}"
P3_SHA="${P3_SHA:-$("$INSPECT" profile-sha displayP3)}"
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
W=602
H=374

open_editor() { capture_into_editor "menu-click capture.screen"; }
# Esc closes the Editor (a pending crop takes the first Esc).
close_editor() {
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 2 gone "$HELPER_PID" || send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
}
# redaction_block <width px> <height px> <scale>: the block of the rule above, worked out here.
redaction_block() {
  awk -v w="$1" -v h="$2" -v s="$3" 'BEGIN {
    short = (w < h ? w : h) / s; pt = short / 3
    if (pt < 14) pt = 14
    if (pt > 48) pt = 48
    b = int(pt * s + 0.5); if (b < 4) b = 4
    print b }'
}
# verify_redaction <png> <w> <h> <full w> <full h> <ox> <oy> <x0> <y0> <x1> <y1> <block>
verify_redaction() { "$INSPECT" verify-redaction "$@"; }
# field <output> <key>
field() { printf '%s\n' "$1" | sed -n "s/^$2=//p" | head -1; }
# expect_redacted <description> <png> <w> <h> <full w> <full h> <ox> <oy> <x0> <y0> <x1> <y1> <block>: every
# pixel of the rectangle is its tile's mean of the fixture, as the independent checker computes it.
expect_redacted() {
  local description="$1" out
  shift
  out="$(verify_redaction "$@")"
  expect_equal "$description" "0" "$(field "$out" mismatches)"
  [[ "$(field "$out" mismatches)" == "0" ]] || echo "     $(field "$out" first_mismatch)"
  expect_equal "$description: no original pixel survives" "0" "$(field "$out" survivors)"
  # No tile is a sliver: the shortest side of a tile is the block, or all of a side shorter than that.
  local x0="${8}" y0="${9}" x1="${10}" y1="${11}" block="${12}" shortest
  shortest=$((x1 - x0 < y1 - y0 ? x1 - x0 : y1 - y0))
  ((shortest < block)) || shortest="$block"
  if (($(field "$out" smallest_tile) >= shortest)); then pass "$description: no tile is thinner than the block"; else fail "$description: a tile is only $(field "$out" smallest_tile) pixels thick (block $block)"; fi
}
# expect_exact_preview <description> <export png>: the canvas's own rendering is the Export, bit for bit.
expect_exact_preview() {
  expect_equal "$1" "max_diff=0" "$("$INSPECT" compare "$2" "$(preview_png)" | grep '^max_diff=')"
}
# expect_tool <tool id>
expect_tool() { expect_equal "the $1 tool is active" "$1" "$(document_field tool)"; }

# 1. The tools and toolbar items are registered, in order, with tooltips.
if open_editor; then
  TOOLBAR="$(send "$EDITOR_SOCK" "editor-toolbar $EDITOR_N")"
  expect_in_order "Redaction and Crop follow the other tools on the left toolbar" \
    "$(printf '%s\n' "$TOOLBAR" | grep '^tool ' | cut -d' ' -f2)" select arrow rectangle oval redaction crop
  expect_contains "Redaction has its tooltip and key" "tool redaction 700 Redaction (X)" "$TOOLBAR"
  expect_contains "Crop has its tooltip and key" "tool crop 800 Crop (C)" "$TOOLBAR"
  expect_contains "Apply Crop has its tooltip" "item crop-apply options Apply Crop (↩)" "$TOOLBAR"
  expect_contains "Cancel Crop has its tooltip" "item crop-cancel options Cancel Crop (Esc)" "$TOOLBAR"
  # Every control of the top toolbar can be clicked: no two are on top of each other, even in the
  # smallest window (this Capture is small, so the window is at its smallest).
  expect_equal "no two controls of the top toolbar overlap (frames, not centres: a swatch is narrower than a button)" \
    "overlapping-controls=0" "$(send "$EDITOR_SOCK" "editor-layout $EDITOR_N" | grep '^overlapping-controls=')"
  expect_disabled "Apply Crop is disabled until the Crop tool is chosen" crop-apply
  expect_disabled "Cancel Crop is disabled until the Crop tool is chosen" crop-cancel

  # 2. The canvas shows the Capture exactly as Export flattens it: no Annotation, no difference
  #    at all (this is the base the Redaction comparisons stand on).
  expect_exact_preview "with nothing drawn the canvas's own rendering is the Export, bit for bit" "$(export_png plain)"

  # 3. A Redaction: dragged from (40,30) to (140,90) points, pixels (80,60) to (280,180): 200 x 120
  #    pixels with 40-pixel blocks (a third of 60 points is 20 points), so five by three whole
  #    blocks.
  keystroke x >/dev/null
  expect_tool redaction
  expect_equal "the Redaction drag replies ok" "ok" "$(drag 40 30 140 90)"
  expect_selected "the new Redaction is selected"
  BLOCK="$(redaction_block 200 120 2)"
  expect_equal "a third of its 60 point short side is 20 points: 40 pixel blocks" "40" "$BLOCK"
  REDACTED="$(export_png redaction)"
  OUT="$(verify_redaction "$REDACTED" $W $H $W $H 0 0 80 60 280 180 "$BLOCK")"
  expect_equal "every pixel under the Redaction is the mean of its 40 x 40 block of the Capture" "0" "$(field "$OUT" mismatches)"
  expect_equal "nothing outside the Redaction changed" "0" "$(field "$OUT" outside_mismatches)"
  expect_equal "the Redaction is five by three blocks" "15" "$(field "$OUT" blocks)"
  expect_equal "the Export holds one color per block under the Redaction and nothing more" "15" "$(field "$OUT" colors)"
  expect_equal "no original pixel survives under the Redaction" "0" "$(field "$OUT" survivors)"
  if (($(changed_pixels "$REDACTED" $W $H) > 23000)); then pass "nearly every pixel under the Redaction changed ($(changed_pixels "$REDACTED" $W $H) of 24000)"; else fail "too few pixels changed under the Redaction: $(changed_pixels "$REDACTED" $W $H)"; fi
  expect_exact_preview "the canvas's preview of the Redaction is the Export, bit for bit" "$REDACTED"
  EXPORT_INFO="$("$INSPECT" info "$REDACTED")"
  expect_equal "the redacted Export keeps the display's ICC profile byte for byte" "$P3_SHA" "$(png_field "$EXPORT_INFO" icc_sha256)"
  expect_contains "the Capture's own mapping stays read-only" "capture-mapping=read-only" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  # What is exported is flattened pixels, not a layer: the Export is a PNG with the same size.
  expect_equal "the redacted Export is the Capture's size" "602" "$(png_field "$EXPORT_INFO" width)"

  # 4. Undo takes the Redaction away (one drag, one step), Redo brings it back, and Select moves it
  #    (its blocks follow it onto the pixel grid of the new place).
  keystroke undo >/dev/null
  expect_unchanged "one Undo takes the Redaction back: the Export is the untouched Capture" "$(export_png undone)" $W $H
  keystroke redo >/dev/null
  expect_exact_preview "after Redo the canvas shows the Redaction again" "$(export_png redone)"
  keystroke v >/dev/null
  drag 90 60 110 80 >/dev/null  # from inside the Redaction: moves it by (+20, +20) points
  MOVED="$(export_png moved)"
  expect_redacted "the moved Redaction is pixelated at its new place (pixels (120,100) to (320,220))" "$MOVED" $W $H $W $H 0 0 120 100 320 220 40
  expect_equal "and the pixels it left are the Capture again" "outside=0" "$(fixture_diff "$MOVED" $W $H 120 100 320 220 | grep '^outside=')"
  keystroke undo >/dev/null
  expect_equal "one Undo puts the Redaction back where it was" "bbox=80,60,280,180" "$(fixture_diff "$(export_png unmoved)" $W $H | grep '^bbox=')"
  close_editor
fi

# 4b. A Redaction whose size is not a whole number of blocks, at fractional points: the edge blocks
#     are smaller and averaged over their own pixels. (10.2,5.2) to (113.4,71.9) points is pixels
#     (20,10) to (227,144) after snapping each edge to the nearest pixel.
if open_editor; then
  keystroke x >/dev/null
  drag 10.2 5.2 113.4 71.9 >/dev/null
  BLOCK="$(redaction_block 207 134 2)"
  OUT="$(verify_redaction "$(export_png edge)" $W $H $W $H 0 0 20 10 227 144 "$BLOCK")"
  expect_equal "a fractional Redaction snaps to whole pixels: its tiles, edge tiles included, are exact block means" "0" "$(field "$OUT" mismatches)"
  expect_equal "and nothing outside those pixels changed" "0" "$(field "$OUT" outside_mismatches)"
  close_editor
fi

# 4c. A width and a height one pixel over a whole number of blocks (the leftover is a single pixel
#     column and row, which used to be left as the original): (10,10) to (110.5,70.5) points is
#     pixels (20,20) to (221,141), 201 x 121 with 40-pixel blocks, so the last tiles are 41 pixels.
if open_editor; then
  keystroke x >/dev/null
  drag 10 10 110.5 70.5 >/dev/null
  BLOCK="$(redaction_block 201 121 2)"
  expect_equal "a third of its 60.5 point short side is 20.17 points: 40 pixel blocks" "40" "$BLOCK"
  EDGE="$(export_png one-over)"
  expect_redacted "a Redaction one pixel over a whole number of blocks has no original pixel left in its last column and row" \
    "$EDGE" $W $H $W $H 0 0 20 20 221 141 "$BLOCK"
  expect_equal "the corner pixel is not the Capture's" "no" \
    "$([[ "$(pixel "$EDGE" 220 140)" == "$(fixture_pixel 220 140 $W $H)" ]] && echo yes || echo no)"
  expect_exact_preview "and the preview is the Export, bit for bit" "$EDGE"
  close_editor
fi

# 5. Overlapping Redactions each pixelate the original pixels (what the canvas shows), the later
#    one over the earlier, never the earlier one's blocks.
if open_editor; then
  keystroke x >/dev/null
  drag 40 30 140 90 >/dev/null
  drag 100 50 200 110 >/dev/null
  OVERLAP="$(export_png overlap)"
  expect_redacted "the later Redaction is the block means of the original Capture, over the earlier one" "$OVERLAP" $W $H $W $H 0 0 200 100 400 220 40
  expect_redacted "the earlier Redaction is intact where the later one is not over it (its first block column)" "$OVERLAP" $W $H $W $H 0 0 80 60 200 100 40
  expect_exact_preview "the canvas's preview of overlapping Redactions is the Export, bit for bit" "$OVERLAP"
  close_editor
fi

# 6. Annotations are drawn over a Redaction, and a Redaction lies beneath every Annotation: select
#    picks the Rectangle drawn later, whichever was drawn first.
if open_editor; then
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 60 50 100 80 >/dev/null  # pixels (120,100) to (200,160)
  keystroke x >/dev/null
  drag 40 30 140 90 >/dev/null  # drawn after the Rectangle, over it: the Rectangle is still on top
  MIXED="$(export_png mixed)"
  expect_red "the Rectangle is drawn over the Redaction (Annotations come after Redactions)" "$(pixel "$MIXED" 160 130)"
  expect_redacted "the Redaction's blocks are exact where no Annotation lies over them" "$MIXED" $W $H $W $H 0 0 200 60 280 180 40
  keystroke v >/dev/null
  click 80 65 >/dev/null
  keystroke delete >/dev/null
  expect_exact_preview "Select picked the Rectangle (topmost) under the click: with it deleted the Redaction alone is left" "$(export_png mixed-deleted)"
  expect_redacted "and the Redaction's blocks hide what the Rectangle covered" "$(export_png mixed-deleted2)" $W $H $W $H 0 0 80 60 280 180 40
  style fill outline >/dev/null
  close_editor
fi

# 7. Crop at 2x with fractional handle drags. The crop rectangle starts as the whole Capture; its
#    top left handle goes to (20.15,15.35) points and its bottom right handle to (170.65,120.8):
#    pixels (40.3,30.7) and (341.3,241.6) snap to (40,31) and (341,242): a 301 x 211 pixel Export.
if open_editor; then
  keystroke c >/dev/null
  expect_tool crop
  expect_enabled "Apply Crop is enabled while the Crop tool is active" crop-apply
  expect_enabled "Cancel Crop is enabled while the Crop tool is active" crop-cancel
  expect_disabled "Undo waits while a crop is being drawn" undo
  expect_equal "dragging the top left handle replies ok" "ok" "$(drag 0 0 20.15 15.35)"
  expect_equal "dragging the bottom right handle replies ok" "ok" "$(drag 301 187 170.65 120.8)"
  # The crop rectangle is on the canvas: the Capture outside it is shaded, inside it is untouched,
  # and its corners have handles. Draft: points (20.15,15.35) to (170.65,120.8).
  OVERLAY="$(preview_overlay_png)"
  expect_equal "inside the crop rectangle the canvas shows the Capture untouched" "$(fixture_pixel 200 140 $W $H)" "$(pixel "$OVERLAY" 200 140)"
  SHADED="$(pixel "$OVERLAY" 10 300)"
  PLAIN="$(fixture_pixel 10 300 $W $H)"
  for c in 0 1 2; do
    want=$(($(channel "$PLAIN" "$c") / 2))
    got="$(channel "$SHADED" "$c")"
    if ((got < want - 3 || got > want + 3)); then fail "outside the crop rectangle the Capture is shaded to half (channel $c: expected about $want, got $got)"; fi
  done
  pass "outside the crop rectangle the Capture is shaded"
  expect_equal "the top left handle is white" "255,255,255" "$(pixel "$OVERLAY" 40 31)"
  expect_equal "the bottom right handle is white" "255,255,255" "$(pixel "$OVERLAY" 341 242)"
  expect_equal "the handle in the middle of the right edge is white" "255,255,255" "$(pixel "$OVERLAY" 341 136)"
  expect_equal "with the shade and handles hidden the canvas's rendering is still the whole Capture" "0" \
    "$(changed_pixels "$(preview_png)" $W $H)"
  expect_unchanged "and the Export is still the whole Capture" "$(export_png uncropped)" $W $H
  expect_equal "Enter replies ok" "ok" "$(keystroke enter)"
  expect_tool select
  CROPPED="$(export_png cropped-enter)"
  CROPPED_INFO="$("$INSPECT" info "$CROPPED")"
  expect_equal "the Export is the 301 pixels wide that the crop keeps" "301" "$(png_field "$CROPPED_INFO" width)"
  expect_equal "the Export is the 211 pixels high that the crop keeps" "211" "$(png_field "$CROPPED_INFO" height)"
  expect_equal "every pixel of the Export is the Capture's pixel at the crop's place, to the pixel" "mismatches=0" \
    "$("$INSPECT" verify-fixture "$CROPPED" 301 211 $W $H 40 31 | grep '^mismatches=')"
  expect_equal "the cropped Export keeps the display's ICC profile byte for byte" "$P3_SHA" "$(png_field "$CROPPED_INFO" icc_sha256)"
  expect_equal "and its resolution (144 dpi, in pixels per metre)" "5669,5669,1" "$(png_field "$CROPPED_INFO" phys)"
  expect_exact_preview "the canvas shows the cropped Capture exactly as Export does" "$CROPPED"
  expect_disabled "Apply Crop is disabled again once the Crop tool is left" crop-apply
  expect_enabled "Undo is enabled after a crop" undo

  # Undo and Redo of the crop.
  keystroke undo >/dev/null
  expect_unchanged "one Undo takes the crop back: the Export is the whole Capture" "$(export_png crop-undone)" $W $H
  expect_exact_preview "and the canvas shows the whole Capture again" "$(export_png crop-undone2)"
  keystroke redo >/dev/null
  expect_equal "Redo brings the crop back: the same Export" "max_diff=0" \
    "$("$INSPECT" compare "$CROPPED" "$(export_png crop-redone)" | grep '^max_diff=')"

  # The toolbar button is the same path as Enter.
  keystroke undo >/dev/null
  keystroke c >/dev/null
  expect_contains "choosing Crop again starts with the whole Capture" "tool=crop" "$(send "$EDITOR_SOCK" "editor-document $EDITOR_N")"
  drag 0 0 20.15 15.35 >/dev/null
  drag 301 187 170.65 120.8 >/dev/null
  expect_equal "the Apply Crop button replies ok" "ok" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N crop-apply")"
  expect_equal "the button crops exactly as Enter did" "max_diff=0" "$("$INSPECT" compare "$CROPPED" "$(export_png cropped-button)" | grep '^max_diff=')"

  # Choosing Crop again starts from the applied crop: dragging a handle further in crops more.
  keystroke c >/dev/null
  drag 20 15.5 40 30 >/dev/null  # the top left handle of the applied crop, to (40,30) points: pixels (80,60)
  keystroke enter >/dev/null
  expect_equal "re-cropping from the applied crop keeps the Capture's own pixels (origin (80,60))" "mismatches=0" \
    "$("$INSPECT" verify-fixture "$(export_png recropped)" 261 182 $W $H 80 60 | grep '^mismatches=')"
  close_editor
fi

# 8. Esc and Cancel leave a crop that was not applied.
if open_editor; then
  keystroke c >/dev/null
  drag 0 0 50 40 >/dev/null
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  if gone "$HELPER_PID"; then fail "Esc closed the Editor while a crop was being drawn"; else pass "Esc while cropping does not close the Editor"; fi
  expect_tool select
  expect_unchanged "Esc dropped the crop: the Export is the whole Capture" "$(export_png esc-crop)" $W $H
  keystroke c >/dev/null
  drag 0 0 50 40 >/dev/null
  expect_equal "the Cancel Crop button replies ok" "ok" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N crop-cancel")"
  expect_tool select
  expect_unchanged "Cancel dropped the crop too" "$(export_png cancel-crop)" $W $H
  expect_disabled "Undo has nothing to undo: neither was a change" undo
  # A click with the Crop tool (no drag) changes nothing, and a drag outside draws a new rectangle.
  keystroke c >/dev/null
  click 150 90 >/dev/null
  drag 60 40 200 130 >/dev/null  # inside the whole-Capture rectangle: moves it, clamped to the Capture
  keystroke enter >/dev/null
  expect_unchanged "a rectangle that is the whole Capture (moved nowhere) crops nothing" "$(export_png whole)" $W $H
  expect_disabled "so no Undo step was made: Undo is disabled" undo
  close_editor
fi

# 9. Annotations drawn before the crop sit in the right place after it: the crop only moves the
#    window. A Rectangle at pixels (80,60) to (240,180) lies at (40,29) to (200,149) once the
#    crop's origin (40,31) is taken off.
if open_editor; then
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 40 30 120 90 >/dev/null
  keystroke c >/dev/null
  drag 0 0 20.15 15.35 >/dev/null
  drag 301 187 170.65 120.8 >/dev/null
  keystroke enter >/dev/null
  EXPORT="$(export_png rect-then-crop)"
  RECT="$("$INSPECT" diff-crop "$EXPORT" 301 211 $W $H 40 31 40 29 200 149)"
  expect_equal "the Rectangle drawn before the crop is exactly at its shifted place" "bbox=40,29,200,149" "$(printf '%s\n' "$RECT" | grep '^bbox=')"
  expect_equal "all of its 160 x 120 pixels are drawn" "changed=19200" "$(printf '%s\n' "$RECT" | grep '^changed=')"
  expect_red "it is the Annotation color" "$(pixel "$EXPORT" 120 89)"
  expect_equal "the canvas's rendering shows the cropped Rectangle as Export does, to within anti-aliasing" "over_8=0" \
    "$("$INSPECT" compare "$EXPORT" "$(preview_png)" | grep '^over_8=')"
  # The Rectangle can still be selected and moved in the cropped view.
  keystroke v >/dev/null
  drag 80 60 100 70 >/dev/null  # from inside the Rectangle (image points): moves it by (+20, +10)
  RECT="$("$INSPECT" diff-crop "$(export_png rect-moved)" 301 211 $W $H 40 31 80 49 240 169)"
  expect_equal "Select moves it in the cropped view, by the distance dragged" "bbox=80,49,240,169" "$(printf '%s\n' "$RECT" | grep '^bbox=')"
  close_editor
fi

# 9b. An Annotation that crosses the crop's edge is cut at it.
if open_editor; then
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 10 100 60 150 >/dev/null  # pixels (20,200) to (120,300); the crop starts at x=40, y=31
  keystroke c >/dev/null
  drag 0 0 20.15 15.35 >/dev/null
  drag 301 187 170.65 120.8 >/dev/null
  keystroke enter >/dev/null
  CUT="$("$INSPECT" diff-crop "$(export_png rect-cut)" 301 211 $W $H 40 31)"
  expect_equal "a Rectangle across the crop's left and bottom edge is cut there: (0,169) to (80,211)" "bbox=0,169,80,211" "$(printf '%s\n' "$CUT" | grep '^bbox=')"
  expect_equal "and every pixel of what is left of it is drawn" "changed=3360" "$(printf '%s\n' "$CUT" | grep '^changed=')"
  close_editor
fi

# 10. A Redaction drawn after the crop lands on the right pixels of the Capture, whose block grid starts
#     at its corner: (60,40) to (140,100) points is pixels (120,80) to (280,200), which is (80,49) to
#     (240,169) in the cropped Export.
if open_editor; then
  # A Redaction that reaches past where the crop will end (drawn first, on the whole Capture): its
  # blocks are a third of the whole box's short side (140 pixels is 70 points, 47 pixel blocks), and
  # the part inside the crop, which is all that is left of it, is pixelated on a grid that starts at
  # that part's corner (240,169) in the cropped Export; it is 61 x 42, narrower than a block, so a
  # single tile.
  keystroke x >/dev/null
  drag 140 100 240 170 >/dev/null
  BLOCK2="$(redaction_block 200 140 2)"
  keystroke c >/dev/null
  drag 0 0 20.15 15.35 >/dev/null
  drag 301 187 170.65 120.8 >/dev/null
  keystroke enter >/dev/null
  keystroke x >/dev/null
  drag 60 40 140 100 >/dev/null
  BLOCK="$(redaction_block 160 120 2)"
  AFTER="$(export_png redaction-after-crop)"
  expect_redacted "a Redaction drawn after the crop is pixelated at its own place, from the Capture's pixels" \
    "$AFTER" 301 211 $W $H 40 31 80 49 240 169 "$BLOCK"
  expect_redacted "a Redaction reaching past the crop is pixelated inside it, its grid starting at the visible corner" \
    "$AFTER" 301 211 $W $H 40 31 240 169 301 211 "$BLOCK2"
  expect_exact_preview "the cropped canvas's preview of both Redactions is the Export, bit for bit" "$AFTER"
  keystroke undo >/dev/null
  expect_redacted "Undo takes the Redaction drawn after the crop back and leaves the other" "$(export_png redaction-undone)" 301 211 $W $H 40 31 240 169 301 211 "$BLOCK2"
  keystroke undo >/dev/null
  keystroke undo >/dev/null
  expect_unchanged "Undo of the Redactions and the crop gives the whole untouched Capture" "$(export_png all-undone)" $W $H
  close_editor
fi

# 10b. With a crop applied, the margin around the visible part is not the Capture the user sees: a
#      press there does nothing, and a drag that leaves the visible part stops at its edge. A solid
#      Rectangle dragged from (160,100) points to (250,170), past the crop's right (170.5) and bottom
#      (121) edges, ends there: pixels (280,169) to (301,211) of the cropped Export.
if open_editor; then
  keystroke c >/dev/null
  drag 0 0 20.15 15.35 >/dev/null
  drag 301 187 170.65 120.8 >/dev/null
  keystroke enter >/dev/null
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 250 170 280 180 >/dev/null  # begins well outside the visible part
  expect_equal "a press in the margin around the cropped Capture draws nothing" "changed=0" \
    "$("$INSPECT" diff-crop "$(export_png margin)" 301 211 $W $H 40 31 | grep '^changed=')"
  drag 160 100 250 170 >/dev/null
  CUT="$("$INSPECT" diff-crop "$(export_png margin-drag)" 301 211 $W $H 40 31)"
  expect_equal "a drag past the crop's edge ends at the edge" "bbox=280,169,301,211" "$(printf '%s\n' "$CUT" | grep '^bbox=')"
  expect_equal "and covers every pixel of what is visible of it" "changed=882" "$(printf '%s\n' "$CUT" | grep '^changed=')"
  style fill outline >/dev/null
  close_editor
fi

# 11. At 1x a point is a pixel and the colors are exact in sRGB. The crop snaps (20.3,15.2) to (170.7,120.7)
#     to pixels (20,15) to (171,121): 151 x 106.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
if open_editor; then
  keystroke c >/dev/null
  drag 0 0 20.3 15.2 >/dev/null
  drag 301 187 170.7 120.7 >/dev/null
  keystroke enter >/dev/null
  EXPORT="$(export_png one-x-crop)"
  expect_equal "at 1x the crop keeps exactly the pixels between the snapped corners" "mismatches=0" \
    "$("$INSPECT" verify-fixture "$EXPORT" 151 106 301 187 20 15 | grep '^mismatches=')"
  expect_equal "the 1x cropped Export keeps the sRGB profile" "$SRGB_SHA" "$(png_field "$("$INSPECT" info "$EXPORT")" icc_sha256)"
  keystroke x >/dev/null
  drag 50 40 130 100 >/dev/null  # pixels (50,40) to (130,100): (30,25) to (110,85) after the crop; 20 pixel blocks
  expect_redacted "at 1x a Redaction after the crop is exact" "$(export_png one-x-redaction)" 151 106 301 187 20 15 30 25 110 85 "$(redaction_block 80 60 1)"
  expect_exact_preview "and so is its preview" "$(export_png one-x-redaction2)"
  drag 60 60 89 89 >/dev/null  # 29 x 29 pixels: 14 pixel blocks and a leftover pixel, at (40,45) in the cropped Export
  expect_redacted "at 1x a 29 x 29 Redaction (14 pixel blocks, 2 x 14 + 1) has no original pixel left" "$(export_png one-x-29)" 151 106 301 187 20 15 40 45 69 74 "$(redaction_block 29 29 1)"
  close_editor
fi
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null

# 12. The first click on a background Editor is not lost on the Redaction and Crop tools or on Apply Crop.
if open_editor; then
  FIRST_N="$EDITOR_N"
  if open_editor; then
    SECOND_N="$EDITOR_N"
    EDITOR_N="$FIRST_N"
    expect_contains "the first Editor is in the background" "key=no" "$(send "$EDITOR_SOCK" "editor-background $FIRST_N")"
    click_on "$FIRST_N" tool redaction >/dev/null
    expect_tool redaction
    background_editor "$FIRST_N"
    click_on "$FIRST_N" tool crop >/dev/null
    expect_tool crop
    drag 0 0 50 40 >/dev/null
    background_editor "$FIRST_N"
    click_on "$FIRST_N" item crop-apply >/dev/null
    expect_tool select
    BACKGROUND_INFO="$("$INSPECT" info "$(export_png first-click-crop)")"
    expect_equal "the first click on Apply Crop in a background Editor applies the crop: the Export is 502 x 294 pixels" "502x294" \
      "$(png_field "$BACKGROUND_INFO" width)x$(png_field "$BACKGROUND_INFO" height)"
    background_editor "$FIRST_N"
    click_on "$FIRST_N" item undo >/dev/null
    expect_unchanged "and the first click on Undo takes it back: the Export is the whole Capture" "$(export_png first-click-undo)" $W $H
    send "$EDITOR_SOCK" "editor-key $SECOND_N escape" >/dev/null
    EDITOR_N="$FIRST_N"
    close_editor
  fi
fi

# 13. A Capture bigger than the window is shown scaled down: pointer positions go through the zoom and
#     the crop. Handles dragged on a 2560 x 1440 point Capture crop (400,300) to (2000,1100): 3200 x 1600
#     pixels from (800,600); a Redaction of (600,400) to (1100,800) lies at (400,200) to (1400,1000) after it.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
if open_editor; then
  ZOOM="$(document_field zoom)"
  if awk -v z="$ZOOM" 'BEGIN { exit !(z > 0 && z < 1) }'; then pass "the 2560 x 1440 point Capture is scaled to fit the window (zoom $ZOOM)"; else fail "the large Capture is not scaled down (zoom $ZOOM)"; fi
  keystroke c >/dev/null
  drag 0 0 400 300 >/dev/null
  drag 2560 1440 2000 1100 >/dev/null
  keystroke enter >/dev/null
  ZOOM_AFTER="$(document_field zoom)"
  if awk -v a="$ZOOM" -v b="$ZOOM_AFTER" 'BEGIN { exit !(b > a) }'; then pass "after the crop the smaller Capture is shown larger (zoom $ZOOM_AFTER)"; else fail "the cropped Capture did not get a bigger zoom ($ZOOM then $ZOOM_AFTER)"; fi
  keystroke x >/dev/null
  drag 600 400 1100 800 >/dev/null
  BIG="$(export_png big-crop-redaction)"
  BIG_BLOCK="$(redaction_block 1000 800 2)"
  expect_equal "the largest block is 48 points: 96 pixels" "96" "$BIG_BLOCK"
  expect_equal "the cropped Export of the large Capture is the crop's size" "3200x1600" \
    "$(png_field "$("$INSPECT" info "$BIG")" width)x$(png_field "$("$INSPECT" info "$BIG")" height)"
  expect_redacted "a Redaction on the scaled-down, cropped Capture is exact on its pixels" "$BIG" 3200 1600 5120 2880 800 600 400 200 1400 1000 "$BIG_BLOCK"
  expect_equal "and nothing outside it changed" "0" "$(field "$(verify_redaction "$BIG" 3200 1600 5120 2880 800 600 400 200 1400 1000 "$BIG_BLOCK")" outside_mismatches)"
  expect_exact_preview "the preview on the scaled-down, cropped Capture is the Export, bit for bit" "$BIG"
  # The heaviest Editor of the run, at rest: nothing is spinning.
  expect_not_spinning "the Editor helper with a Redaction on a cropped large Capture" "$HELPER_PID" 5
  close_editor
fi
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null

# 14. A full 6K Copy (6016 x 3384 pixels) with a crop, Redactions and Annotations.
send "$APP_SOCK" "fixture-display 2 3008 1692" >/dev/null
if open_editor; then
  keystroke r >/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do drag $((100 + i * 60)) 100 $((200 + i * 60)) 300 >/dev/null; done
  keystroke o >/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do drag $((100 + i * 60)) 400 $((200 + i * 60)) 600 >/dev/null; done
  keystroke a >/dev/null
  for i in 1 2 3 4 5 6 7 8 9 10; do drag $((100 + i * 60)) 700 $((250 + i * 60)) 900 >/dev/null; done
  keystroke x >/dev/null
  drag 200 150 1400 800 >/dev/null
  drag 1000 900 2400 1500 >/dev/null
  keystroke c >/dev/null
  drag 0 0 50 50 >/dev/null
  drag 3008 1692 2900 1650 >/dev/null
  keystroke enter >/dev/null
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N copy" >/dev/null
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/tools/six-k.png" >/dev/null
  SIX_K="$("$INSPECT" info "$RUN_ROOT/tools/six-k.png")"
  expect_equal "the 6K Export is the cropped size, 5700 x 3200 pixels" "5700x3200" "$(png_field "$SIX_K" width)x$(png_field "$SIX_K" height)"
  close_editor
fi
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null

# 15. Memory: drawing and undoing Redactions and crops on a large Capture leaves the helper flat, and
#     Capture, Redact, Crop, Copy cycles leave the menu bar app flat with no helper behind.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
if open_editor; then
  keystroke x >/dev/null
  for _ in 1 2; do drag 100 100 2000 1200 >/dev/null; keystroke undo >/dev/null; done  # warm up
  sleep 1
  REDACT_BASELINE="$(footprint_mb "$HELPER_PID")"
  for _ in 1 2 3 4 5 6 7 8; do
    drag 100 100 2000 1200 >/dev/null
    keystroke undo >/dev/null
  done
  keystroke c >/dev/null
  for _ in 1 2 3 4; do
    drag 0 0 300 200 >/dev/null
    drag 2560 1440 2000 1000 >/dev/null
    keystroke enter >/dev/null
    keystroke undo >/dev/null
    keystroke c >/dev/null
  done
  keystroke v >/dev/null
  # Five Redactions of almost the whole Capture at once (each preview is tens of megabytes of
  # pixels): the Editor holds them while they are on the canvas and gives them all back.
  keystroke x >/dev/null
  for i in 1 2 3 4 5; do drag $((50 + i * 20)) 50 $((2000 + i * 20)) 1200 >/dev/null; done
  sleep 1
  REDACT_HELD="$(footprint_mb "$HELPER_PID")"
  # Each Redaction covers about 1900 x 1150 points, 3800 x 2300 pixels at 2x.
  REDACT_FIVE_MB="$(awk -v p="$(pixels_mb 3800 2300)" 'BEGIN { printf "%.1f", 5 * p }')"
  expect_peak_proportionate "five large Redactions on a 2560 x 1440 point Capture" "$REDACT_HELD" "$REDACT_BASELINE" "$REDACT_FIVE_MB"
  for _ in 1 2 3 4 5; do keystroke undo >/dev/null; done
  keystroke v >/dev/null
  sleep 1
  expect_memory_returns "the Editor's memory over Redaction and crop cycles on a large Capture" "$HELPER_PID" "$REDACT_BASELINE" "$(pixels_mb 5120 2880)"
  close_editor
fi
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null
REDACT_APP_BASELINE="$(footprint_mb "$APP_PID")"
for _ in 1 2 3; do
  if open_editor; then
    keystroke x >/dev/null; drag 40 30 140 90 >/dev/null
    keystroke c >/dev/null; drag 0 0 20 15 >/dev/null; drag 301 187 250 150 >/dev/null; keystroke enter >/dev/null
    copy_closes_editor
  fi
done
expect_memory_returns "the menu bar app's memory is flat over Capture, Redact, Crop, Copy cycles" "$APP_PID" "$REDACT_APP_BASELINE"
if [[ -z "$(helper_pid)" ]]; then pass "no helper process is left after the Redaction and crop cycles"; else fail "a helper is still running after the Redaction and crop cycles"; fi
send "$APP_SOCK" pasteboard-clear >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null

# 16. Save and the drag-out file go through the same pipeline: the saved PNG and the dragged file are the
#     cropped, redacted Export, pixel for pixel.
SAVE_DIR="$RUN_ROOT/save"
mkdir -p "$SAVE_DIR"
send "$APP_SOCK" "defaults-set closeEditorAfterSave false" >/dev/null
if open_editor; then
  keystroke x >/dev/null
  drag 60 40 140 100 >/dev/null
  keystroke c >/dev/null
  drag 0 0 20.15 15.35 >/dev/null
  drag 301 187 170.65 120.8 >/dev/null
  keystroke enter >/dev/null
  # The drag-out thumbnail is the Export too: 96 pixels on its long side, the crop's proportions
  # (301 x 211), and the whole Capture's (602 x 374: 96 x 60) once the crop is undone.
  thumbnail_size() { send "$EDITOR_SOCK" "editor-drag-thumbnail $EDITOR_N" | sed -n 's/.*thumbnail=\([0-9x]*\).*/\1/p'; }
  thumbnail_is() { [[ "$(thumbnail_size)" == "$1" ]]; }
  if wait_until 10 thumbnail_is 96x67; then pass "the drag-out thumbnail follows the crop: 96 x 67 pixels"; else fail "the drag-out thumbnail is $(thumbnail_size), expected 96x67 for the crop"; fi
  keystroke undo >/dev/null
  if wait_until 10 thumbnail_is 96x60; then pass "and goes back to the whole Capture's proportions after Undo (96 x 60)"; else fail "the drag-out thumbnail is $(thumbnail_size) after Undo, expected 96x60"; fi
  keystroke redo >/dev/null
  wait_until 10 thumbnail_is 96x67 >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  saved_name() { ls "$SAVE_DIR" 2>/dev/null | grep '^snapit-.*\.png$' | head -1; }
  save_done() { [[ "$(send "$APP_SOCK" save-pending)" == "0" && -n "$(saved_name)" ]]; }
  if wait_until 10 save_done; then
    SAVED="$SAVE_DIR/$(saved_name)"
    expect_redacted "the saved PNG is the cropped Export with the Redaction pixelated" "$SAVED" 301 211 $W $H 40 31 80 49 240 169 "$(redaction_block 160 120 2)"
    expect_equal "the saved PNG is the crop's size" "301x211" "$(png_field "$("$INSPECT" info "$SAVED")" width)x$(png_field "$("$INSPECT" info "$SAVED")" height)"
  else
    fail "the Save did not finish"
  fi
  DRAGGED="$(send_slow "$EDITOR_SOCK" "editor-drag-file $EDITOR_N")"
  if [[ "$DRAGGED" == ok\ * ]]; then
    expect_redacted "the file dragged out is the cropped Export with the Redaction pixelated" "${DRAGGED#ok }" 301 211 $W $H 40 31 80 49 240 169 "$(redaction_block 160 120 2)"
  else
    fail "the drag-out file failed: $DRAGGED"
  fi
  close_editor
fi
find "$SAVE_DIR" -mindepth 1 -delete 2>/dev/null
rm -rf "$RUN_ROOT/drag-out"  # the file dragged out above, so the next flow starts with none
send "$APP_SOCK" "defaults-set closeEditorAfterSave true" >/dev/null
