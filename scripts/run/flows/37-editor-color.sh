# Flow: Annotation color and width. Preset swatches, the eyedropper (it reads the Capture's own pixel
# under the cursor's hot spot, at 1x and 2x, never an Annotation), the color wheel (the macOS color
# panel, replaced in test mode by a fixture; a drag in it is one Undo step), width presets, and the last
# color, width and text size remembered. Every control works on the first click of a background Editor.
# Expected colors come from the fixture formula in docs/testing.md, not from the app. Sourced by
# scripts/check-run.sh, after flow 36.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
send "$APP_SOCK" "defaults-set annotationTextSize 20" >/dev/null

# control <tooltip>: a click on one control (a swatch, a width) through the window, as a user's.
control() { send "$EDITOR_SOCK" "editor-click $EDITOR_N control ${1// /%20}"; }
# annotation_field <id> <field number of the `annotation` line>: 3 kind, 8 color, 9 width, 10 fill.
annotation_field() { send "$EDITOR_SOCK" "editor-document $EDITOR_N" | grep "^annotation $1 " | cut -d' ' -f"$2"; }
last_annotation() { send "$EDITOR_SOCK" "editor-document $EDITOR_N" | grep '^annotation ' | tail -1 | cut -d' ' -f2; }
undo_steps() { document_field undo-steps; }
picking() { send "$EDITOR_SOCK" "editor-text $EDITOR_N" | sed -n 's/^picking=//p'; }
default_of() { send "$APP_SOCK" "defaults-get $1"; }
# rgb_hex <r> <g> <b>: RRGGBB.
rgb_hex() { printf '%02x%02x%02x' "$1" "$2" "$3"; }

send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  W=301
  H=187
  # The controls: always there, enabled as soon as the Editor opens (Select, nothing selected).
  TOOLBAR="$(send "$EDITOR_SOCK" "editor-toolbar $EDITOR_N")"
  expect_in_order "the color, width and text size controls are in the options pill in order" \
    "$(printf '%s\n' "$TOOLBAR" | grep '^item [a-z-]* options ' | cut -d' ' -f2)" \
    annotation-color eyedropper color-wheel annotation-width text-size annotation-fill
  expect_enabled "the color swatches are enabled as soon as the Editor opens" annotation-color
  expect_enabled "the eyedropper is enabled as soon as the Editor opens" eyedropper
  expect_enabled "the color wheel is enabled as soon as the Editor opens" color-wheel
  expect_enabled "width is enabled with nothing selected: it sets the next Annotation's" annotation-width
  expect_enabled "text size is enabled with nothing selected" text-size
  expect_disabled "the fill control still waits for a Rectangle or an Oval" annotation-fill
  CONTROLS="$(send "$EDITOR_SOCK" "editor-controls $EDITOR_N")"
  for tooltip in Red Orange Yellow Green Blue Purple Black White "Eyedropper: pick a color from the Capture" \
    "Color wheel: choose any color" "Width: 3 pt" "Width: 5 pt" "Width: 8 pt" "Text size: 14 pt" "Text size: 20 pt" "Text size: 32 pt"; do
    expect_contains "'$tooltip' is a control with that tooltip" "control $tooltip " "$CONTROLS"
  done
  SOLID_X="$(printf '%s\n' "$CONTROLS" | grep '^control Solid fill ' | awk '{ print $(NF-1) }')"
  UNDO_X="$(printf '%s\n' "$CONTROLS" | grep '^control Undo ' | awk '{ print $(NF-1) }')"
  if ((SOLID_X + 20 < UNDO_X)); then pass "the options pill ends before the history pill begins (x $SOLID_X, $UNDO_X)"; else fail "the options pill runs into the history pill (x $SOLID_X, $UNDO_X)"; fi
  SWATCH_Y="$(printf '%s\n' "$CONTROLS" | grep '^control Red ' | awk '{ print $NF }')"
  BLUE_Y="$(printf '%s\n' "$CONTROLS" | grep '^control Blue ' | awk '{ print $NF }')"
  expect_equal "the swatches sit in one row" "$SWATCH_Y" "$BLUE_Y"

  # Swatches: one click sets the color for the next Annotation and for the selected one.
  expect_contains "a click on the Blue swatch is delivered" "ok" "$(control Blue)"
  expect_equal "the swatch's color is remembered" "0a84ff" "$(default_of annotationColor)"
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 40 30 120 90 >/dev/null
  expect_blue "the next Annotation is drawn in the swatch's color" "$(pixel "$(export_png swatch)" 80 60)"
  STEPS="$(undo_steps)"
  control Green >/dev/null
  expect_equal "a swatch recolors the selected Annotation" "34c759" "$(annotation_field "$(last_annotation)" 8)"
  expect_within "and the Export shows it, exactly in sRGB at 1x" 1 "52,199,89" "$(pixel "$(export_png recolored)" 80 60)"
  expect_equal "recoloring is one Undo step" "$((STEPS + 1))" "$(undo_steps)"
  keystroke undo >/dev/null
  expect_equal "one Undo puts the color back" "0a84ff" "$(annotation_field "$(last_annotation)" 8)"
  expect_equal "and the remembered color is the last one chosen" "34c759" "$(default_of annotationColor)"

  # Width presets set the selected Arrow's width and the next ones'.
  keystroke a >/dev/null
  drag 30 150 120 170 >/dev/null
  ARROW="$(last_annotation)"
  expect_equal "an Arrow is drawn at the remembered width" "5.0" "$(annotation_field "$ARROW" 9)"
  control "Width: 8 pt" >/dev/null
  expect_equal "a width preset changes the selected Arrow" "8.0" "$(annotation_field "$ARROW" 9)"
  expect_equal "and is remembered" "8" "$(default_of annotationWidth)"
  keystroke undo >/dev/null
  expect_equal "one Undo takes the width back" "5.0" "$(annotation_field "$ARROW" 9)"
  keystroke undo >/dev/null  # the Arrow
  keystroke undo >/dev/null  # the Rectangle

  # The eyedropper, at 1x: the pixel under the hot spot, in sRGB exactly. Pixel (7,100) is
  # R 5, G 137, B 40; the next pixel across a block edge, (8,100), is R 6, G 137, B 200.
  keystroke v >/dev/null
  expect_equal "the eyedropper button starts picking" "ok" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper")"
  expect_equal "the Editor is picking" "yes" "$(picking)"
  click 7.9 100.5 >/dev/null
  expect_equal "the click ends picking" "no" "$(picking)"
  expect_equal "the eyedropper took pixel (7,100) for a click at x 7.9, y 100.5 points" "$(rgb_hex 5 137 40)" "$(default_of annotationColor)"
  send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper" >/dev/null
  click 8.0 100.5 >/dev/null
  expect_equal "a click at x 8.0 takes the next pixel, (8,100)" "$(rgb_hex 6 137 200)" "$(default_of annotationColor)"
  send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper" >/dev/null
  click 7.99 100.99 >/dev/null
  expect_equal "the pixel is the one that holds the point, not the nearest" "$(rgb_hex 5 137 40)" "$(default_of annotationColor)"
  # Drawn with that color, the Export shows the Capture's own pixel.
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 200 20 260 60 >/dev/null
  expect_near "a Rectangle in the picked color is the picked pixel in the Export" "5,137,40" "$(pixel "$(export_png picked)" 230 40)"

  # It samples the Capture, never an Annotation over it.
  style color ff3b30 >/dev/null
  drag 0 90 60 110 >/dev/null  # solid red over pixel (7,100)
  keystroke v >/dev/null
  click 280 170 >/dev/null
  send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper" >/dev/null
  click 7.9 100.5 >/dev/null
  expect_equal "the eyedropper reads the Capture under an Annotation, not the Annotation" "$(rgb_hex 5 137 40)" "$(default_of annotationColor)"
  # A click outside the Capture, and Esc, do not pick.
  style color ff3b30 >/dev/null
  send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper" >/dev/null
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  expect_equal "Esc ends picking" "no" "$(picking)"
  expect_contains "and leaves the Editor open" "$EDITOR_N" "$(open_editors)"
  expect_equal "and the color unchanged" "ff3b30" "$(default_of annotationColor)"
  send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper" >/dev/null
  keystroke r >/dev/null
  expect_equal "picking another tool ends picking" "no" "$(picking)"

  # The color wheel: a color panel; a drag in it is one Undo step.
  keystroke v >/dev/null
  click 230 40 >/dev/null
  expect_selected "a Rectangle is selected"
  RECT="$(send "$EDITOR_SOCK" "editor-document $EDITOR_N" | sed -n 's/^selected=//p')"
  expect_equal "the color wheel button opens the panel" "ok" "$(send "$EDITOR_SOCK" "editor-press $EDITOR_N color-wheel")"
  expect_contains "the panel is showing the Annotation color" "shown=yes color=$(annotation_field "$RECT" 8)" "$(send "$EDITOR_SOCK" "editor-color-panel $EDITOR_N state")"
  STEPS="$(undo_steps)"
  BEFORE="$(annotation_field "$RECT" 8)"
  send "$EDITOR_SOCK" "editor-color-panel $EDITOR_N choose 00ff00" >/dev/null
  expect_equal "a color typed into the panel recolors the selected Annotation" "00ff00" "$(annotation_field "$RECT" 8)"
  expect_equal "as one Undo step" "$((STEPS + 1))" "$(undo_steps)"
  expect_equal "and is remembered" "00ff00" "$(default_of annotationColor)"
  send "$EDITOR_SOCK" "editor-color-panel $EDITOR_N drag 112233 445566 778899" >/dev/null
  expect_equal "a drag across the panel leaves its last color" "778899" "$(annotation_field "$RECT" 8)"
  expect_equal "and the whole drag is one Undo step" "$((STEPS + 2))" "$(undo_steps)"
  keystroke undo >/dev/null
  expect_equal "one Undo takes the whole drag back, not a step of it" "00ff00" "$(annotation_field "$RECT" 8)"
  keystroke undo >/dev/null
  expect_equal "the next Undo takes back the typed color" "$BEFORE" "$(annotation_field "$RECT" 8)"
  keystroke redo >/dev/null
  keystroke redo >/dev/null
  # No Undo bracket is left open: the next drawing is a step of its own.
  STEPS="$(undo_steps)"
  keystroke r >/dev/null
  drag 150 120 200 160 >/dev/null
  expect_equal "an Annotation drawn after the drag is its own Undo step" "$((STEPS + 1))" "$(undo_steps)"
  keystroke undo >/dev/null
  expect_equal "and Undo takes only it back" "778899" "$(annotation_field "$RECT" 8)"

  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi

# The eyedropper at 2x: a Display P3 Capture with twice as many pixels as points. Pixels (303,184) and
# (304,184) are either side of a block edge: R 128, G 125, B 40 and R 128, G 125, B 200.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  W=602
  H=374
  send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper" >/dev/null
  click 151.75 92.25 >/dev/null
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 20 20 80 60 >/dev/null
  expect_within "at 2x a click at x 151.75 takes pixel 303: the Export shows the Capture's own pixel" 3 "128,125,40" "$(pixel "$(export_png eye-2x-a)" 80 80)"
  keystroke v >/dev/null
  click 280 170 >/dev/null
  send "$EDITOR_SOCK" "editor-press $EDITOR_N eyedropper" >/dev/null
  click 152.0 92.25 >/dev/null
  keystroke r >/dev/null
  drag 100 20 160 60 >/dev/null
  expect_within "at 2x a click at x 152.0 takes pixel 304, across the block edge" 3 "128,125,200" "$(pixel "$(export_png eye-2x-b)" 240 80)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi

# The first click on a background Editor works on every control.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
send "$APP_SOCK" "defaults-set annotationTextSize 20" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  FIRST_N="$EDITOR_N"
  if capture_into_editor "menu-click capture.screen"; then
    SECOND_N="$EDITOR_N"
    EDITOR_N="$FIRST_N"
    background_editor "$FIRST_N"
    expect_contains "a click on a swatch in a background Editor is not lost" "key-before=no" "$(control Green)"
    expect_equal "and it chose the color" "34c759" "$(default_of annotationColor)"
    background_editor "$FIRST_N"
    control "Width: 8 pt" >/dev/null
    expect_equal "the first click on a width tile works in a background Editor" "8" "$(default_of annotationWidth)"
    background_editor "$FIRST_N"
    control "Text size: 32 pt" >/dev/null
    expect_equal "the first click on a text size tile works" "32" "$(default_of annotationTextSize)"
    background_editor "$FIRST_N"
    click_on "$FIRST_N" item eyedropper >/dev/null
    expect_equal "the first click on the eyedropper starts picking" "yes" "$(picking)"
    background_editor "$FIRST_N"
    click_on "$FIRST_N" item color-wheel >/dev/null
    expect_contains "the first click on the color wheel opens the panel" "shown=yes" "$(send "$EDITOR_SOCK" "editor-color-panel $FIRST_N state")"
    # The panel serves the Editor that opened it: when that closes, so does the panel.
    send "$EDITOR_SOCK" "editor-key $FIRST_N escape" >/dev/null
    send "$EDITOR_SOCK" "editor-key $FIRST_N escape" >/dev/null
    expect_contains "the color panel closes with its Editor" "shown=no" "$(send "$EDITOR_SOCK" "editor-color-panel $SECOND_N state")"
    send "$EDITOR_SOCK" "editor-key $SECOND_N escape" >/dev/null
    wait_until 10 gone "$HELPER_PID"
  fi
fi

# What was chosen last is where the next Editor starts.
if capture_into_editor "menu-click capture.screen"; then
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 40 30 120 90 >/dev/null
  expect_within "a new Editor starts with the last color" 1 "52,199,89" "$(pixel "$(export_png remembered-color)" 80 60)"
  keystroke t >/dev/null
  click 150 120 >/dev/null
  send "$EDITOR_SOCK" "editor-type $EDITOR_N A" >/dev/null
  click 280 170 >/dev/null
  expect_contains "and the last text size" "text " "$(send "$EDITOR_SOCK" "editor-text $EDITOR_N")"
  expect_equal "the Text is 32 points" "32" "$(send "$EDITOR_SOCK" "editor-text $EDITOR_N" | grep '^text ' | cut -d' ' -f3)"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
send "$APP_SOCK" "defaults-set annotationTextSize 20" >/dev/null
