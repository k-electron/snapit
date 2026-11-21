# The run's own measuring tools, checked against known inputs before anything depends on them: that the
# isolation check on the general pasteboard fails when snapit-shaped data lands on a pasteboard (and stays
# quiet for a user's own text copy), that the spin check fails a process that burns CPU all the time and
# passes one that is quiet, and that the cache check names a leftover file. The pasteboard checks use a
# private pasteboard of their own, never the user's.

HARNESS_BOARD="dev.snapit.test.harness.$(basename "$RUN_ROOT")"
harness_verdict() { # <png|hex|text|none>: the verdict after that content is put on the private pasteboard
  local before
  before="$(pasteboard_state - "$HARNESS_BOARD")"
  [[ "$1" == none ]] || "$INSPECT" pasteboard-fixture "$HARNESS_BOARD" "$1"
  pasteboard_verdict "$before" "$(pasteboard_state "$(pasteboard_field "$before" change_count)" "$HARNESS_BOARD")"
}
expect_equal "isolation: a pasteboard nobody wrote to is untouched" "untouched" "$(harness_verdict none)"
expect_equal "isolation: a PNG written to a pasteboard is caught" "touched" "$(harness_verdict png)"
expect_equal "isolation: a #RRGGBB string written to a pasteboard is caught" "touched" "$(harness_verdict hex)"
expect_equal "isolation: other text written to a pasteboard is a user's copy, not snapit's" "user-copy" "$(harness_verdict text)"
HARNESS_UNCHANGED="$(pasteboard_state - "$HARNESS_BOARD")"
expect_contains "isolation: an unchanged pasteboard's contents are not looked at" "shape=unread" \
  "$(pasteboard_state "$(pasteboard_field "$HARNESS_UNCHANGED" change_count)" "$HARNESS_BOARD")"
"$INSPECT" pasteboard-fixture "$HARNESS_BOARD" release

# harness_burner <busy|quiet>: a process that burns CPU all the time (a loop) or sleeps. Sets HARNESS_PID.
harness_burner() {
  if [[ "$1" == busy ]]; then perl -e '1 while 1' & else sleep 30 & fi
  HARNESS_PID=$!
}
harness_spin_failures() { # <busy|quiet>: how many checks the spin check fails for that process
  local output
  harness_burner "$1"
  output="$(expect_not_spinning "the harness process" "$HARNESS_PID" 3)"
  kill "$HARNESS_PID" 2>/dev/null
  wait "$HARNESS_PID" 2>/dev/null
  [[ "$output" == FAIL* ]] && echo 1 || echo 0
}
expect_equal "the spin check fails a process that burns CPU all the time" "1" "$(harness_spin_failures busy)"
expect_equal "the spin check passes a quiet process" "0" "$(harness_spin_failures quiet)"

mkdir -p "$RUN_ROOT/exports"
: >"$RUN_ROOT/exports/leftover.pixels"
expect_contains "the cache check names a leftover export file" "exports/leftover.pixels" "$(cache_leftovers)"
rm -f "$RUN_ROOT/exports/leftover.pixels"
rmdir "$RUN_ROOT/exports"
expect_equal "the cache check passes a clean cache folder" "" "$(cache_leftovers)"
