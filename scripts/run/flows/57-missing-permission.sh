# Flow: a permission that is missing. (1) A Capture Shortcut or menu item pressed without Screen
# Recording shows the Permission guide (Onboarding when that is unfinished) instead of failing
# silently, in every state the permission can be in: never granted, granted to the build before the
# update, turned off, granted but waiting for a relaunch; nothing is captured and nothing is left
# running, and once granted (through Relaunch snapit) Captures work. (2) A Save into a folder that
# can't be written to keeps the Editor open and shows the folder Permission guide, worded for the
# cause (only a macOS privacy denial mentions macOS), with "Choose another folder", "Open System
# Settings" and "Try again". (3) A Save that fails after it was handed over, when the Editor may be
# gone, shows the same window from the helper, started for it. The fake macOS, the fixture `tccutil`
# and test seams for the errno macOS would give stand in for the real prompts. Sourced by
# scripts/check-run.sh.
# shellcheck shell=bash

MP_SAVE="$RUN_ROOT/save"
MP_ELSEWHERE="$RUN_ROOT/save-elsewhere"
MP_GONE="$RUN_ROOT/save-gone"
MP_SAVE_BEFORE="$(send "$APP_SOCK" test-seams | sed -n 's/^save=//p')"
MP_FOOT_BEFORE="$(footprint_mb "$APP_PID")"
mkdir -p "$MP_SAVE" "$MP_ELSEWHERE"

mp_gf() { send "$EDITOR_SOCK" "guide-facts $1" | sed -n "s/^$2=//p" | head -1; }
mp_facts() { send "$EDITOR_SOCK" "guide-facts $1"; }
mp_sr() { send "$APP_SOCK" screen-recording-facts | sed -n "s/^$1=//p"; }
mp_no_helper() { [[ -z "$(helper_pid)" ]]; }
mp_guide_visible() { [[ "$(mp_gf "$1" window)" == visible ]]; }
mp_guide_gone() { [[ "$(mp_gf "$1" window)" == none ]]; }
mp_guide_is() { [[ "$(mp_gf "$1" "$2")" == "$3" ]]; }
mp_onb() { send "$EDITOR_SOCK" onboarding-facts | sed -n "s/^$1=//p" | head -1; }
mp_onb_visible() { [[ "$(mp_onb window)" == visible ]]; }
mp_onb_is() { [[ "$(mp_onb "$1")" == "$2" ]]; }
mp_saved_pngs() { ls -A "$1" 2>/dev/null | grep -c '^snapit-.*\.png$'; }
mp_save_idle() { [[ "$(send "$APP_SOCK" save-pending)" == "0" ]]; }
mp_close_windows() {
  send "$EDITOR_SOCK" "guide-close" >/dev/null 2>&1
  send "$EDITOR_SOCK" "guide-close folder" >/dev/null 2>&1
  send "$EDITOR_SOCK" onboarding-close >/dev/null 2>&1
  wait_until 10 mp_no_helper
}
mp_clear_save() { chmod 700 "$MP_SAVE" 2>/dev/null; find "$MP_SAVE" -mindepth 1 -delete 2>/dev/null; }
mp_restart_app() {
  send "$APP_SOCK" quit >/dev/null
  wait_until 30 gone "$APP_PID"
  (nohup "$APP_EXE" >>"$RUN_ROOT/app.log" 2>&1 &)
  if wait_until 15 answers "$APP_SOCK"; then pass "snapit starts again ($1)"; else abort "snapit did not start again ($1)"; fi
  APP_PID="$(pid_of "$APP_EXE")"
}
mp_new_app() { local now; now="$(pid_of "$APP_EXE")"; [[ -n "$now" && "$now" != "$1" ]] && answers "$APP_SOCK"; }
mp_links() { cat "$RUN_ROOT/system-settings-links" 2>/dev/null; }

send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
mp_close_windows

# 1. A Shortcut or a menu item that starts a Capture, with Screen Recording missing, shows the guide.
#    Nothing is captured, no Editor and no overlay is left, and the helper that shows the guide is the
#    only helper (no warm-up is left behind): closing the guide ends it.
MP_TRIGGERS=("press-shortcut capture-screen" "press-shortcut capture-area" "press-shortcut capture-window" "press-shortcut pick-color"
  "menu-click capture.screen" "menu-click capture.area" "menu-click capture.window" "menu-click capture.pick-color")
send "$APP_SOCK" "screen-recording-simulate turnedOff" >/dev/null
MP_REQUESTS_START="$(mp_sr requests)"
MP_RESETS_START="$(mp_sr resets)"
CAPTURE_BEFORE="$(send "$APP_SOCK" last-capture)"
for trigger in "${MP_TRIGGERS[@]}"; do
  send_slow "$APP_SOCK" "$trigger" >/dev/null
  if wait_until 15 mp_guide_visible ""; then pass "$trigger with Screen Recording off shows the Permission guide"; else fail "$trigger with Screen Recording off showed no guide"; fi
  expect_equal "$trigger took no Capture" "$CAPTURE_BEFORE" "$(send "$APP_SOCK" last-capture)"
  expect_equal "$trigger opened no Editor" "" "$(open_editors)"
  expect_equal "$trigger left the guide's helper as the only window owner (a regular app: Dock icon)" "regular" "$(mp_gf "" activation)"
  case "$trigger" in *area* | *window* | *pick*)
    expect_equal "$trigger left no overlay behind" "permission-needed" "$(send "$APP_SOCK" overlay-wait)" ;;
  esac
  mp_close_windows
  if mp_no_helper; then pass "closing the guide ends the helper after $trigger"; else fail "a helper is left after $trigger"; fi
done
expect_equal "snapit asked macOS for nothing: it was switched off, and macOS does not ask again" "$MP_REQUESTS_START" "$(mp_sr requests)"
expect_equal "and reset nothing" "$MP_RESETS_START" "$(mp_sr resets)"
expect_equal "no Capture file was left behind" "" "$(capture_files)"

# 2. The state the permission is in decides what the guide says and asks.
mp_case() { # label, simulate state, requests added, resets added, guide-state, update, headline
  local label="$1" requests resets
  send "$APP_SOCK" "screen-recording-simulate $2" >/dev/null
  requests="$(mp_sr requests)"
  resets="$(mp_sr resets)"
  send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
  if wait_until 15 mp_guide_visible ""; then pass "$label: the Shortcut shows the guide"; else fail "$label: no guide"; fi
  wait_until 10 mp_guide_is "" guide-state "$5"
  expect_equal "$label: the guide's state" "$5" "$(mp_gf "" guide-state)"
  expect_equal "$label: times macOS was asked" "$((requests + $3))" "$(mp_sr requests)"
  expect_equal "$label: times snapit's own entry was reset" "$((resets + $4))" "$(mp_sr resets)"
  expect_equal "$label: worded for an update or not" "$6" "$(mp_gf "" guide-update)"
  expect_equal "$label: headline" "$7" "$(mp_gf "" guide-headline)"
  if [[ "$(mp_gf "" guide-message)" == *toggle* || "$(mp_gf "" guide-message)" == *"already"* ]]; then fail "$label: the guide tells people to toggle an existing switch: $(mp_gf "" guide-message)"; else pass "$label: the guide never tells people to toggle an existing switch"; fi
  mp_close_windows
}
mp_case "never granted" notDetermined 1 0 denied no "Turn on Screen Recording for snapit"
mp_case "granted before an update" grantedStale 1 1 denied yes "snapit needs Screen Recording turned back on"
mp_case "asked and denied" denied 0 0 denied no "Turn on Screen Recording for snapit"
mp_case "turned off" turnedOff 0 0 denied no "Turn on Screen Recording for snapit"
expect_equal "turned off says so" "Screen Recording is off for snapit. Turn snapit on in System Settings, then choose Quit & Reopen." "$(send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null; wait_until 15 mp_guide_visible ""; mp_gf "" guide-message)"
mp_close_windows

# 3. A press while the guide is open brings it forward: still one window, one more look.
send "$APP_SOCK" "screen-recording-simulate denied" >/dev/null
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
wait_until 15 mp_guide_visible ""
CHECKS_BEFORE="$(mp_gf "" guide-checks)"
send_slow "$APP_SOCK" "press-shortcut capture-area" >/dev/null
mp_checked_again() { (($(mp_gf "" guide-checks) > CHECKS_BEFORE)); }
wait_until 10 mp_checked_again
if mp_checked_again; then pass "a second press looks at the permission again in the same window"; else fail "a second press did not look again"; fi
expect_equal "and still shows one guide window" "1" "$(onscreen_windows "$(helper_pid)")"
mp_close_windows

# 4. Onboarding unfinished: the press opens Onboarding, never a second window that asks macOS too.
send "$APP_SOCK" "defaults-set onboardingStep screenRecording" >/dev/null
send "$APP_SOCK" "screen-recording-simulate notDetermined" >/dev/null
REQUESTS_BEFORE="$(mp_sr requests)"
send_slow "$APP_SOCK" "menu-click capture.screen" >/dev/null
if wait_until 15 mp_onb_visible; then pass "a menu item with Onboarding unfinished shows Onboarding"; else fail "Onboarding did not show"; fi
expect_equal "and no standalone Permission guide" "window=none" "$(mp_facts "")"
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
expect_equal "a Shortcut shows Onboarding too, still no standalone guide" "window=none" "$(mp_facts "")"
wait_until 10 mp_onb_is guide-state denied
expect_equal "macOS was asked once, by Onboarding's own guide" "$((REQUESTS_BEFORE + 1))" "$(mp_sr requests)"
mp_close_windows
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null

# 5. Granting works end to end: after an update (granted to the build before) a press shows the guide
#    and resets snapit's own entry; the user turns it on; macOS lets a process use it from its next
#    launch on, so the guide offers Relaunch snapit; and after it Captures work.
send "$APP_SOCK" "screen-recording-simulate grantedStale" >/dev/null
mp_restart_app "launched without Screen Recording"
RESETS_BEFORE="$(mp_sr resets)"
CAPTURE_BEFORE="$(send "$APP_SOCK" last-capture)"
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
wait_until 15 mp_guide_visible ""
wait_until 10 mp_guide_is "" guide-state denied
expect_equal "the press after an update reset snapit's own entry once" "$((RESETS_BEFORE + 1))" "$(mp_sr resets)"
expect_equal "the guide is worded for the update" "yes" "$(mp_gf "" guide-update)"
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
expect_equal "once granted, the state waits for a relaunch" "grantedNeedsRelaunch" "$(mp_sr state)"
send "$EDITOR_SOCK" guide-activate >/dev/null
expect_equal "coming back to the window, the guide says so" "grantedNeedsRelaunch" "$(mp_gf "" guide-state)"
expect_contains "it offers Relaunch snapit" "button relaunch|Relaunch snapit|" "$(mp_facts "")"
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
expect_equal "a press while it waits for the relaunch still takes no Capture" "$CAPTURE_BEFORE" "$(send "$APP_SOCK" last-capture)"
expect_equal "and still shows the guide" "visible" "$(mp_gf "" window)"
OLD_APP_PID="$APP_PID"
send "$EDITOR_SOCK" "guide-press relaunch" >/dev/null
if wait_until 30 mp_new_app "$OLD_APP_PID"; then pass "Relaunch snapit starts a new snapit"; else fail "snapit did not relaunch"; fi
APP_PID="$(pid_of "$APP_EXE")"
expect_equal "the relaunched snapit has Screen Recording" "granted" "$(mp_sr state)"
mp_close_windows
mp_restart_app "its log is the run's again"
if capture_into_editor "press-shortcut capture-screen"; then pass "a Capture works after the guide, the grant and the relaunch"; else fail "no Capture after granting"; fi
mp_close_windows_editor() { send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null 2>&1; wait_until 10 mp_no_helper; }
mp_close_windows_editor

# 6. Folder access, from an Editor. The Save is refused, the Editor stays open and the folder guide
#    says why, worded for the cause. Only a macOS privacy denial (EPERM) talks about macOS.
send "$APP_SOCK" "defaults-set closeEditorAfterSave false" >/dev/null
mp_clear_save
if ! capture_into_editor "press-shortcut capture-screen"; then abort "no Capture for the folder guide"; fi
MP_EDITOR="$EDITOR_N"
MP_HELPER="$HELPER_PID"
mp_save() { send_slow "$EDITOR_SOCK" "editor-press $MP_EDITOR save" >/dev/null; }
mp_fail_cause() { # label, cause, errno, words that must be in the message, words that must not
  local label="$1"
  if wait_until 15 mp_guide_visible folder; then pass "$label: the folder guide shows"; else fail "$label: no folder guide"; return; fi
  expect_equal "$label: cause" "$2" "$(mp_gf folder guide-cause)"
  expect_equal "$label: errno" "$3" "$(mp_gf folder guide-code)"
  expect_contains "$label: the message says what is wrong" "$4" "$(mp_gf folder guide-message)"
  if [[ -n "$5" && "$(mp_gf folder guide-message)" == *"$5"* ]]; then fail "$label: the message says '$5': $(mp_gf folder guide-message)"; else pass "$label: the message does not say '${5:-anything it should not}'"; fi
  expect_equal "$label: the Editor stays open" "$MP_EDITOR" "$(open_editors | tail -1)"
  expect_equal "$label: the same helper keeps running" "$MP_HELPER" "$(helper_pid)"
  expect_contains "$label: Choose another folder is offered" "button choose-folder|Choose another folder|" "$(mp_facts folder)"
  expect_contains "$label: Try again is offered, the Editor being open" "button retry|Try again|" "$(mp_facts folder)"
  if mp_facts folder | grep '^button ' | awk -F'|' '$3 == "" { bad = 1 } END { exit bad }'; then pass "$label: every button has a tooltip"; else fail "$label: a button has no tooltip"; fi
}

# 6a. EACCES: ordinary file permissions (a real read-only folder).
chmod 500 "$MP_SAVE"
mp_save
mp_fail_cause "an unwritable folder" notPermitted 13 "can't be written to" "macOS"
expect_contains "the message names the folder" "$MP_SAVE" "$(mp_gf folder guide-message)"
expect_equal "no System Settings button for a cause that is not macOS access" "" "$(mp_facts folder | grep '^button open-system-settings|')"
expect_equal "no animation for it" "idle" "$(mp_gf folder guide-animation)"
expect_equal "the guide is a regular window of the helper" "regular" "$(mp_gf folder activation)"
expect_equal "the Save never happened" "0" "$(mp_saved_pngs "$MP_SAVE")"
MP_WINDOWS="$(onscreen_windows "$MP_HELPER")"
# Try again while the folder is still closed: the same guide, a second failure.
send_slow "$EDITOR_SOCK" "guide-press folder retry" >/dev/null
wait_until 10 mp_guide_is folder guide-failures 2
expect_equal "a second refusal updates the open guide" "2" "$(mp_gf folder guide-failures)"
expect_equal "and it is still one guide window (the Editor and one guide)" "$MP_WINDOWS" "$(onscreen_windows "$MP_HELPER")"
chmod 700 "$MP_SAVE"
send_slow "$EDITOR_SOCK" "guide-press folder retry" >/dev/null
wait_until 15 mp_guide_gone folder
expect_equal "Try again, once the folder opens, saves from the Editor that stayed open" "1" "$(mp_saved_pngs "$MP_SAVE")"
expect_equal "the guide closed itself" "window=none" "$(mp_facts folder)"
expect_equal "the Editor is still open" "$MP_EDITOR" "$(open_editors | tail -1)"
expect_equal "and the helper with it" "$MP_HELPER" "$(helper_pid)"
expect_equal "the Save was handed over" "handed-over" "$(send "$EDITOR_SOCK" "editor-save-outcome $MP_EDITOR")"
wait_until 15 mp_save_idle

# 6b. Choose another folder: it becomes the Save location and the Capture is saved there at once.
mp_clear_save
chmod 500 "$MP_SAVE"
mp_save
mp_fail_cause "an unwritable folder again" notPermitted 13 "can't be written to" "macOS"
expect_equal "the chooser is a real panel: a run names the folder with its own command" "error folder must be inside the test root" "$(send "$EDITOR_SOCK" "guide-choose-folder /tmp")"
send_slow "$EDITOR_SOCK" "guide-choose-folder $MP_ELSEWHERE" >/dev/null
wait_until 15 mp_guide_gone folder
wait_until 15 mp_save_idle
expect_equal "choosing another folder saves the Capture there" "1" "$(mp_saved_pngs "$MP_ELSEWHERE")"
expect_equal "the Save location is the chosen folder" "$MP_ELSEWHERE" "$(send "$APP_SOCK" test-seams | sed -n 's/^save=//p')"
expect_equal "the folder that was refused got nothing" "0" "$(mp_saved_pngs "$MP_SAVE")"
send "$APP_SOCK" "defaults-set saveLocation $MP_SAVE" >/dev/null
chmod 700 "$MP_SAVE"

# 6c. EPERM, macOS privacy (a test seam gives the errno a denied Documents or Desktop prompt gives).
mp_clear_save
send "$APP_SOCK" "save-fail-check 1" >/dev/null
mp_save
mp_fail_cause "a folder macOS denied" privacy 1 "macOS is not letting snapit write" "zzz"
expect_contains "it points at Files & Folders" "Files & Folders" "$(mp_gf folder guide-message)"
expect_contains "and offers Open System Settings" "button open-system-settings|Open System Settings|" "$(mp_facts folder)"
: >"$RUN_ROOT/system-settings-links"
send "$EDITOR_SOCK" "guide-press folder open-system-settings" >/dev/null
expect_contains "Open System Settings goes to Files and Folders" "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders" "$(mp_links)"
expect_equal "the animation plays while the guide is visible" "playing" "$(mp_gf folder guide-animation)"
PLAYS_BEFORE="$(mp_gf folder guide-plays)"
send "$EDITOR_SOCK" "guide-hide folder" >/dev/null
wait_until 5 mp_guide_is folder guide-animation idle
expect_equal "hiding the window cancels it" "idle" "$(mp_gf folder guide-animation)"
send "$EDITOR_SOCK" "guide-unhide folder" >/dev/null
wait_until 5 mp_guide_is folder guide-animation playing
PLAYS_AFTER="$(mp_gf folder guide-plays)"
expect_equal "showing it again plays it again" "$((PLAYS_BEFORE + 1))" "$PLAYS_AFTER"
MP_LOOP_SECONDS=$(($(mp_gf folder guide-loops) * $(mp_gf folder guide-loop-seconds)))
if wait_until $((MP_LOOP_SECONDS + 6)) mp_guide_is folder guide-animation stopped; then pass "the animation is finite: it stops after $(mp_gf folder guide-loops) loops"; else fail "the animation never stopped"; fi
expect_contains "when it stops Replay is offered" "button replay|Replay|" "$(mp_facts folder)"
send "$EDITOR_SOCK" "guide-snapshot folder $RUN_ROOT/folder-guide.png" >/dev/null
[[ -s "$RUN_ROOT/folder-guide.png" ]] && pass "the folder guide renders" || fail "the folder guide did not render"
assert_idle_cpu "the helper with the folder guide, the animation stopped," "$(helper_pid)" "$IDLE_SECONDS"
send "$APP_SOCK" "save-fail-check off" >/dev/null
send_slow "$EDITOR_SOCK" "guide-press folder retry" >/dev/null
wait_until 15 mp_guide_gone folder
wait_until 15 mp_save_idle
expect_equal "once macOS lets snapit in, Try again saves" "1" "$(mp_saved_pngs "$MP_SAVE")"

# 6d. ENOENT: the folder is gone (an unplugged drive).
send "$APP_SOCK" "defaults-set saveLocation $MP_GONE" >/dev/null
mp_save
mp_fail_cause "a folder that is gone" missing 2 "not there any more" "macOS"
mkdir -p "$MP_GONE"
send_slow "$EDITOR_SOCK" "guide-press folder retry" >/dev/null
wait_until 15 mp_guide_gone folder
wait_until 15 mp_save_idle
expect_equal "the drive comes back and Try again saves into it" "1" "$(mp_saved_pngs "$MP_GONE")"
rm -rf "$MP_GONE"

# 6e. EROFS: a read-only volume (a test seam: a run makes no read-only volume).
send "$APP_SOCK" "defaults-set saveLocation $MP_SAVE" >/dev/null
send "$APP_SOCK" "save-fail-check 30" >/dev/null
mp_save
mp_fail_cause "a read-only disk" readOnly 30 "read-only" "macOS"
send "$APP_SOCK" "save-fail-check off" >/dev/null
send_slow "$EDITOR_SOCK" "guide-press folder retry" >/dev/null
wait_until 15 mp_guide_gone folder
wait_until 15 mp_save_idle

# 6f. The Editor of the failed Save closes: the guide has nothing to retry, the helper quits with it.
chmod 500 "$MP_SAVE"
mp_save
wait_until 15 mp_guide_visible folder
send_slow "$EDITOR_SOCK" "editor-key $MP_EDITOR escape" >/dev/null 2>&1
sleep 1
expect_contains "after its Editor closed, the guide offers no Try again" "guide-retry=unavailable" "$(mp_facts folder)"
expect_contains "but still Choose another folder" "button choose-folder|" "$(mp_facts folder)"
expect_equal "the guide alone keeps the helper running" "visible" "$(mp_gf folder window)"
send "$EDITOR_SOCK" "guide-close folder" >/dev/null
if wait_until 10 mp_no_helper; then pass "the helper quits after the folder guide closes with no Editor open"; else fail "the helper outlived the folder guide"; fi
chmod 700 "$MP_SAVE"
mp_clear_save

# 7. A Save that fails after it was handed over, with the Editor gone: the menu bar app asks the helper
#    for a window of its own. The Capture was not saved, so it offers no Try again.
send "$APP_SOCK" "defaults-set closeEditorAfterSave true" >/dev/null
if ! capture_into_editor "press-shortcut capture-screen"; then abort "no Capture for the failed Save"; fi
MP_EDITOR="$EDITOR_N"
send "$APP_SOCK" save-hold >/dev/null
send_slow "$EDITOR_SOCK" "editor-press $MP_EDITOR save" >/dev/null
if wait_until 10 mp_no_helper; then pass "the Editor closed and the helper quit after Save, the write still pending"; else fail "the helper did not quit"; fi
chmod 500 "$MP_SAVE"
send "$APP_SOCK" save-release >/dev/null
if wait_until 20 mp_guide_visible folder; then pass "a Save that failed after the hand-over shows the guide, in a helper started for it"; else fail "no window for a Save that failed after the hand-over"; fi
expect_equal "it names the cause" "notPermitted" "$(mp_gf folder guide-cause)"
expect_equal "it says the Capture was not saved" "yes" "$([[ "$(mp_gf folder guide-message)" == *"was not saved"* ]] && echo yes || echo no)"
expect_equal "there is nothing to try again" "guide-retry=unavailable" "$(mp_facts folder | grep '^guide-retry=')"
expect_contains "but another folder can be chosen for the next Save" "button choose-folder|Choose another folder|" "$(mp_facts folder)"
expect_equal "the helper's guide is a regular app while it shows (Dock icon)" "regular" "$(mp_gf folder activation)"
if is_foreground "$(helper_pid)"; then pass "the helper has a Dock icon while the window shows"; else fail "the helper has no Dock icon"; fi
expect_equal "no Editor is open" "" "$(open_editors)"
wait_until 15 mp_save_idle
expect_equal "nothing is pending" "0" "$(send "$APP_SOCK" save-pending)"
find "$MP_ELSEWHERE" -mindepth 1 -delete
expect_equal "the chooser is a real panel: a run names the folder with its own command" "error use guide-choose-folder <folder>" "$(send "$EDITOR_SOCK" "guide-press folder choose-folder")"
send_slow "$EDITOR_SOCK" "guide-choose-folder $MP_ELSEWHERE" >/dev/null
if wait_until 10 mp_no_helper; then pass "choosing another folder finishes the guide, and the helper quits with its window"; else fail "the guide stayed after a folder was chosen"; fi
expect_equal "the chosen folder is the Save location for the next Save" "$MP_ELSEWHERE" "$(send "$APP_SOCK" test-seams | sed -n 's/^save=//p')"
expect_equal "nothing was saved by the choice: the Capture was not saved" "0" "$(mp_saved_pngs "$MP_ELSEWHERE")"
send "$APP_SOCK" "defaults-set saveLocation $MP_SAVE" >/dev/null
chmod 700 "$MP_SAVE"
mp_clear_save

# 7a. The same failure with the helper still quitting: close after Save is on, so the Editor closes and the
#     helper starts to quit while the (instant) failure is reported. The window must still show: a helper
#     that is quitting because its last window closed stays when the menu bar app has asked for a window.
send "$APP_SOCK" "save-fail-write 28" >/dev/null
for round in 1 2 3 4 5; do
  if ! capture_into_editor "press-shortcut capture-screen"; then fail "no Capture for round $round"; continue; fi
  MP_EDITOR="$EDITOR_N"
  send_slow "$EDITOR_SOCK" "editor-press $MP_EDITOR save" >/dev/null
  if wait_until 20 mp_guide_visible folder; then pass "round $round: a failure right after Save closed the Editor still shows the guide"; else fail "round $round: the guide was lost to the quitting helper"; fi
  expect_equal "round $round: the Editor is gone" "" "$(open_editors)"
  send "$EDITOR_SOCK" "guide-close folder" >/dev/null
  wait_until 10 mp_no_helper
done
send "$APP_SOCK" "save-fail-write off" >/dev/null

# 7b. The disk filled up after the hand-over (a test seam for the errno), with the Editor still open:
#     the window shows beside it, and closing it leaves the Editor and the helper alone.
send "$APP_SOCK" "defaults-set closeEditorAfterSave false" >/dev/null
send "$APP_SOCK" "save-fail-write 28" >/dev/null
if ! capture_into_editor "press-shortcut capture-screen"; then abort "no Capture for the full disk"; fi
MP_EDITOR="$EDITOR_N"
MP_HELPER="$HELPER_PID"
mp_save
if wait_until 20 mp_guide_visible folder; then pass "a full disk after the hand-over shows the guide"; else fail "no window for a full disk"; fi
send "$APP_SOCK" "save-fail-write off" >/dev/null
expect_equal "it names the cause" "diskFull" "$(mp_gf folder guide-cause)"
expect_contains "it says there is no space" "no space left" "$(mp_gf folder guide-message)"
expect_equal "no macOS access talk" "no" "$([[ "$(mp_gf folder guide-message)" == *macOS* ]] && echo yes || echo no)"
expect_equal "the Editor is open: the Capture can be saved from it again" "$MP_EDITOR" "$(open_editors | tail -1)"
expect_equal "nothing was written" "0" "$(mp_saved_pngs "$MP_SAVE")"
expect_equal "no partial file is left" "0" "$(ls -A "$MP_SAVE" | wc -l | tr -d ' ')"
send "$EDITOR_SOCK" "guide-close folder" >/dev/null
sleep 1
expect_equal "closing the window leaves the Editor open" "$MP_EDITOR" "$(open_editors | tail -1)"
expect_equal "and the same helper running" "$MP_HELPER" "$(helper_pid)"
mp_save
wait_until 15 mp_save_idle
expect_equal "the Editor Saves once the disk has room" "1" "$(mp_saved_pngs "$MP_SAVE")"
send_slow "$EDITOR_SOCK" "editor-key $MP_EDITOR escape" >/dev/null 2>&1
wait_until 10 mp_no_helper

# 8. Back to rest: memory and idle CPU of the menu bar app, and the run's settings put back.
mp_close_windows
mp_clear_save
sleep 2
MP_FOOT_AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$MP_FOOT_BEFORE" -v b="$MP_FOOT_AFTER" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(b > 0 && b - a <= max) }'; then
  pass "the menu bar app is back at its baseline after the permission flows (${MP_FOOT_BEFORE} MB before, ${MP_FOOT_AFTER} MB after)"
else
  fail "the menu bar app grew from ${MP_FOOT_BEFORE} MB to ${MP_FOOT_AFTER} MB over the permission flows"
fi
assert_idle_cpu "the menu bar app after the permission flows" "$APP_PID" "$IDLE_SECONDS"
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" "defaults-set saveLocation $MP_SAVE_BEFORE" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterSave true" >/dev/null
rm -rf "$MP_ELSEWHERE" "$MP_GONE"
