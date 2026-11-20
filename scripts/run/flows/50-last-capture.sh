# Flow: the Last Capture store and Reopen Last Capture. The most recent Capture is kept in the
# private `captures` folder (mode 0700): its raw pixel file, written when the Capture is taken,
# and a small state file the Last Capture's Editor writes about half a second after each change
# and when it closes. Reopen Last Capture brings it back with its Annotations, crop and Undo
# history; Delete Capture, a new Capture and quitting remove only snapit's own files, then the
# folder. The run reads the files in the private cache (`$RUN_ROOT/captures`) and what the Editor
# shows and exports; it never reaches into the app's classes. Sourced by scripts/check-run.sh,
# before flow 80 (which restarts the menu bar app).
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

CAPS="$RUN_ROOT/captures"
lc_pixels() { echo "$CAPS/capture-$1.pixels"; }
lc_state() { echo "$CAPS/capture-$1.state"; }
# One field of the state file (JSON): `plutil` prints a scalar, or the count of an array.
state_field() { plutil -extract "$2" raw -o - "$(lc_state "$1")" 2>/dev/null; }
lc_state_is() { [[ "$(state_field "$1" "$2")" == "$3" ]]; }
lc_has_state() { [[ -f "$(lc_state "$1")" ]]; }
lc_no_state() { [[ ! -e "$(lc_state "$1")" ]]; }
lc_no_folder() { [[ ! -e "$CAPS" ]]; }
lc_no_helper() { [[ -z "$(helper_pid)" ]]; }
lc_stamp() { stat -f '%i %Fm %z' "$1" 2>/dev/null; }
lc_entries() { ls -A "$CAPS" 2>/dev/null | LC_ALL=C sort | tr '\n' ' '; }
lc_written() { send "$EDITOR_SOCK" last-capture-writes | sed -n 's/.*written=\([0-9]*\).*/\1/p'; }
lc_dropped() { send "$EDITOR_SOCK" last-capture-writes | sed -n 's/.*dropped=\([0-9]*\).*/\1/p'; }
# The Annotations, Undo and Redo steps and revision of the open Editor, without the selection
# and tool (what a Reopen does not bring back).
lc_document() { send "$EDITOR_SOCK" "editor-document $EDITOR_N" | grep -E '^(annotation|undo-steps|redo-steps|revision)'; }
# Closes the open Editor with Esc (nothing is asked) and waits for the helper to quit.
lc_close() {
  send_slow "$EDITOR_SOCK" "editor-key $1 escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
}
# Reopen Last Capture from the menu; sets EDITOR_N and HELPER_PID to the Editor it shows.
lc_reopen() {
  local reply
  reply="$(send_slow "$APP_SOCK" "menu-click reopen-last-capture")"
  EDITOR_N="$(open_editors | tail -1)"
  HELPER_PID="$(helper_pid)"
  [[ "$reply" == "ok" ]]
}
lc_notice() { send "$EDITOR_SOCK" reopen-notice; }
lc_only_editor() { [[ "$(open_editors)" == "$1" ]]; }

wait_until 10 lc_no_helper
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" "defaults-set annotationColor ff3b30" >/dev/null
send "$APP_SOCK" "defaults-set annotationWidth 5" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
W=602
H=374

# 1. The Capture is stored when it is taken: pixels only, in a private folder.
if capture_into_editor "menu-click capture.screen"; then
  N="$EDITOR_N"
  TITLES="$(send "$APP_SOCK" menu-titles)"
  expect_in_order "the menu has Reopen Last Capture after the Capture items" "$TITLES" "Capture Screen" "-" "Reopen Last Capture"
  expect_equal "Reopen Last Capture is enabled while there is a Last Capture" "yes" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"
  expect_equal "the Last Capture is the Capture just taken" "$N" "$(send "$APP_SOCK" last-capture)"
  expect_equal "the Capture folder is private (mode 700)" "700" "$(stat -f '%Lp' "$CAPS")"
  expect_equal "the pixel file is private (mode 600)" "600" "$(stat -f '%Lp' "$(lc_pixels "$N")")"
  expect_equal "an untouched Capture has its pixels and no state file" "capture-$N.pixels " "$(lc_entries)"

  # 2. The first change writes the state file; quick changes share one write; a change that
  #    leaves the revision and the exported flag as they were writes nothing.
  keystroke r >/dev/null
  style fill solid >/dev/null
  drag 40 30 120 90 >/dev/null
  if wait_until 5 lc_has_state "$N"; then pass "the state file is written after the first change"; else fail "no state file after a change"; fi
  expect_equal "the state file records the revision" "$(document_field revision)" "$(state_field "$N" revision)"
  expect_equal "the state file holds the Annotation" "1" "$(state_field "$N" history.state.annotations)"
  expect_equal "the state file says the Capture is not exported" "false" "$(state_field "$N" exported)"
  expect_equal "the state file is private (mode 600)" "600" "$(stat -f '%Lp' "$(lc_state "$N")")"
  expect_equal "no partial file is left beside the state" "capture-$N.pixels capture-$N.state " "$(lc_entries)"

  sleep 1
  WRITTEN="$(lc_written)"
  drag 150 30 200 70 >/dev/null
  drag 150 80 200 120 >/dev/null
  drag 20 100 60 160 >/dev/null
  sleep 1.5
  # One write when the changes land within the half second; a busy machine may split them, but
  # never one write per change.
  NEW_WRITES="$(($(lc_written) - WRITTEN))"
  if ((NEW_WRITES >= 1 && NEW_WRITES <= 2)); then pass "three quick changes are coalesced into at most two state writes ($NEW_WRITES)"; else fail "three quick changes made $NEW_WRITES state writes"; fi
  expect_equal "the state file holds all four Annotations" "4" "$(state_field "$N" history.state.annotations)"
  expect_equal "the state file's revision is the Editor's" "$(document_field revision)" "$(state_field "$N" revision)"

  keystroke v >/dev/null
  STAMP="$(lc_stamp "$(lc_state "$N")")"
  WRITTEN="$(lc_written)"
  click 280 5 >/dev/null   # empty canvas: deselects, changes nothing
  sleep 1.2
  expect_equal "a click that changes nothing writes nothing (same file)" "$STAMP" "$(lc_stamp "$(lc_state "$N")")"
  expect_equal "a click that changes nothing is not a state write" "$WRITTEN" "$(lc_written)"

  # Copy marks the Capture exported; the state file follows, and a later change clears it.
  send_slow "$EDITOR_SOCK" "editor-press $N copy" >/dev/null
  if wait_until 5 lc_state_is "$N" exported true; then pass "Copy marks the Capture exported in the state file"; else fail "the state file is not marked exported after Copy"; fi
  keystroke r >/dev/null
  drag 200 130 250 170 >/dev/null
  if wait_until 5 lc_state_is "$N" exported false; then pass "a change after an Export clears the exported flag"; else fail "the exported flag is still set after a change"; fi

  # Idle once the write has landed.
  sleep 1
  assert_idle_cpu "the Editor helper after the state file was written" "$HELPER_PID" 3
  assert_idle_cpu "the menu bar app while the Last Capture's Editor is open" "$APP_PID" 3

  # 3. Annotations of every kind in the registry, a crop and the Undo history come back.
  KINDS="$(send "$EDITOR_SOCK" annotation-kinds)"
  KIND_COUNT="$(printf '%s\n' "$KINDS" | grep -c .)"
  expect_equal "every kind in the registry is stored and restored by the state file's encoding" \
    "ok kinds=$(printf '%s\n' "$KINDS" | paste -sd, -),kind-from-a-newer-snapit" "$(send "$EDITOR_SOCK" last-capture-roundtrip)"
  expect_equal "one Annotation of every kind is added" "ok" "$(send "$EDITOR_SOCK" "editor-inject-kinds $N")"
  expect_equal "the crop is set" "ok" "$(send "$EDITOR_SOCK" "editor-state-crop $N set 10 12 100 80")"
  BEFORE_DOC="$(lc_document)"
  BEFORE_PNG="$(export_png before-reopen)"
  BEFORE_PIXELS="$(lc_stamp "$(lc_pixels "$N")")"
  expect_equal "the Editor has the four drawn Annotations and one of every kind" "$((5 + KIND_COUNT))" "$(printf '%s\n' "$BEFORE_DOC" | grep -c '^annotation')"

  lc_close "$N"
  if gone "$HELPER_PID"; then pass "closing the Last Capture's Editor asks nothing and closes it"; else fail "the Last Capture's Editor did not close"; fi
  expect_equal "the state file written on close has the final revision" "$(printf '%s\n' "$BEFORE_DOC" | sed -n 's/^revision=//p')" "$(state_field "$N" revision)"
  expect_equal "closing keeps the Last Capture's files" "capture-$N.pixels capture-$N.state " "$(lc_entries)"
  expect_equal "Reopen Last Capture stays enabled after the Editor closed" "yes" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"

  # 4. Reopen brings back the pixels, Annotations, crop and Undo history, exactly.
  if lc_reopen; then pass "Reopen Last Capture opens an Editor"; else fail "Reopen Last Capture failed"; fi
  expect_equal "the reopened Editor is the Last Capture's number" "$N" "$EDITOR_N"
  expect_equal "the Annotations, Undo and Redo steps and revision come back exactly" "$BEFORE_DOC" "$(lc_document)"
  expect_equal "the crop comes back" "10.0 12.0 100.0 80.0" "$(send "$EDITOR_SOCK" "editor-state-crop $EDITOR_N get")"
  expect_contains "the reopened Editor shows the Capture at its native pixel size" "pixels=$W""x$H" "$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N")"
  AFTER_PNG="$(export_png after-reopen)"
  expect_equal "the reopened Capture exports the same pixels" "max_diff=0" "$("$INSPECT" compare "$BEFORE_PNG" "$AFTER_PNG" | grep '^max_diff=')"
  expect_equal "Reopen leaves the pixel file as it was (no encode, no rewrite)" "$BEFORE_PIXELS" "$(lc_stamp "$(lc_pixels "$N")")"
  expect_enabled "Undo is enabled after a Reopen (the Undo history came back)" undo
  keystroke undo >/dev/null
  expect_equal "Undo after a Reopen takes back the last change, the crop" "none" "$(send "$EDITOR_SOCK" "editor-state-crop $EDITOR_N get")"
  keystroke undo >/dev/null
  expect_equal "the next Undo takes back the last Annotation" "$((4 + KIND_COUNT))" "$(lc_document | grep -c '^annotation')"
  keystroke redo >/dev/null
  keystroke redo >/dev/null
  expect_equal "Redo puts the Annotations back" "$(printf '%s\n' "$BEFORE_DOC" | grep '^annotation')" "$(lc_document | grep '^annotation')"
  expect_equal "and the crop" "10.0 12.0 100.0 80.0" "$(send "$EDITOR_SOCK" "editor-state-crop $EDITOR_N get")"
  # Reopen while the Editor is open brings that Editor forward and opens no second one.
  OPEN_BEFORE="$(open_editors)"
  HELPER_BEFORE="$HELPER_PID"
  expect_equal "Reopen with the Last Capture's Editor open replies ok" "ok" "$(send_slow "$APP_SOCK" "menu-click reopen-last-capture")"
  expect_equal "that opens no second Editor" "$OPEN_BEFORE" "$(open_editors)"
  expect_equal "and starts no second helper" "$HELPER_BEFORE" "$(helper_pid)"

  # 5. The history is capped at 100 steps, in the file and after a Reopen.
  for i in $(seq 1 105); do send "$EDITOR_SOCK" "editor-state-crop $EDITOR_N set $i 5 100 80" >/dev/null; done
  if wait_until 5 lc_state_is "$N" history.undoSteps 100; then pass "the state file keeps at most 100 Undo steps"; else fail "the state file holds $(state_field "$N" history.undoSteps) Undo steps"; fi
  lc_close "$EDITOR_N"
  lc_reopen
  expect_contains "a Reopen brings back 100 Undo steps" "undo-steps=100" "$(send "$EDITOR_SOCK" "editor-document $EDITOR_N")"

  # 6. Delete Capture removes the files and the folder at once and greys out the menu item.
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N delete-capture" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Delete Capture closes the Editor"; else fail "the Editor is still open after Delete Capture"; fi
  if wait_until 5 lc_no_folder; then pass "Delete Capture removes the Capture's files and the folder"; else fail "after Delete Capture the folder holds: $(lc_entries)"; fi
  sleep 1.2
  expect_equal "no state file is written after Delete Capture" "" "$(lc_entries)"
  expect_equal "Reopen Last Capture is greyed out with no Last Capture" "no" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"
  expect_equal "choosing the greyed item does nothing" "error menu item is disabled" "$(send "$APP_SOCK" "menu-click reopen-last-capture")"
  expect_equal "there is no Last Capture" "none" "$(send "$APP_SOCK" last-capture)"

  # A Capture whose folder is removed (by a Delete Capture) between the folder being made and
  # the file being created still lands: the folder is made again.
  expect_equal "the next Capture file finds its folder removed" "ok" "$(send "$APP_SOCK" capture-folder-race)"
  if capture_into_editor "menu-click capture.screen"; then
    pass "a Capture whose folder was removed under it still opens"
    expect_equal "its pixel file is there" "capture-$EDITOR_N.pixels " "$(lc_entries)"
    expect_equal "in a private folder" "700" "$(stat -f '%Lp' "$CAPS")"
    lc_close "$EDITOR_N"
  else
    fail "a Capture whose folder was removed under it did not open"
  fi
fi

# 7. A new Capture replaces the Last Capture. The Editor of the old one keeps its Capture in
#    memory only.
if capture_into_editor "menu-click capture.screen"; then
  A="$EDITOR_N"
  keystroke r >/dev/null
  drag 40 30 120 90 >/dev/null
  wait_until 5 lc_has_state "$A"
  if capture_into_editor "menu-click capture.screen"; then
    B="$EDITOR_N"
    expect_equal "a second Editor opens for the new Capture" "$A
$B" "$(open_editors)"
    expect_equal "the new Capture is the Last Capture" "$B" "$(send "$APP_SOCK" last-capture)"
    expect_equal "the new Capture replaced the old one's pixels and state" "capture-$B.pixels " "$(lc_entries)"
    # The older Editor is edited: nothing of it is written, and nothing of the new one either.
    EDITOR_N="$A"
    keystroke r >/dev/null
    drag 150 30 200 70 >/dev/null
    sleep 1.3
    expect_equal "an Editor that is not the Last Capture's writes nothing" "capture-$B.pixels " "$(lc_entries)"
    EDITOR_N="$B"
    keystroke r >/dev/null
    drag 40 30 120 90 >/dev/null
    if wait_until 5 lc_has_state "$B"; then pass "the new Last Capture's Editor writes its state"; else fail "no state file for the new Last Capture"; fi
    expect_equal "only the Last Capture's files exist" "capture-$B.pixels capture-$B.state " "$(lc_entries)"
    # Reopen with the Last Capture's Editor in the background brings that Editor forward.
    send "$EDITOR_SOCK" "editor-background $B" >/dev/null
    expect_equal "the older Editor is in front of the Last Capture's" "$A" "$(send "$EDITOR_SOCK" editor-front)"
    expect_equal "Reopen with a background Last Capture Editor replies ok" "ok" "$(send_slow "$APP_SOCK" "menu-click reopen-last-capture")"
    expect_equal "Reopen brings the Last Capture's open Editor in front" "$B" "$(send "$EDITOR_SOCK" editor-front)"
    expect_equal "and opens no second Editor for it" "$A
$B" "$(open_editors)"
    # Deleting the older Capture leaves the Last Capture alone.
    send_slow "$EDITOR_SOCK" "editor-press $A delete-capture" >/dev/null
    wait_until 5 lc_only_editor "$B"
    expect_equal "Delete Capture on the older Editor closes only that Editor" "$B" "$(open_editors)"
    expect_equal "and leaves the Last Capture's files" "capture-$B.pixels capture-$B.state " "$(lc_entries)"
    expect_equal "and the Last Capture" "$B" "$(send "$APP_SOCK" last-capture)"
    lc_close "$B"
  fi
fi

# 8. A write made stale is dropped: a change waiting to be written when a new Capture replaces
#    the Capture never lands.
if capture_into_editor "menu-click capture.screen"; then
  C="$EDITOR_N"
  send "$EDITOR_SOCK" "last-capture-hold on" >/dev/null
  WRITTEN="$(lc_written)"
  DROPPED="$(lc_dropped)"
  keystroke r >/dev/null
  drag 40 30 120 90 >/dev/null
  sleep 1
  expect_equal "while writes are held, nothing is written" "capture-$C.pixels " "$(lc_entries)"
  send_slow "$APP_SOCK" "menu-click capture.screen" >"$RUN_ROOT/last-capture-bg.txt" &
  BG_PID=$!
  sleep 1
  send "$EDITOR_SOCK" "last-capture-hold off" >/dev/null
  wait "$BG_PID"
  expect_equal "the new Capture still opens" "ok" "$(cat "$RUN_ROOT/last-capture-bg.txt")"
  expect_equal "the stale write was not made" "$WRITTEN" "$(lc_written)"
  expect_equal "the stale write was dropped" "$((DROPPED + 1))" "$(lc_dropped)"
  D="$(open_editors | tail -1)"
  expect_equal "the old Capture's files are gone and nothing was recreated" "capture-$D.pixels " "$(lc_entries)"
  send_slow "$EDITOR_SOCK" "editor-press $C delete-capture" >/dev/null
  wait_until 5 lc_only_editor "$D"
  lc_close "$D"
fi

# 8b. A Reopen that reaches the helper while a new Capture is being handed over (the menu bar
#     app still has the old one as the Last Capture) does nothing: it must neither demote the new
#     Capture nor say the old one is damaged, since its files are about to go.
if capture_into_editor "menu-click capture.screen"; then
  KEEP="$EDITOR_N"   # an open Editor keeps the helper running while C is closed
  if capture_into_editor "menu-click capture.screen"; then
    C="$EDITOR_N"
    send "$EDITOR_SOCK" "last-capture-hold on" >/dev/null
    keystroke r >/dev/null
    drag 40 30 120 90 >/dev/null
    sleep 1   # the write is queued and held
    send_slow "$EDITOR_SOCK" "editor-key $C escape" >/dev/null
    expect_equal "the Last Capture's Editor closed, the other stays" "$KEEP" "$(open_editors)"
    send_slow "$APP_SOCK" "menu-click capture.screen" >"$RUN_ROOT/last-capture-bg.txt" &
    BG_PID=$!
    sleep 1   # the new Capture is open in the helper, waiting for the held write before it is answered
    expect_equal "Reopen during the hand-off replies ok" "ok" "$(send_slow "$APP_SOCK" "menu-click reopen-last-capture")"
    expect_equal "it shows no message" "none" "$(lc_notice)"
    expect_equal "and brings back nothing: the old Capture is not in an Editor" "0" "$(open_editors | grep -c "^$C\$")"
    send "$EDITOR_SOCK" "last-capture-hold off" >/dev/null
    wait "$BG_PID"
    expect_equal "the new Capture opened" "ok" "$(cat "$RUN_ROOT/last-capture-bg.txt")"
    D="$(open_editors | tail -1)"
    expect_equal "the new Capture is the Last Capture" "$D" "$(send "$APP_SOCK" last-capture)"
    expect_equal "the Editors open are the other one and the new one" "$KEEP
$D" "$(open_editors)"
    EDITOR_N="$D"
    keystroke r >/dev/null
    drag 40 30 120 90 >/dev/null
    if wait_until 5 lc_has_state "$D"; then pass "the new Capture is still the Last Capture: its Editor writes its state"; else fail "the new Capture's Editor does not write its state: it was demoted"; fi
    expect_equal "the old Capture's files are gone" "capture-$D.pixels capture-$D.state " "$(lc_entries)"
    send_slow "$EDITOR_SOCK" "editor-key $KEEP escape" >/dev/null
    wait_until 5 lc_only_editor "$D"
    lc_close "$D"
  fi
fi

# 9. A damaged store makes Reopen say so, instead of doing nothing; the Last Capture is dropped.
check_damaged_reopen() { # description
  local label="$1"
  lc_reopen
  wait_until 10 answers "$EDITOR_SOCK"
  expect_equal "$label: Reopen shows that it couldn't reopen the Capture" "shown That Capture couldn't be reopened." "$(lc_notice)"
  expect_equal "$label: no Editor opened" "" "$(open_editors)"
  if wait_until 5 has_onscreen_window "$(helper_pid)"; then pass "$label: the message is a window on screen"; else fail "$label: no window shows the message"; fi
  expect_equal "$label: Reopen Last Capture is greyed out" "no" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"
  expect_equal "$label: the damaged files are removed" "" "$(lc_entries)"
  send "$EDITOR_SOCK" reopen-notice-close >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "$label: closing the message quits the helper"; else fail "$label: the helper is still running after the message closed"; fi
}
if capture_into_editor "menu-click capture.screen"; then
  keystroke r >/dev/null
  drag 40 30 120 90 >/dev/null
  wait_until 5 lc_has_state "$EDITOR_N"
  DAMAGED="$EDITOR_N"
  lc_close "$DAMAGED"
  printf '{ this is not a state file' >"$(lc_state "$DAMAGED")"
  check_damaged_reopen "a state file that cannot be read"
fi
if capture_into_editor "menu-click capture.screen"; then
  DAMAGED="$EDITOR_N"
  lc_close "$DAMAGED"
  truncate -s 1000 "$(lc_pixels "$DAMAGED")"
  check_damaged_reopen "a pixel file cut short"
fi
# No state file is not damage: an untouched Capture reopens as it was taken.
if capture_into_editor "menu-click capture.screen"; then
  UNTOUCHED="$EDITOR_N"
  lc_close "$UNTOUCHED"
  if lc_reopen; then pass "a Capture with no state file reopens"; else fail "a Capture with no state file did not reopen"; fi
  expect_equal "that Editor has no Annotations and nothing to undo" "revision=0" "$(lc_document | grep '^revision=')"
  expect_equal "no message was shown" "none" "$(lc_notice)"
  lc_close "$EDITOR_N"
fi

# 10. Memory returns to baseline over Reopen and close cycles, and nothing idles.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  BIG="$EDITOR_N"
  keystroke r >/dev/null
  drag 200 200 600 500 >/dev/null
  wait_until 5 lc_has_state "$BIG"
  lc_close "$BIG"
  lc_reopen && lc_close "$EDITOR_N"   # warm up
  sleep 1
  CYCLE_BASELINE="$(footprint_mb "$APP_PID")"
  HELPER_MIN=""
  HELPER_MAX=""
  for cycle in 1 2 3 4 5; do
    if lc_reopen; then
      HELPER_MB="$(peak_footprint_mb "$HELPER_PID" 3)"
      if [[ -z "$HELPER_MIN" ]] || awk -v a="$HELPER_MB" -v b="$HELPER_MIN" 'BEGIN { exit !(a < b) }'; then HELPER_MIN="$HELPER_MB"; fi
      if [[ -z "$HELPER_MAX" ]] || awk -v a="$HELPER_MB" -v b="$HELPER_MAX" 'BEGIN { exit !(a > b) }'; then HELPER_MAX="$HELPER_MB"; fi
      if ((cycle == 1)); then assert_idle_cpu "the helper with a reopened 5K Editor open" "$HELPER_PID" 3; fi
      lc_close "$EDITOR_N"
    else
      fail "Reopen failed in cycle $cycle"
    fi
  done
  sleep 1
  CYCLE_AFTER="$(footprint_mb "$APP_PID")"
  if awk -v a="$CYCLE_AFTER" -v b="$CYCLE_BASELINE" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
    pass "the menu bar app's memory is flat over five Reopen and close cycles (${CYCLE_BASELINE} MB before, ${CYCLE_AFTER} MB after)"
  else
    fail "the menu bar app's memory went from ${CYCLE_BASELINE} MB to ${CYCLE_AFTER} MB over five Reopen cycles (limit +${FOOTPRINT_GROWTH_MB_MAX} MB)"
  fi
  if awk -v a="$CYCLE_AFTER" -v b="$AT_REST" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
    pass "the menu bar app is back near its at-rest footprint after the Reopen cycles (${AT_REST} MB at rest, ${CYCLE_AFTER} MB after)"
  else
    fail "the menu bar app is at ${CYCLE_AFTER} MB after the Reopen cycles, ${AT_REST} MB at rest (limit +${FOOTPRINT_FROM_REST_MB_MAX} MB)"
  fi
  if awk -v lo="$HELPER_MIN" -v hi="$HELPER_MAX" 'BEGIN { exit !(lo > 0 && hi - lo <= 15) }'; then
    pass "the helper's footprint with a reopened 5K Editor is the same every cycle (${HELPER_MIN} to ${HELPER_MAX} MB)"
  else
    fail "the helper's footprint with a reopened 5K Editor varies from ${HELPER_MIN} to ${HELPER_MAX} MB"
  fi
  expect_equal "no helper process is left at rest after the Reopen cycles" "" "$(helper_pid)"
  assert_idle_cpu "the menu bar app after the Reopen cycles" "$APP_PID" 5
fi

# 11. Quitting removes the Last Capture: known files only, then the folder. A write that was
#     about to happen as snapit quits never recreates a file.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  # A change whose state write is queued, and held there, when snapit quits. The helper's quit
  # waits for the queue, which is held, so snapit's blocking send gives up after a second and
  # removes the files; the write must still never land. Quitting supersedes the write's
  # generation at once, before it waits, so the write is dropped when it is released, which
  # happens here after snapit has exited, while the helper is still alive.
  send "$EDITOR_SOCK" "last-capture-hold on" >/dev/null
  keystroke r >/dev/null
  drag 40 30 120 90 >/dev/null
  printf 'not snapit\n' >"$CAPS/unrelated.txt"
  sleep 1
  OLD_APP_PID="$APP_PID"
  OLD_HELPER="$HELPER_PID"
  send "$APP_SOCK" quit >/dev/null
  if wait_until 10 gone "$OLD_APP_PID"; then pass "snapit quits with a Last Capture"; else fail "snapit is still running"; fi
  send "$EDITOR_SOCK" "last-capture-hold off" >/dev/null
  if wait_until 10 gone "$OLD_HELPER"; then pass "the Editor helper quits with it"; else fail "the helper outlived snapit"; fi
  sleep 1
  expect_equal "quitting removes the Capture's pixels and state, and nothing else" "unrelated.txt " "$(lc_entries)"
  expect_equal "the folder stays while something that is not snapit's is in it" "not snapit" "$(cat "$CAPS/unrelated.txt")"

  # Files left by a crash are removed at launch.
  : >"$CAPS/capture-7.pixels"
  : >"$CAPS/capture-7.state"
  : >"$CAPS/capture-7.state.partial"
  : >"$CAPS/capture-7.pixels.partial"
  (nohup "$APP_EXE" >"$RUN_ROOT/app.log" 2>&1 &)
  if wait_until 10 answers "$APP_SOCK"; then pass "snapit starts again"; else abort "snapit did not restart after quitting"; fi
  APP_PID="$(pid_of "$APP_EXE")"
  expect_equal "launch removes the files a crash left, and only those" "unrelated.txt " "$(lc_entries)"
  expect_equal "there is no Last Capture after a restart" "none" "$(send "$APP_SOCK" last-capture)"
  expect_equal "Reopen Last Capture is greyed out after a restart" "no" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"
  rm -f "$CAPS/unrelated.txt"
  rmdir "$CAPS" 2>/dev/null
fi

# 12. The helper's own "Quit snapit" makes the same preparation before snapit quits: it waits for
#     the Last Capture's queued write (held here) to be dropped, and only then snapit quits and
#     removes the files.
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  send "$EDITOR_SOCK" "last-capture-hold on" >/dev/null
  keystroke r >/dev/null
  drag 40 30 120 90 >/dev/null
  sleep 1
  OLD_APP_PID="$APP_PID"
  OLD_HELPER="$HELPER_PID"
  expect_equal "the helper's Quit snapit is chosen" "ok" "$(send "$EDITOR_SOCK" editor-menu-quit)"
  sleep 1.5
  if kill -0 "$OLD_APP_PID" 2>/dev/null; then pass "snapit is still running while the Last Capture's write is held"; else fail "snapit quit before the Last Capture's write was dealt with"; fi
  send "$EDITOR_SOCK" "last-capture-hold off" >/dev/null
  if wait_until 15 gone "$OLD_APP_PID"; then pass "snapit quits once the write is dropped"; else fail "snapit is still running after the held write was released"; fi
  if wait_until 10 gone "$OLD_HELPER"; then pass "the Editor helper quits with it"; else fail "the helper outlived snapit"; fi
  sleep 1
  expect_equal "the Capture's files are gone, folder and all" "" "$(lc_entries)"
  (nohup "$APP_EXE" >"$RUN_ROOT/app.log" 2>&1 &)
  if wait_until 10 answers "$APP_SOCK"; then pass "snapit starts again"; else abort "snapit did not restart after quitting"; fi
  APP_PID="$(pid_of "$APP_EXE")"
fi
send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null
