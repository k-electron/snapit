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
# document_field <key>: one line of `editor-document` (`selected=`, `undo-steps=`, ...).
document_field() { send "$EDITOR_SOCK" "editor-document $EDITOR_N" | sed -n "s/^$1=//p"; }
annotation_count() { send "$EDITOR_SOCK" "editor-document $EDITOR_N" | grep -c '^annotation '; }

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
# pixel <png> <x> <y>: "r,g,b".
pixel() { "$INSPECT" pixel "$@"; }
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
# expect_selected <description>, expect_nothing_selected <description>
expect_selected() {
  if [[ "$(document_field selected)" != "none" ]]; then pass "$1"; else fail "$1 (nothing is selected)"; fi
}
expect_nothing_selected() { expect_equal "$1" "none" "$(document_field selected)"; }
