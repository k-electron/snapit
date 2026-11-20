# The run's own measuring tools, checked against known inputs before anything depends on them: that the
# isolation check on the general pasteboard fails when snapit-shaped data lands on a pasteboard (and stays
# quiet for a user's own text copy), and that the idle CPU measure fails a steady 2% loop and a timer that
# fires every two seconds but shrugs off one short burst. The pasteboard checks use a private pasteboard
# of their own, never the user's.

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

# harness_cpu <seconds> <burn ms> <wait ms> <first ms> <repeat 0|1>: the idle CPU sample of a process that waits
# <first> ms and then uses <burn> ms of CPU time, waiting <wait> ms between bursts when it repeats.
harness_cpu() {
  local seconds="$1" burner
  shift
  perl -e '
    my ($burn, $wait, $first, $repeat) = @ARGV;
    sub nap { select(undef, undef, undef, $_[0] / 1000) }
    nap($first);
    do {
      my $t = (times)[0];
      1 while ((times)[0] - $t) < $burn / 1000;
      nap($wait);
    } while ($repeat);
    sleep 30' "$@" &
  burner=$!
  HARNESS_SAMPLE="$(idle_cpu_sample "$burner" "$seconds")"
  kill "$burner" 2>/dev/null
  wait "$burner" 2>/dev/null
}

harness_cpu 3 20 980 0 1
if idle_cpu_ok "$HARNESS_SAMPLE"; then fail "the idle CPU measure let a steady 2% loop through ($HARNESS_SAMPLE)"; else pass "the idle CPU measure fails a steady 2% loop ($HARNESS_SAMPLE)"; fi
harness_cpu 6 20 1980 0 1
if idle_cpu_ok "$HARNESS_SAMPLE"; then fail "the idle CPU measure let a 20 ms timer every two seconds through ($HARNESS_SAMPLE)"; else pass "the idle CPU measure fails a 20 ms timer every two seconds ($HARNESS_SAMPLE)"; fi
harness_cpu 5 60 0 2500 0
if idle_cpu_ok "$HARNESS_SAMPLE"; then pass "the idle CPU measure tolerates one short burst ($HARNESS_SAMPLE)"; else fail "the idle CPU measure failed a process with one short burst ($HARNESS_SAMPLE)"; fi
