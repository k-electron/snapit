# Flow: Delete Capture, several Editors, and the close and Quit prompts. The rule is "don't
# over-protect Captures the user never Exported": closing an Editor that is not the Last Capture's
# and holds edits it never Exported asks once; Quit asks only in that case, bringing that Editor
# forward first; the Last Capture's Editor never asks (it can be reopened); Delete Capture never
# asks. Copy, Save and a taken drop clear the unexported state. The prompt is a real sheet on the
# Editor's window; the run answers it through `editor-prompt-answer` (buttons, Esc), so
# nothing ever waits on a modal. Flow 50 ends with a freshly restarted menu bar app, so this
# flow reads its pids and its at-rest memory again. Sourced by scripts/check-run.sh, after flow
# 50; it ends with a menu bar app running again.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

APP_PID="$(pid_of "$APP_EXE")"
PCAPS="$RUN_ROOT/captures"
wait_until 10 bash -c "[[ -z \"\$(pgrep -f '$HELPER_EXE' | head -1)\" ]]"
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterCopy false" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterSave false" >/dev/null
send "$APP_SOCK" "defaults-set annotationFilled false" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null

pr_prompt() { send "$EDITOR_SOCK" editor-prompt; }
pr_shown() { [[ "$(pr_prompt)" == shown* ]]; }
pr_none() { [[ "$(pr_prompt)" == none ]]; }
# Waits for a prompt to show and for it to go.
pr_wait_shown() { wait_until 5 pr_shown; }
pr_wait_none() { wait_until 5 pr_none; }
pr_answer() { send "$EDITOR_SOCK" "editor-prompt-answer $1" >/dev/null; pr_wait_none; }
pr_open() { # <N>: Editor N is among the open Editors
  open_editors | grep -qx "$1"
}
pr_is_open() { pr_open "$1"; }
pr_is_closed() { ! pr_open "$1"; }
# Reopen Last Capture from the menu; sets EDITOR_N and HELPER_PID to the Editor it shows.
pr_reopen() {
  local reply
  reply="$(send_slow "$APP_SOCK" "menu-click reopen-last-capture")"
  EDITOR_N="$(open_editors | tail -1)"
  HELPER_PID="$(helper_pid)"
  [[ "$reply" == "ok" ]]
}
# No prompt shows for a short while: a prompt would be on screen the moment the Editor handled the key.
pr_quiet() { sleep 0.6; pr_none; }
# edit <N>: one Rectangle in Editor N.
edit() { EDITOR_N="$1"; keystroke r >/dev/null; drag 40 30 120 90 >/dev/null; }
# pair: two Editors open, A (older, not the Last Capture's) and B (the Last Capture's).
pair() {
  capture_into_editor "menu-click capture.screen" || return 1
  A="$EDITOR_N"
  capture_into_editor "menu-click capture.screen" || return 1
  B="$EDITOR_N"
}
# end_pair: Delete Capture on A (immediate, asks nothing) if it is still open, then close B (the
# Last Capture's, asks nothing) and wait for the helper to quit.
end_pair() {
  if pr_is_open "$A"; then send_slow "$EDITOR_SOCK" "editor-press $A delete-capture" >/dev/null; wait_until 5 pr_is_closed "$A"; fi
  send_slow "$EDITOR_SOCK" "editor-key $B escape" >/dev/null
  wait_until 10 gone "$HELPER_PID"
}
revision_of() { send "$EDITOR_SOCK" "editor-document $1" | sed -n 's/^revision=//p'; }

# 1. The Last Capture's Editor never asks, with edits or not, by Esc, ⌘W or the close button;
#    Reopen brings it back.
if capture_into_editor "menu-click capture.screen"; then
  edit "$EDITOR_N"
  LAST="$EDITOR_N"
  send_slow "$EDITOR_SOCK" "editor-key $LAST escape" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "closing the Last Capture's Editor with unexported edits asks nothing (Esc)"; else fail "the Last Capture's Editor asked, or did not close, on Esc"; fi
  if capture_into_editor "menu-click capture.screen"; then
    edit "$EDITOR_N"
    LAST="$EDITOR_N"
    send_slow "$EDITOR_SOCK" "editor-key $LAST close" >/dev/null
    if wait_until 10 gone "$HELPER_PID"; then pass "the Last Capture's Editor closes on ⌘W with unexported edits, asking nothing"; else fail "the Last Capture's Editor did not close on ⌘W"; fi
    if pr_reopen; then
      edit "$EDITOR_N"
      send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N close-button" >/dev/null
      if wait_until 10 gone "$HELPER_PID"; then pass "a reopened Last Capture's Editor closes by its close button, asking nothing"; else fail "the reopened Last Capture's Editor asked on its close button"; fi
    else
      fail "Reopen Last Capture did not bring the Last Capture back"
    fi
  fi
fi

# 2. An Editor that is not the Last Capture's and has no edits closes without asking.
if pair; then
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  wait_until 5 pr_is_closed "$A"
  expect_equal "an older Editor with no edits closes without a prompt" "$B" "$(open_editors)"
  expect_equal "and no prompt is showing" "none" "$(pr_prompt)"
  end_pair
fi

# 3. An older Editor with unexported edits asks once, on every way of closing it.
if pair; then
  edit "$A"
  REVISION="$(revision_of "$A")"
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  if pr_wait_shown; then pass "closing an older Editor with unexported edits asks"; else fail "no prompt for an older Editor with unexported edits"; fi
  PROMPT="$(pr_prompt)"
  expect_contains "the prompt is about closing that Editor" "shown close editor=$A" "$PROMPT"
  expect_contains "it names the Capture" "title=Discard this Capture?" "$PROMPT"
  expect_contains "it says why, in the glossary's words" "edits haven't been Exported" "$PROMPT"
  expect_contains "its buttons are Cancel and Discard" "buttons=Cancel,Discard" "$PROMPT"
  expect_contains "Esc is Cancel" "escape=Cancel" "$PROMPT"
  expect_contains "Discard has a key of its own, ⌘D (read back once the sheet is up)" "command-d=Discard" "$PROMPT"
  expect_contains "both buttons have a tooltip" "tooltips=Keep this Editor open|Discard this Capture and close its Editor" "$PROMPT"
  expect_contains "the view under Delete Capture's button refuses the first click" "accepts-first-mouse=no" "$(send "$EDITOR_SOCK" "editor-first-mouse $A item delete-capture")"
  expect_contains "the view under Undo's button takes it" "accepts-first-mouse=yes" "$(send "$EDITOR_SOCK" "editor-first-mouse $A item undo")"
  expect_equal "the Editor stays open while it asks" "$(printf '%s\n%s' "$A" "$B")" "$(open_editors)"
  expect_equal "the question is on that Editor's window: it is in front" "$A" "$(send "$EDITOR_SOCK" editor-front)"
  pr_answer cancel
  expect_equal "Cancel keeps the Editor open" "$(printf '%s\n%s' "$A" "$B")" "$(open_editors)"
  expect_equal "and its edits as they were" "$REVISION" "$(revision_of "$A")"
  # ⌘W asks too; Esc on the sheet is Cancel.
  send_slow "$EDITOR_SOCK" "editor-key $A close" >/dev/null
  if pr_wait_shown; then pass "⌘W asks"; else fail "⌘W on an older Editor with unexported edits did not ask"; fi
  expect_equal "Esc answers the prompt (keyboard)" "ok" "$(send "$EDITOR_SOCK" "editor-prompt-answer escape")"
  if pr_wait_none; then pass "Esc cancels the prompt"; else fail "Esc left the prompt showing"; fi
  expect_equal "so the Editor is still open" "$(printf '%s\n%s' "$A" "$B")" "$(open_editors)"
  send_slow "$EDITOR_SOCK" "editor-key $A close-button" >/dev/null
  if pr_wait_shown; then pass "the close button asks"; else fail "the close button did not ask"; fi
  pr_answer cancel
  expect_equal "so the Editor is still open" "$(printf '%s\n%s' "$A" "$B")" "$(open_editors)"
  # Asked once: a second Esc while the question shows does not stack another.
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  pr_wait_shown
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  expect_equal "a second close while it asks is not a second question" "1" "$(pr_prompt | grep -c '^shown')"
  expect_equal "⌘D answers the prompt (keyboard)" "ok" "$(send "$EDITOR_SOCK" "editor-prompt-answer command-d")"
  if wait_until 5 pr_is_closed "$A"; then pass "⌘D discards: the Editor closes"; else fail "⌘D left the Editor open"; fi
  expect_equal "only that Editor closed" "$B" "$(open_editors)"
  expect_equal "the Last Capture's Editor is untouched and its Capture is the Last Capture" "$B" "$(send "$APP_SOCK" last-capture)"
  end_pair
fi

# 3b. A Text still being typed counts as an edit: it is committed first, then counted, on a close
#     and on a Quit.
editing_now() { send "$EDITOR_SOCK" "editor-text $A" | sed -n 's/^editing=//p'; }
if pair; then
  EDITOR_N="$A"
  keystroke t >/dev/null
  click 30 40 >/dev/null
  send "$EDITOR_SOCK" "editor-type $A T" >/dev/null
  expect_equal "a Text is being typed in the older Editor" "yes" "$(editing_now)"
  send_slow "$EDITOR_SOCK" "editor-key $A close" >/dev/null
  if pr_wait_shown; then pass "closing an older Editor with a Text still being typed asks"; else fail "a Text being typed did not count as an edit on close"; fi
  expect_equal "the Text was committed first" "no" "$(editing_now)"
  pr_answer cancel
  end_pair
fi
if pair; then
  EDITOR_N="$A"
  keystroke t >/dev/null
  click 30 40 >/dev/null
  send "$EDITOR_SOCK" "editor-type $A T" >/dev/null
  OLD_APP="$APP_PID"
  send_slow "$APP_SOCK" "menu-click quit" >"$RUN_ROOT/quit-menu.txt" 2>&1 &
  QUIT_PID=$!
  if pr_wait_shown; then pass "Quit snapit with a Text still being typed in an older Editor asks"; else fail "a Text being typed did not count as an edit on Quit"; fi
  expect_contains "about that Editor" "shown quit editor=$A" "$(pr_prompt)"
  pr_answer cancel
  wait "$QUIT_PID"
  expect_equal "Cancel keeps snapit running" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  end_pair
fi

# 4. Exporting clears the unexported state: Copy, Save and a taken drop; each closes asking nothing.
#    A refused drop, a failed Save and a change after the Export do not.
if pair; then
  edit "$A"
  send_slow "$EDITOR_SOCK" "editor-press $A copy" >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  wait_until 5 pr_is_closed "$A"
  expect_equal "after Copy an older Editor closes without a prompt" "$B" "$(open_editors)"
  end_pair
fi
if pair; then
  edit "$A"
  send_slow "$EDITOR_SOCK" "editor-press $A save" >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  wait_until 5 pr_is_closed "$A"
  expect_equal "after Save an older Editor closes without a prompt" "$B" "$(open_editors)"
  end_pair
fi
if pair; then
  edit "$A"
  send "$EDITOR_SOCK" "editor-drop $A begin" >/dev/null
  expect_equal "a drop nobody took is refused" "ok" "$(send "$EDITOR_SOCK" "editor-drop $A refused")"
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  if pr_wait_shown; then pass "a refused drop does not count as an Export: closing asks"; else fail "a refused drop cleared the unexported state"; fi
  pr_answer cancel
  send "$EDITOR_SOCK" "editor-drop $A begin" >/dev/null
  expect_equal "a drop that was taken" "ok" "$(send "$EDITOR_SOCK" "editor-drop $A taken")"
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  wait_until 5 pr_is_closed "$A"
  expect_equal "after a taken drop the Editor closes without a prompt" "$B" "$(open_editors)"
  end_pair
fi
if pair; then
  edit "$A"
  send_slow "$EDITOR_SOCK" "editor-press $A copy" >/dev/null
  EDITOR_N="$A"
  keystroke r >/dev/null
  drag 150 30 200 70 >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  if pr_wait_shown; then pass "an edit after the Export asks again"; else fail "an edit made after Copy did not ask"; fi
  pr_answer cancel
  keystroke undo >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  wait_until 5 pr_is_closed "$A"
  expect_equal "edited back to exactly what was Exported, the Editor closes without a prompt" "$B" "$(open_editors)"
  end_pair
fi
# 4b. An edit made while an Export is still running (a Save waiting on a folder prompt) is not
#     covered by it: the Export took its snapshot first.
for kind in save copy; do
  if pair; then
    edit "$A"
    send "$EDITOR_SOCK" "export-hold on" >/dev/null
    send_slow "$EDITOR_SOCK" "editor-press $A $kind" >"$RUN_ROOT/export-bg.txt" 2>&1 &
    EXPORT_PID=$!
    sleep 1
    EDITOR_N="$A"
    keystroke r >/dev/null
    drag 150 30 200 70 >/dev/null
    send "$EDITOR_SOCK" "export-hold off" >/dev/null
    wait "$EXPORT_PID"
    send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
    if pr_wait_shown; then pass "an edit made while a ${kind} was running still asks on close"; else fail "an edit made while a ${kind} was running was marked Exported"; fi
    pr_answer cancel
    end_pair
  fi
done
if pair; then
  edit "$A"
  send "$EDITOR_SOCK" "editor-drop $A begin" >/dev/null
  EDITOR_N="$A"
  keystroke r >/dev/null
  drag 150 30 200 70 >/dev/null
  send "$EDITOR_SOCK" "editor-drop $A taken" >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  if pr_wait_shown; then pass "an edit made while a drag was in progress still asks on close"; else fail "an edit made after a drag began was marked Exported"; fi
  pr_answer cancel
  end_pair
fi
if pair; then
  SAVE_DIR="$RUN_ROOT/save"
  edit "$A"
  chmod 500 "$SAVE_DIR"
  send_slow "$EDITOR_SOCK" "editor-press $A save" >/dev/null
  chmod 700 "$SAVE_DIR"
  # The failed Save shows the folder Permission guide, a window of its own that would keep the helper alive: close it.
  send "$EDITOR_SOCK" "guide-close folder" >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  if pr_wait_shown; then pass "a Save that failed does not count as an Export: closing asks"; else fail "a failed Save cleared the unexported state"; fi
  pr_answer cancel
  end_pair
fi
if pair; then
  # Undone back to nothing, there is nothing to lose.
  edit "$A"
  keystroke undo >/dev/null
  send_slow "$EDITOR_SOCK" "editor-key $A escape" >/dev/null
  wait_until 5 pr_is_closed "$A"
  expect_equal "an older Editor whose Annotations were all Undone closes without a prompt" "$B" "$(open_editors)"
  end_pair
fi

# 5. Delete Capture is immediate: no prompt, on an older Editor with unexported edits and on the
#    Last Capture's; the Last Capture's files go and Reopen is greyed out.
if pair; then
  edit "$A"
  edit "$B"
  wait_until 5 test -f "$PCAPS/capture-$B.state"
  send_slow "$EDITOR_SOCK" "editor-press $A delete-capture" >/dev/null
  wait_until 5 pr_is_closed "$A"
  expect_equal "Delete Capture on an older Editor with unexported edits closes it with no prompt" "$B" "$(open_editors)"
  expect_equal "and no prompt shows" "none" "$(pr_prompt)"
  expect_equal "the Last Capture is still there" "$B" "$(send "$APP_SOCK" last-capture)"
  expect_equal "Reopen is enabled" "yes" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"
  send_slow "$EDITOR_SOCK" "editor-press $B delete-capture" >/dev/null
  if wait_until 10 gone "$HELPER_PID"; then pass "Delete Capture on the Last Capture's Editor with unexported edits closes it with no prompt"; else fail "Delete Capture on the Last Capture's Editor did not close it"; fi
  if wait_until 5 test ! -e "$PCAPS"; then pass "the Last Capture's files and folder are removed"; else fail "the Last Capture's files are still there: $(ls -A "$PCAPS")"; fi
  sleep 1.2
  expect_equal "no pending write recreated them" "none" "$(ls -A "$PCAPS" 2>/dev/null || echo none)"
  expect_equal "Reopen Last Capture is greyed out" "no" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"
fi

# 6. Several Editors: the Dock and Cmd-Tab entry stays while any is open, a new Capture opens
#    another Editor on a window of its own, the helper quits after the last one closes. Memory
#    returns to where it was, and nothing idles.
sleep 1
APP_REST="$(footprint_mb "$APP_PID")"
CASCADE_BEFORE="$(footprint_mb "$APP_PID")"
for round in 1 2 3; do
  if capture_into_editor "menu-click capture.screen"; then
    E1="$EDITOR_N"
    capture_into_editor "menu-click capture.screen"; E2="$EDITOR_N"
    capture_into_editor "menu-click capture.screen"; E3="$EDITOR_N"
    if ((round == 1)); then
      expect_equal "a new Capture while an Editor is open opens another: three Editors" "$(printf '%s\n%s\n%s' "$E1" "$E2" "$E3")" "$(open_editors)"
      if is_foreground "$HELPER_PID"; then pass "the helper has a Dock icon and a Cmd-Tab entry while Editors are open"; else fail "the helper is not a regular app with three Editors open"; fi
      O1="$(send "$EDITOR_SOCK" "editor-facts $E1" | sed -n 's/^window-origin=//p')"
      O2="$(send "$EDITOR_SOCK" "editor-facts $E2" | sed -n 's/^window-origin=//p')"
      O3="$(send "$EDITOR_SOCK" "editor-facts $E3" | sed -n 's/^window-origin=//p')"
      expect_equal "the three windows are cascaded, none on top of another" "3" "$(printf '%s\n%s\n%s\n' "$O1" "$O2" "$O3" | sort -u | wc -l | tr -d ' ')"
      expect_equal "only the Last Capture's pixels are in the cache" "capture-$E3.pixels " "$(ls -A "$PCAPS" | LC_ALL=C sort | tr '\n' ' ')"
      expect_equal "the Last Capture is the newest" "$E3" "$(send "$APP_SOCK" last-capture)"
      sleep 2
      assert_idle_cpu "the helper with three Editors open" "$HELPER_PID" 3
      # Close the middle one; the next Capture takes a free spot, not the one of an open Editor.
      send_slow "$EDITOR_SOCK" "editor-key $E2 escape" >/dev/null
      wait_until 5 pr_is_closed "$E2"
      if is_foreground "$HELPER_PID"; then pass "the helper stays a regular app while an Editor is open"; else fail "the helper went back to an agent with Editors still open"; fi
      capture_into_editor "menu-click capture.screen"; E4="$EDITOR_N"
      O4="$(send "$EDITOR_SOCK" "editor-facts $E4" | sed -n 's/^window-origin=//p')"
      expect_equal "after closing one in the middle, the next Editor opens on a spot of its own" "3" "$(printf '%s\n%s\n%s\n' "$O1" "$O3" "$O4" | sort -u | wc -l | tr -d ' ')"
      send_slow "$EDITOR_SOCK" "editor-key $E4 escape" >/dev/null
      send_slow "$EDITOR_SOCK" "editor-key $E3 escape" >/dev/null
      send_slow "$EDITOR_SOCK" "editor-key $E1 escape" >/dev/null
    else
      for n in "$E1" "$E2" "$E3"; do send_slow "$EDITOR_SOCK" "editor-key $n escape" >/dev/null; done
    fi
    if wait_until 10 gone "$HELPER_PID"; then pass "the helper quits after the last Editor closes (round $round)"; else fail "the helper outlived its last Editor (round $round)"; fi
  fi
done
sleep 1
CASCADE_AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$CASCADE_AFTER" -v b="$APP_REST" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app's memory is back to its baseline after several Editors opened and closed (${APP_REST} MB before, ${CASCADE_AFTER} MB after)"
else
  fail "the menu bar app went from ${APP_REST} MB to ${CASCADE_AFTER} MB over several Editors"
fi
expect_equal "no helper is left at rest" "" "$(helper_pid)"
assert_idle_cpu "the menu bar app after several Editors" "$APP_PID" 3

# 6b. The helper is where Editors live: with one Editor open throughout, opening two more and
#     closing them (Delete Capture asks nothing) leaves its footprint where it was.
send "$APP_SOCK" "fixture-display 2 2560 1440" >/dev/null
if capture_into_editor "menu-click capture.screen"; then
  KEEP="$EDITOR_N"
  KEEP_HELPER="$HELPER_PID"
  CYCLE_MIN=""
  CYCLE_MAX=""
  for cycle in 1 2 3 4 5; do
    capture_into_editor "menu-click capture.screen"; C1="$EDITOR_N"
    capture_into_editor "menu-click capture.screen"; C2="$EDITOR_N"
    send_slow "$EDITOR_SOCK" "editor-press $C1 delete-capture" >/dev/null
    send_slow "$EDITOR_SOCK" "editor-press $C2 delete-capture" >/dev/null
    wait_until 10 bash -c "[[ \"\$(printf 'editors\n' | nc -U -w 2 '$EDITOR_SOCK')\" == '$KEEP' ]]"
    MB="$(peak_footprint_mb "$KEEP_HELPER" 2)"
    if [[ -z "$CYCLE_MIN" ]] || awk -v a="$MB" -v b="$CYCLE_MIN" 'BEGIN { exit !(a < b) }'; then CYCLE_MIN="$MB"; fi
    if [[ -z "$CYCLE_MAX" ]] || awk -v a="$MB" -v b="$CYCLE_MAX" 'BEGIN { exit !(a > b) }'; then CYCLE_MAX="$MB"; fi
  done
  expect_equal "the same helper served every cycle" "$KEEP_HELPER" "$(helper_pid)"
  if awk -v lo="$CYCLE_MIN" -v hi="$CYCLE_MAX" 'BEGIN { exit !(lo > 0 && hi - lo <= 15) }'; then
    pass "the helper's footprint is the same after every cycle of two more 5K Editors opening and closing (${CYCLE_MIN} to ${CYCLE_MAX} MB)"
  else
    fail "the helper's footprint varies from ${CYCLE_MIN} to ${CYCLE_MAX} MB over cycles of opening and closing 5K Editors"
  fi
  # Windows as big as they get (80% of the screen) still cascade onto spots of their own.
  ORIGINS="$(send "$EDITOR_SOCK" "editor-facts $KEEP" | sed -n 's/^window-origin=//p')"
  BIG_EDITORS="$KEEP"
  for i in 1 2 3 4 5; do
    capture_into_editor "menu-click capture.screen"
    ORIGINS="$ORIGINS
$(send "$EDITOR_SOCK" "editor-facts $EDITOR_N" | sed -n 's/^window-origin=//p')"
    BIG_EDITORS="$BIG_EDITORS $EDITOR_N"
  done
  expect_equal "six big Editors are on six different spots" "6" "$(printf '%s\n' "$ORIGINS" | sort -u | wc -l | tr -d ' ')"
  for n in $BIG_EDITORS; do [[ "$n" == "$KEEP" ]] || send_slow "$EDITOR_SOCK" "editor-press $n delete-capture" >/dev/null; done
  wait_until 10 bash -c "[[ \"\$(printf 'editors\n' | nc -U -w 2 '$EDITOR_SOCK')\" == '$KEEP' ]]"
  sleep 1
  assert_idle_cpu "the helper with a 5K Editor open after the cycles" "$KEEP_HELPER" 3
  send_slow "$EDITOR_SOCK" "editor-key $KEEP escape" >/dev/null
  wait_until 10 gone "$KEEP_HELPER"
fi
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null

# 7. Quit from the menu bar app's "Quit snapit". With an older Editor holding unexported edits it
#    brings that Editor forward and asks; Cancel (or Esc) keeps snapit running;
#    Discard quits and the Last Capture goes. With several, the oldest is the one asked about.
quit_menu_bg() { send_slow "$APP_SOCK" "menu-click quit" >"$RUN_ROOT/quit-menu.txt" 2>&1 & QUIT_PID=$!; }
if pair; then
  edit "$A"
  OLD_APP="$APP_PID"
  OLD_HELPER="$HELPER_PID"
  expect_equal "the Last Capture's Editor is in front of the older one" "$B" "$(send "$EDITOR_SOCK" editor-front)"
  quit_menu_bg
  if pr_wait_shown; then pass "Quit snapit with an older Editor holding unexported edits asks"; else fail "Quit snapit did not ask"; fi
  PROMPT="$(pr_prompt)"
  expect_contains "the prompt is the Quit prompt, about the older Editor" "shown quit editor=$A title=Quit snapit?" "$PROMPT"
  expect_contains "it counts the Capture" "This Capture has edits you haven't Exported" "$PROMPT"
  expect_contains "its buttons are Cancel and Discard and Quit" "buttons=Cancel,Discard and Quit" "$PROMPT"
  expect_equal "that Editor was brought forward first" "$A" "$(send "$EDITOR_SOCK" editor-front)"
  expect_equal "snapit is still running while it asks" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  pr_answer cancel
  wait "$QUIT_PID"
  sleep 0.5
  expect_equal "Cancel keeps snapit running" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  expect_equal "and the Editor helper" "yes" "$(kill -0 "$OLD_HELPER" 2>/dev/null && echo yes)"
  expect_equal "and both Editors open" "$(printf '%s\n%s' "$A" "$B")" "$(open_editors)"
  expect_equal "and the menu bar app still answers" "pong" "$(send "$APP_SOCK" ping)"
  # Esc cancels too.
  quit_menu_bg
  pr_wait_shown
  send "$EDITOR_SOCK" "editor-prompt-answer escape" >/dev/null
  wait "$QUIT_PID"
  sleep 0.5
  expect_equal "Esc on the Quit prompt keeps snapit running" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  # Discard quits.
  quit_menu_bg
  pr_wait_shown
  send "$EDITOR_SOCK" "editor-prompt-answer discard" >/dev/null
  wait "$QUIT_PID"
  if wait_until 10 gone "$OLD_APP"; then pass "Discard and Quit quits snapit"; else fail "snapit is still running after Discard and Quit"; fi
  if wait_until 10 gone "$OLD_HELPER"; then pass "and the Editor helper with it"; else fail "the helper outlived snapit"; fi
  sleep 1
  expect_equal "the Last Capture is gone with it" "none" "$(ls -A "$PCAPS" 2>/dev/null || echo none)"
  restart_app
fi

# Several older Editors with unexported edits: the oldest is brought forward and asked about, once.
if capture_into_editor "menu-click capture.screen"; then
  X="$EDITOR_N"
  capture_into_editor "menu-click capture.screen"; Y="$EDITOR_N"
  capture_into_editor "menu-click capture.screen"; Z="$EDITOR_N"
  edit "$Y"
  edit "$X"
  edit "$Z"
  OLD_APP="$APP_PID"
  quit_menu_bg
  pr_wait_shown
  PROMPT="$(pr_prompt)"
  expect_contains "with several Editors holding unexported edits the oldest is asked about" "shown quit editor=$X" "$PROMPT"
  expect_contains "the prompt counts them (the Last Capture's Editor does not count)" "2 Captures have edits you haven't Exported" "$PROMPT"
  expect_equal "the oldest of them was brought forward" "$X" "$(send "$EDITOR_SOCK" editor-front)"
  pr_answer cancel
  wait "$QUIT_PID"
  sleep 0.5
  expect_equal "Cancel keeps snapit running" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  # Exporting the oldest leaves one at risk: the prompt is about the next.
  send_slow "$EDITOR_SOCK" "editor-press $X copy" >/dev/null
  quit_menu_bg
  pr_wait_shown
  expect_contains "after the oldest was Exported the next one is asked about" "shown quit editor=$Y" "$(pr_prompt)"
  expect_contains "and it is one Capture" "This Capture has edits" "$(pr_prompt)"
  pr_answer cancel
  wait "$QUIT_PID"
  # Nothing at risk once the other is Exported too: Quit goes straight through, no prompt.
  send_slow "$EDITOR_SOCK" "editor-press $Y save" >/dev/null
  send_slow "$APP_SOCK" "menu-click quit" >/dev/null
  if wait_until 10 gone "$OLD_APP"; then pass "Quit snapit asks nothing when every older Editor was Exported (the Last Capture's edits never count)"; else fail "Quit snapit did not go through, or asked"; fi
  expect_equal "no prompt is showing" "none" "$(pr_prompt)"
  wait_until 10 bash -c "[[ -z \"\$(pgrep -f '$HELPER_EXE' | head -1)\" ]]"
  expect_equal "the helper quit with it" "" "$(helper_pid)"
  restart_app
fi

# 7b. A quit nobody was asked about (logout, `osascript` quit, Activity Monitor) is an AppleEvent to
#     the menu bar app: it asks the helper first, and Cancel leaves everything running. Two askers at
#     once (the system quits both processes at logout) get one question and the same answer.
if pair; then
  edit "$A"
  OLD_APP="$APP_PID"
  OLD_HELPER="$HELPER_PID"
  expect_equal "the quit AppleEvent is sent to the menu bar app" "ok" "$(send "$APP_SOCK" quit-event)"
  if pr_wait_shown; then pass "a quit AppleEvent with an older Editor holding unexported edits asks"; else fail "a quit AppleEvent quit snapit without asking"; fi
  expect_contains "the Quit prompt, about the older Editor" "shown quit editor=$A" "$(pr_prompt)"
  expect_equal "that Editor was brought forward" "$A" "$(send "$EDITOR_SOCK" editor-front)"
  pr_answer cancel
  sleep 1
  expect_equal "Cancel leaves the menu bar app running" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  expect_equal "and the helper" "yes" "$(kill -0 "$OLD_HELPER" 2>/dev/null && echo yes)"
  expect_equal "and both Editors" "$(printf '%s\n%s' "$A" "$B")" "$(open_editors)"
  # Two askers at once: the AppleEvent to the menu bar app and the helper's own Quit.
  send "$APP_SOCK" quit-event >/dev/null
  send "$EDITOR_SOCK" editor-menu-quit >/dev/null
  pr_wait_shown
  sleep 0.5
  expect_equal "two askers get one question" "1" "$(pr_prompt | grep -c '^shown')"
  pr_answer cancel
  sleep 1
  expect_equal "and Cancel answers both: snapit is still running" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  expect_equal "and the helper" "yes" "$(kill -0 "$OLD_HELPER" 2>/dev/null && echo yes)"
  # Discard through the AppleEvent: the whole of snapit goes and the Last Capture with it.
  send "$APP_SOCK" quit-event >/dev/null
  pr_wait_shown
  send "$EDITOR_SOCK" "editor-prompt-answer discard" >/dev/null
  if wait_until 15 gone "$OLD_APP"; then pass "Discard and Quit after a quit AppleEvent quits snapit"; else fail "snapit is still running after Discard and Quit"; fi
  if wait_until 10 gone "$OLD_HELPER"; then pass "and the helper"; else fail "the helper did not quit"; fi
  sleep 1
  expect_equal "the Last Capture is gone" "none" "$(ls -A "$PCAPS" 2>/dev/null || echo none)"
  restart_app
fi
# The helper's own AppleEvent (the Dock's Quit): the same question, and it quits snapit as a whole.
if pair; then
  edit "$A"
  OLD_APP="$APP_PID"
  OLD_HELPER="$HELPER_PID"
  expect_equal "the quit AppleEvent is sent to the helper" "ok" "$(send "$EDITOR_SOCK" quit-event)"
  if pr_wait_shown; then pass "a quit AppleEvent to the helper asks"; else fail "the helper quit without asking"; fi
  pr_answer cancel
  sleep 1
  expect_equal "Cancel leaves the helper running" "yes" "$(kill -0 "$OLD_HELPER" 2>/dev/null && echo yes)"
  expect_equal "and the menu bar app" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  send "$EDITOR_SOCK" quit-event >/dev/null
  pr_wait_shown
  send "$EDITOR_SOCK" "editor-prompt-answer discard" >/dev/null
  if wait_until 15 gone "$OLD_HELPER"; then pass "Discard and Quit quits the helper"; else fail "the helper is still running after Discard and Quit"; fi
  if wait_until 15 gone "$OLD_APP"; then pass "and snapit with it: to the user it is one app"; else fail "the menu bar app outlived the helper's Quit"; fi
  sleep 1
  expect_equal "the Last Capture is gone" "none" "$(ls -A "$PCAPS" 2>/dev/null || echo none)"
  restart_app
fi
# Two `confirm-quit` at once (the helper is what both processes ask) share one question.
if pair; then
  edit "$A"
  send_slow "$EDITOR_SOCK" confirm-quit >"$RUN_ROOT/confirm-1.txt" 2>&1 &
  CONFIRM_1=$!
  pr_wait_shown
  send_slow "$EDITOR_SOCK" confirm-quit >"$RUN_ROOT/confirm-2.txt" 2>&1 &
  CONFIRM_2=$!
  sleep 0.7
  expect_equal "two confirm-quit commands show one question" "1" "$(pr_prompt | grep -c '^shown')"
  pr_answer cancel
  wait "$CONFIRM_1" "$CONFIRM_2"
  expect_equal "the first asker is told cancel" "cancel" "$(cat "$RUN_ROOT/confirm-1.txt")"
  expect_equal "and the second the same" "cancel" "$(cat "$RUN_ROOT/confirm-2.txt")"
  end_pair
fi

# 8. The helper's own "Quit snapit" asks the same, and Cancel keeps snapit running.
if pair; then
  edit "$A"
  OLD_APP="$APP_PID"
  OLD_HELPER="$HELPER_PID"
  expect_equal "the helper's Quit snapit is chosen" "ok" "$(send "$EDITOR_SOCK" editor-menu-quit)"
  if pr_wait_shown; then pass "the helper's own Quit snapit asks too"; else fail "the helper's Quit snapit did not ask"; fi
  expect_contains "about the older Editor" "shown quit editor=$A" "$(pr_prompt)"
  expect_equal "and brought it forward" "$A" "$(send "$EDITOR_SOCK" editor-front)"
  pr_answer cancel
  sleep 0.7
  expect_equal "Cancel keeps snapit running" "yes" "$(kill -0 "$OLD_APP" 2>/dev/null && echo yes)"
  expect_equal "and the helper" "yes" "$(kill -0 "$OLD_HELPER" 2>/dev/null && echo yes)"
  send "$EDITOR_SOCK" editor-menu-quit >/dev/null
  pr_wait_shown
  assert_idle_cpu "the helper while the Quit prompt shows" "$OLD_HELPER" 3
  send "$EDITOR_SOCK" "editor-prompt-answer discard" >/dev/null
  if wait_until 15 gone "$OLD_APP"; then pass "Discard and Quit from the helper quits snapit"; else fail "snapit is still running after the helper's Discard and Quit"; fi
  if wait_until 10 gone "$OLD_HELPER"; then pass "and the helper"; else fail "the helper did not quit"; fi
  sleep 1
  expect_equal "the Last Capture is gone" "none" "$(ls -A "$PCAPS" 2>/dev/null || echo none)"
  restart_app
fi

# 9. Quit asks nothing when only the Last Capture's Editor has edits, or when no Editor is open.
if capture_into_editor "menu-click capture.screen"; then
  edit "$EDITOR_N"
  OLD_APP="$APP_PID"
  send_slow "$APP_SOCK" "menu-click quit" >/dev/null
  if wait_until 10 gone "$OLD_APP"; then pass "Quit snapit with only the Last Capture's Editor holding edits asks nothing"; else fail "Quit snapit is waiting on a prompt for the Last Capture's Editor"; fi
  wait_until 10 gone "$HELPER_PID"
  restart_app
fi
OLD_APP="$APP_PID"
send_slow "$APP_SOCK" "menu-click quit" >/dev/null
if wait_until 10 gone "$OLD_APP"; then pass "Quit snapit with no Editor open quits at once"; else fail "Quit snapit with no Editor open did not quit"; fi
restart_app

send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterSave true" >/dev/null
