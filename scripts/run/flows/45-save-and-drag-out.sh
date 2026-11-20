# Flow: Save and drag-out. ⌘S writes a PNG into the Save location (a temp folder in test mode)
# named from the Capture's time, with -2, -3 on a clash; the menu bar app encodes it, so it lands
# even when the helper has quit; a Save location that can't be written to keeps the Editor open;
# "Export at standard resolution (1x)" averages a Retina Export down; the Editor's thumbnail
# offers a file with the Export name. Every file is checked with the independent PNG checker.
# Sourced by scripts/check-run.sh.
# shellcheck shell=bash

SAVE="$RUN_ROOT/save"
saved_pngs() { ls -A "$SAVE" 2>/dev/null | grep '^snapit-.*\.png$' | LC_ALL=C sort; }
save_dir_entries() { ls -A "$SAVE" 2>/dev/null | wc -l | tr -d ' '; }
file_exists() { [[ -f "$1" ]]; }
save_idle() { [[ "$(send "$APP_SOCK" save-pending)" == "0" ]]; }
file_size() { stat -f '%z' "$1"; }
# A setting is changed while no Editor helper runs, by the menu bar app: a helper reads settings
# when it starts, and the next Capture starts a new one. (In the test store's file a running
# helper neither picks up a key another process wrote nor can override it; the product's
# Settings window writes inside the helper.)
no_helper() { [[ -z "$(helper_pid)" ]]; }
set_default() {
  wait_until 10 no_helper
  send "$APP_SOCK" "defaults-set $1 $2" >/dev/null
}
clear_save_folder() { chmod 700 "$SAVE" 2>/dev/null; find "$SAVE" -mindepth 1 -delete 2>/dev/null; }

# check_png <label> <file> <w> <h> <phys> <profile sha> <how: verify-fixture|scaled:<factor>> [<source w> <source h>]
# The file's size, dpi, ICC profile and every pixel, read back by png-inspect. `scaled:<n>` says the
# file is the fixture of <source w> x <source h> pixels averaged down by the whole factor n.
check_png() {
  local label="$1" file="$2" w="$3" h="$4" phys="$5" sha="$6" how="$7" sw="${8:-$3}" sh="${9:-$4}" info verify
  info="$("$INSPECT" info "$file")"
  if [[ "$how" == scaled:* ]]; then verify="$("$INSPECT" verify-fixture-scaled "$file" "$sw" "$sh" "${how#scaled:}")"; else verify="$("$INSPECT" verify-fixture "$file" "$sw" "$sh")"; fi
  expect_equal "$label: pixel size" "${w}x${h}" "$(png_field "$info" width)x$(png_field "$info" height)"
  expect_equal "$label: pHYs records $phys pixels per metre (dpi: $((phys * 254 / 10000)))" "$phys,$phys,1" "$(png_field "$info" phys)"
  expect_equal "$label: the display's ICC profile is embedded byte for byte" "$sha" "$(png_field "$info" icc_sha256)"
  expect_equal "$label: every pixel is right" "mismatches=0" "$(printf '%s\n' "$verify" | grep '^mismatches=')"
}
# The mode a file made with 0644 gets under this shell's umask (the run's processes share it).
FILE_MODE="$(printf '%o' $((8#644 & ~8#$(umask))))"

mkdir -p "$SAVE"
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
set_default closeEditorAfterSave true
set_default exportStandardResolution false
clear_save_folder

# 1. ⌘S writes snapit-YYYYMMDD-HHMMSS.png from the Capture's time, then the Editor closes (the
#    default) and the helper quits: the menu bar app finishes the file on its own.
BEFORE="$(date +%Y%m%d-%H%M%S)"
if capture_into_editor "menu-click capture.screen"; then
  AFTER="$(date +%Y%m%d-%H%M%S)"
  NAME="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  TOOLBAR="$(send "$EDITOR_SOCK" "editor-toolbar $EDITOR_N")"
  expect_in_order "the Export pill has the drag-out thumbnail, Copy and Save, in that order" "$(printf '%s\n' "$TOOLBAR" | grep ' export ' | awk '{ print $2 }')" "drag-out" "copy" "save"
  expect_contains "Save has its tooltip" "item save export Save (⌘S)" "$TOOLBAR"
  expect_contains "the drag-out thumbnail has its tooltip" "item drag-out export Drag the Capture out as a file" "$TOOLBAR"
  MENUS="$(send "$EDITOR_SOCK" main-menu)"
  expect_in_order "the helper's File menu has Save" "$(menu_items "$MENUS" File)" "Save"
  if [[ "$NAME" =~ ^snapit-[0-9]{8}-[0-9]{6}\.png$ ]]; then pass "the Export name is snapit-YYYYMMDD-HHMMSS.png"; else fail "the Export name '$NAME' does not match snapit-YYYYMMDD-HHMMSS.png"; fi
  BASE="${NAME%.png}"
  if [[ "$BASE" > "snapit-$BEFORE" || "$BASE" == "snapit-$BEFORE" ]] && [[ "$BASE" < "snapit-$AFTER" || "$BASE" == "snapit-$AFTER" ]]; then
    pass "the name's time is the time of the Capture ($BEFORE to $AFTER)"
  else
    fail "the name '$NAME' is not from the Capture's time ($BEFORE to $AFTER)"
  fi
  expect_equal "nothing is saved before the user presses Save" "0" "$(save_dir_entries)"

  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "⌘S saves and the Editor closes (the helper quits)"; else fail "the helper is still running after ⌘S"; fi
  if wait_until 15 file_exists "$SAVE/$NAME"; then pass "the Save writes $NAME into the Save location"; else fail "no $NAME in the Save location"; fi
  wait_until 15 save_idle
  expect_equal "the Save location holds only that file (no partial file is left)" "1" "$(save_dir_entries)"
  check_png "Save at 2x" "$SAVE/$NAME" 602 374 5669 "$P3_SHA" verify-fixture
  expect_equal "the Saved file's mode is 0644 less the umask ($FILE_MODE)" "$FILE_MODE" "$(stat -f '%Lp' "$SAVE/$NAME")"
  expect_equal "Save leaves the clipboard alone" "" "$(send "$APP_SOCK" pasteboard-types)"
  expect_equal "the shared export file is gone once the Save is written" "" "$(ls -A "$RUN_ROOT/exports" 2>/dev/null)"
fi

# 2. A second Capture in the same second, and Saving more than once, never overwrites: -2, -3.
#    With "Close the Editor after Save" off the Editor stays open and can Save again.
clear_save_folder
set_default closeEditorAfterSave false
if capture_into_editor "press-shortcut capture-screen"; then
  NAME="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  BASE="${NAME%.png}"
  for _ in 1 2 3; do send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N save" >/dev/null; done
  wait_until 15 save_idle
  expect_in_order "a clash adds -2 and -3 before the extension" "$(saved_pngs)" "$BASE-2.png" "$BASE-3.png" "$NAME"
  expect_equal "three Saves wrote three files and nothing else" "3" "$(save_dir_entries)"
  expect_equal "the Editor stays open after Save when close after Save is off" "$EDITOR_N" "$(open_editors | tail -1)"
  expect_equal "the helper is still running" "$HELPER_PID" "$(helper_pid)"
  expect_equal "the Save was handed to the menu bar app" "handed-over" "$(send "$EDITOR_SOCK" "editor-save-outcome $EDITOR_N")"
  for file in "$NAME" "$BASE-2.png" "$BASE-3.png"; do
    check_png "Save of $file" "$SAVE/$file" 602 374 5669 "$P3_SHA" verify-fixture
  done

  # 3. When the Save location can't be written to, the Editor stays open and says why.
  chmod 500 "$SAVE"
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N save" >/dev/null
  OUTCOME="$(send "$EDITOR_SOCK" "editor-save-outcome $EDITOR_N")"
  expect_contains "a Save location that can't be written to is reported as a failure the folder Permission guide can use" "failed folder-not-writable 13 $SAVE" "$OUTCOME"
  expect_equal "the Editor stays open when the writability check fails" "$EDITOR_N" "$(open_editors | tail -1)"
  expect_equal "the helper keeps running" "$HELPER_PID" "$(helper_pid)"
  expect_equal "nothing was written and no partial file is left" "3" "$(save_dir_entries)"
  expect_equal "the failed Save leaves no shared export file behind" "" "$(ls -A "$RUN_ROOT/exports" 2>/dev/null)"
  expect_equal "no Save is left running after the failure" "0" "$(send "$APP_SOCK" save-pending)"
  chmod 700 "$SAVE"
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N save" >/dev/null
  wait_until 15 save_idle
  expect_equal "after the location is fixed the same Editor Saves (-4)" "$BASE-4.png" "$(saved_pngs | grep -- '-4' )"

  # 4. Drag-out: the thumbnail Fast-encodes a file with the Export name into the private cache.
  if wait_until 10 bash -c "[[ \"\$(printf 'editor-drag-thumbnail $EDITOR_N\n' | nc -U -w 2 '$EDITOR_SOCK')\" == *'thumbnail=96x60'* ]]"; then
    pass "the thumbnail is made by the engine: 96 x 60 pixels for a 602 x 374 Capture"
  else
    fail "the drag-out thumbnail: $(send "$EDITOR_SOCK" "editor-drag-thumbnail $EDITOR_N")"
  fi
  expect_contains "the thumbnail view is 48 x 32 points" "view=48x32" "$(send "$EDITOR_SOCK" "editor-drag-thumbnail $EDITOR_N")"
  DRAG="$(send_slow "$EDITOR_SOCK" "editor-drag-file $EDITOR_N")"
  DRAG_FILE="${DRAG#ok }"
  expect_equal "the drag-out file is in the private cache, under the Export name" "$RUN_ROOT/drag-out/$EDITOR_N/$NAME" "$DRAG_FILE"
  check_png "drag-out file at 2x" "$DRAG_FILE" 602 374 5669 "$P3_SHA" verify-fixture
  expect_equal "the drag-out folder is private to the user (mode 700)" "700" "$(stat -f '%Lp' "$RUN_ROOT/drag-out/$EDITOR_N")"
  expect_equal "the drag-out file's mode is the same as a Saved file's ($FILE_MODE)" "$FILE_MODE" "$(stat -f '%Lp' "$DRAG_FILE")"
  DRAG_INODE="$(stat -f '%i' "$DRAG_FILE")"
  send_slow "$EDITOR_SOCK" "editor-drag-file $EDITOR_N" >/dev/null
  if [[ "$(stat -f '%i' "$DRAG_FILE")" != "$DRAG_INODE" ]]; then pass "a second drag writes a new file and renames it into place (a reader of the first keeps its own)"; else fail "a second drag rewrote the first drag's file in place"; fi
  expect_equal "no partial file is left in the drag-out folder" "1" "$(ls -A "$RUN_ROOT/drag-out/$EDITOR_N" | wc -l | tr -d ' ')"
  expect_equal "dragging writes nothing into the Save location" "4" "$(save_dir_entries)"
  if (($(file_size "$SAVE/$NAME") < $(file_size "$DRAG_FILE"))); then
    pass "Save is Balanced and drag-out is Fast (the Saved file is smaller: $(file_size "$SAVE/$NAME") < $(file_size "$DRAG_FILE") bytes)"
  else
    fail "the Saved file ($(file_size "$SAVE/$NAME") bytes) is not smaller than the Fast drag-out file ($(file_size "$DRAG_FILE") bytes)"
  fi
  expect_equal "the clipboard is untouched by drag-out" "" "$(send "$APP_SOCK" pasteboard-types)"

  # The drag-out file stays after its Editor closes: the app that took the drop may still be reading it.
  OLD_DRAG_N="$EDITOR_N"
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Esc closes the Editor"; else fail "the helper is still running after Esc"; fi
  expect_equal "the drag-out folder is still there after the Editor closed" "$OLD_DRAG_N" "$(ls -A "$RUN_ROOT/drag-out" 2>/dev/null)"
  # Folders older than ten minutes go when the next Capture opens.
  touch -t 202001010000 "$RUN_ROOT/drag-out/$OLD_DRAG_N"
fi

# 5. Export at standard resolution (1x): the engine averages the Retina Capture down in the same
#    pass as the encode, for Save, Copy and drag-out alike, and tags it 72 dpi.
set_default exportStandardResolution true
set_default closeEditorAfterCopy false
clear_save_folder
if capture_into_editor "menu-click capture.screen"; then
  NAME="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  if [[ ! -e "$RUN_ROOT/drag-out/$OLD_DRAG_N" ]]; then pass "opening a Capture removes the drag-out folder that is older than ten minutes"; else fail "the stale drag-out folder is still there"; fi
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N save" >/dev/null
  wait_until 15 save_idle
  check_png "1x Save of a 2x Capture" "$SAVE/$NAME" 301 187 2835 "$P3_SHA" scaled:2 602 374
  send "$APP_SOCK" pasteboard-clear >/dev/null
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N copy" >/dev/null
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/clip.png" >/dev/null
  check_png "1x Copy of a 2x Capture" "$RUN_ROOT/clip.png" 301 187 2835 "$P3_SHA" scaled:2 602 374
  rm -f "$RUN_ROOT/clip.png"
  send "$APP_SOCK" pasteboard-clear >/dev/null
  DRAG="$(send_slow "$EDITOR_SOCK" "editor-drag-file $EDITOR_N")"
  check_png "1x drag-out of a 2x Capture" "${DRAG#ok }" 301 187 2835 "$P3_SHA" scaled:2 602 374
  send "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
fi
set_default exportStandardResolution false
set_default closeEditorAfterCopy true

# 6. A 1x Capture with the 1x setting on is not changed, and says 72 dpi.
set_default exportStandardResolution true
set_default closeEditorAfterSave true
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
clear_save_folder
# A crash or force-quit mid-Save can leave a hidden partial file; the next Save removes exactly those
# (`.snapit-<UUID>.partial`) and nothing else.
STALE_PARTIAL=".snapit-$(uuidgen).partial"
: >"$SAVE/$STALE_PARTIAL"
: >"$SAVE/.snapit-notes.partial"
: >"$SAVE/.snapit-$(uuidgen).txt"
if capture_into_editor "menu-click capture.screen"; then
  NAME="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  wait_until 10 gone "$HELPER_PID"
  wait_until 15 file_exists "$SAVE/$NAME"
  wait_until 15 save_idle
  check_png "1x setting on a 1x Capture" "$SAVE/$NAME" 301 187 2835 "$SRGB_SHA" verify-fixture
  if [[ ! -e "$SAVE/$STALE_PARTIAL" ]]; then pass "a Save removes the partial file an earlier run left in the Save location"; else fail "the abandoned partial file is still in the Save location"; fi
  expect_equal "files that are not snapit partials are left alone" "2" "$(ls -A "$SAVE" | grep -c '^\.snapit-')"
fi
# An odd size: 101 x 61 points at 3x is 303 x 183 pixels, 101 x 61 at 1x.
send "$APP_SOCK" "fixture-display 3 101 61" >/dev/null
clear_save_folder
if capture_into_editor "menu-click capture.screen"; then
  NAME="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  wait_until 10 gone "$HELPER_PID"
  wait_until 15 file_exists "$SAVE/$NAME"
  wait_until 15 save_idle
  check_png "1x Save of a 3x Capture with an odd size" "$SAVE/$NAME" 101 61 2835 "$P3_SHA" scaled:3 303 183
fi
set_default exportStandardResolution false
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null

# 7. The helper quits mid-Save: the menu bar app is told to hold its write, the Editor closes and
#    the helper goes, nothing is in the Save location yet, then the held Save finishes by itself.
clear_save_folder
set_default closeEditorAfterSave true
send "$APP_SOCK" save-hold >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  NAME="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "the helper quits while the Save is still being written"; else fail "the helper is still running"; fi
  expect_equal "the menu bar app is still writing the Save" "1" "$(send "$APP_SOCK" save-pending)"
  expect_equal "the Saved file does not exist yet" "0" "$(saved_pngs | wc -l | tr -d ' ')"
  expect_equal "the shared export file needs no cleanup: the menu bar app already holds it" "" "$(ls -A "$RUN_ROOT/exports" 2>/dev/null)"
  send "$APP_SOCK" save-release >/dev/null
  if wait_until 15 file_exists "$SAVE/$NAME"; then pass "the Balanced encode finishes after the helper has quit"; else fail "no $NAME after the helper quit"; fi
  wait_until 15 save_idle
  check_png "Save finished after the helper quit" "$SAVE/$NAME" 602 374 5669 "$P3_SHA" verify-fixture
  expect_equal "no partial file is left" "1" "$(save_dir_entries)"
fi
send "$APP_SOCK" save-release >/dev/null   # whatever happened above, later Saves are never held

# 8. Memory and CPU: five 5K Saves, each closing its Editor, leave the menu bar app where it was.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
clear_save_folder
big_save() {
  capture_into_editor "press-shortcut capture-screen" || return
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  wait_until 20 gone "$HELPER_PID"
  wait_until 30 save_idle
}
big_save   # warm up the allocator pools
sleep 1
SAVE_BASELINE="$(footprint_mb "$APP_PID")"
for _ in 1 2 3 4 5; do big_save; done
sleep 1
SAVE_AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$SAVE_AFTER" -v b="$SAVE_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory returns to baseline after five 5K Saves (${SAVE_BASELINE} MB before, ${SAVE_AFTER} MB after)"
else
  fail "memory grew from ${SAVE_BASELINE} MB to ${SAVE_AFTER} MB over five 5K Saves (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
fi
if awk -v a="$SAVE_AFTER" -v b="$AT_REST" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app is back near its at-rest footprint after the Saves (${AT_REST} MB at rest, ${SAVE_AFTER} MB after)"
else
  fail "the menu bar app is at ${SAVE_AFTER} MB after the Saves, ${AT_REST} MB at rest (limit +${FOOTPRINT_FROM_REST_MB_MAX} MB)"
fi
BIG_FILE="$(saved_pngs | head -1)"
BIG_INFO="$("$INSPECT" info "$SAVE/$BIG_FILE")"
expect_equal "a 5K Save has the full pixel size" "5120x2880" "$(png_field "$BIG_INFO" width)x$(png_field "$BIG_INFO" height)"
if [[ -z "$(helper_pid)" ]]; then pass "no helper process is left after the Saves"; else fail "an Editor helper is still running"; fi
expect_equal "no shared export file is left after the Saves" "" "$(ls -A "$RUN_ROOT/exports" 2>/dev/null)"
assert_idle_cpu "menu bar app after the Saves" "$APP_PID" 5
clear_save_folder
set_default closeEditorAfterSave true
send "$APP_SOCK" pasteboard-clear >/dev/null

# 9. Quit while a Save is still being written: snapit exits only after the file is written. A 7680 x 4320
#    pixel Capture (3x of 2560 x 1440 points) takes the Balanced encode long enough for Quit to arrive in
#    the middle of it. The run starts the menu bar app again afterwards, like flow 80 does.
send "$APP_SOCK" "fixture-display 3 2560 1440" >/dev/null
clear_save_folder
if capture_into_editor "menu-click capture.screen"; then
  NAME="$(send "$EDITOR_SOCK" "export-name $EDITOR_N")"
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N save" >/dev/null
  wait_until 20 gone "$HELPER_PID"
  expect_equal "the Save is still being written when Quit comes" "1" "$(send "$APP_SOCK" save-pending)"
  expect_equal "the Saved file does not exist yet" "0" "$(saved_pngs | wc -l | tr -d ' ')"
  send "$APP_SOCK" quit >/dev/null
  if wait_until 90 gone "$APP_PID"; then pass "Quit with a Save in progress still quits, once the Save is written"; else fail "snapit is still running 90 s after Quit with a Save in progress"; fi
  if file_exists "$SAVE/$NAME"; then
    pass "the Save finished before snapit quit"
    check_png "Save finished across Quit" "$SAVE/$NAME" 7680 4320 8504 "$P3_SHA" verify-fixture
  else
    fail "snapit quit without writing $NAME"
  fi
  expect_equal "no partial file is left behind by the Quit" "1" "$(save_dir_entries)"
  expect_equal "no shared export file is left behind by the Quit" "" "$(ls -A "$RUN_ROOT/exports" 2>/dev/null)"
  expect_equal "the drag-out folders go when snapit quits" "" "$(ls -A "$RUN_ROOT/drag-out" 2>/dev/null)"
fi
clear_save_folder
(nohup "$APP_EXE" >>"$RUN_ROOT/app.log" 2>&1 &)
if wait_until 15 answers "$APP_SOCK"; then pass "snapit starts again after the Quit"; else fail "snapit did not start again"; fi
APP_PID="$(pid_of "$APP_EXE")"
