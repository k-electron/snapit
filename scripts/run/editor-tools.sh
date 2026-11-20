# Helpers for flows that draw in the Editor with synthetic pointer input and compare the
# Export's pixels. Sourced by the flow, after lib.sh and editor.sh; it uses EDITOR_SOCK,
# APP_SOCK, EDITOR_N, RUN_ROOT and INSPECT.
# Points are image points: the Capture's own coordinates, origin at the top left. A fixture at
# scale 2 has twice as many pixels as points.
# shellcheck shell=bash

# drag <x1> <y1> <x2> <y2>: press, drag and release the pointer on the canvas.
drag() { send "$EDITOR_SOCK" "editor-drag $EDITOR_N $1 $2 $3 $4"; }
# click <x> <y>
click() {
  send "$EDITOR_SOCK" "editor-mouse $EDITOR_N down $1 $2" >/dev/null
  send "$EDITOR_SOCK" "editor-mouse $EDITOR_N up $1 $2"
}
# keystroke <undo|redo|delete|a character>: the key press, as the window receives it.
keystroke() { send "$EDITOR_SOCK" "editor-keystroke $EDITOR_N $1"; }
# style <fill|width|color> <value>
style() { send "$EDITOR_SOCK" "editor-style $EDITOR_N $1 $2"; }

# document_field <key>: one line of `editor-document` (`zoom=`, `revision=`, ...).
document_field() { send "$EDITOR_SOCK" "editor-document $EDITOR_N" | sed -n "s/^$1=//p"; }

# export_png <name>: Copy in the open Editor and write the PNG on the pasteboard to
# $RUN_ROOT/tools/<name>.png; prints the path. (Close after Copy must be off.)
export_png() {
  mkdir -p "$RUN_ROOT/tools"
  send "$APP_SOCK" pasteboard-clear >/dev/null
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N copy" >/dev/null
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/tools/$1.png" >/dev/null
  echo "$RUN_ROOT/tools/$1.png"
}

# fixture_diff <png> <pixel width> <pixel height> [<x0> <y0> <x1> <y1>]: `png-inspect diff-fixture`.
fixture_diff() { "$INSPECT" diff-fixture "$@"; }
# changed_pixels <png> <pixel width> <pixel height>: how many pixels differ from the fixture.
changed_pixels() { "$INSPECT" diff-fixture "$1" "$2" "$3" | sed -n 's/^changed=//p'; }
# pixel <png> <x> <y>: "r,g,b" in the PNG's own color space.
pixel() { "$INSPECT" raw-pixel "$@"; }
# channel <"r,g,b"> <0|1|2>
channel() { echo "$1" | cut -d, -f"$(($2 + 1))"; }
# expect_unchanged <description> <png> <pixel width> <pixel height>: no pixel differs from the fixture.
expect_unchanged() { expect_equal "$1" "changed=0" "$("$INSPECT" diff-fixture "$2" "$3" "$4" | grep '^changed=')"; }
# expect_red <description> <"r,g,b">: the default Annotation color (a red), whatever the color space.
expect_red() {
  local r g b
  r="$(channel "$2" 0)"; g="$(channel "$2" 1)"; b="$(channel "$2" 2)"
  if ((r >= 200 && g <= 110 && b <= 110)); then pass "$1"; else fail "$1 (got $2)"; fi
}
# expect_blue <description> <"r,g,b">, expect_green <description> <"r,g,b">
expect_blue() {
  if (($(channel "$2" 2) >= 200 && $(channel "$2" 0) <= 100)); then pass "$1"; else fail "$1 (got $2)"; fi
}
expect_green() {
  if (($(channel "$2" 1) >= 230 && $(channel "$2" 0) <= 150 && $(channel "$2" 2) <= 150)); then pass "$1"; else fail "$1 (got $2)"; fi
}
# fixture_pixel <x> <y> <pixel width> <pixel height>: "r,g,b" the fixture has there, from the formula in docs/testing.md.
fixture_pixel() {
  local x="$1" y="$2" w="$3" h="$4" b=200
  if (((x / 8 + y / 8) % 2 == 0)); then b=40; fi
  echo "$((x * 255 / (w - 1))),$((y * 255 / (h - 1))),$b"
}
# expect_near <description> <"r,g,b" expected> <"r,g,b" actual>: every channel within 1 (sRGB at 1x).
expect_near() {
  local i want got
  for i in 0 1 2; do
    want="$(channel "$2" "$i")"; got="$(channel "$3" "$i")"
    if ((got < want - 1 || got > want + 1)); then fail "$1 (expected $2, got $3)"; return; fi
  done
  pass "$1"
}

# item_enabled <item id>: whether a toolbar item is enabled in the open Editor.
item_enabled() { [[ "$(send "$EDITOR_SOCK" "editor-enabled $EDITOR_N $1")" == "yes" ]]; }
expect_enabled() { if item_enabled "$2"; then pass "$1"; else fail "$1 ('$2' is disabled)"; fi; }
expect_disabled() { if item_enabled "$2"; then fail "$1 ('$2' is enabled)"; else pass "$1"; fi; }
# What Select picked is what Delete Annotation would delete: it is enabled with a selection.
expect_selected() { expect_enabled "$1" delete-annotation; }
expect_nothing_selected() { expect_disabled "$1" delete-annotation; }

# preview_png: the canvas's own layers rendered at the Capture's pixel size; prints the PNG's path.
preview_png() { send "$EDITOR_SOCK" "editor-preview $EDITOR_N" | sed -n 's/^ok //p'; }
# preview_overlay_png: the same with the selection's and the crop rectangle's outline, shade and handles.
preview_overlay_png() { send "$EDITOR_SOCK" "editor-preview $EDITOR_N overlay" | sed -n 's/^ok //p'; }
# background_editor <N>: makes another Editor's window key, so Editor N is a background Editor.
background_editor() { send "$EDITOR_SOCK" "editor-background $1" >/dev/null; }
# click_on <N> tool|item <id> | canvas <x> <y>: a click (through the window's sendEvent) in Editor N.
click_on() { local n="$1"; shift; send "$EDITOR_SOCK" "editor-click $n $*"; }
