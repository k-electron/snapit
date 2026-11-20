# Flow: Onboarding and the Screen Recording Permission guide. Onboarding is a resumable window in
# the Editor helper with six steps (Welcome, Screen Recording, Save location, Shortcuts, Open at
# Login, Done). It opens at the first launch and at a Shortcut press until it is finished, resumes at
# the stored step, and never shows again once finished. The Permission guide plays a finite
# animation while it is visible, looks at Screen Recording only when the window becomes active, and
# covers every path through a fake macOS: never granted, "Don't Allow", turned on and relaunched
# (also through Relaunch snapit), and the update path (granted before, gone now: snapit clears its
# own entry through a fixture `tccutil` and asks afresh). Test mode starts Onboarding finished, so
# every other flow is untouched: this flow stores a step first. No real prompt, no real TCC
# database and no real `tccutil` are involved. Sourced by scripts/check-run.sh.
# shellcheck shell=bash

ONB_ELSEWHERE="$RUN_ROOT/save-onboarding"
ONB_SAVE_BEFORE="$(send "$APP_SOCK" test-seams | sed -n 's/^save=//p')"
ONB_LOGIN_BEFORE="$(send "$APP_SOCK" login-item-status)"
ONB_URL="x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
mkdir -p "$ONB_ELSEWHERE"

onb_facts() { send "$EDITOR_SOCK" onboarding-facts; }
onb() { onb_facts | sed -n "s/^$1=//p" | head -1; }
gfacts() { send "$EDITOR_SOCK" guide-facts; }
gf() { gfacts | sed -n "s/^$1=//p" | head -1; }
sr_fact() { send "$APP_SOCK" screen-recording-facts | sed -n "s/^$1=//p"; }
onb_no_helper() { [[ -z "$(helper_pid)" ]]; }
onb_visible() { [[ "$(onb window)" == visible ]]; }
guide_visible() { [[ "$(gf window)" == visible ]]; }
onb_is() { [[ "$(onb "$1")" == "$2" ]]; }
guide_is() { [[ "$(gf "$1")" == "$2" ]]; }
onb_has_button() { onb_facts | grep -q "^button $1|"; }
onb_button() { onb_facts | grep "^button $1|" | head -1; }
onb_press() { send_slow "$EDITOR_SOCK" "onboarding-press $1"; }
onb_tooltips() { onb_facts | grep '^button ' | awk -F'|' '$3 == "" { bad = 1 } END { exit bad }'; }
links_log() { cat "$RUN_ROOT/system-settings-links" 2>/dev/null; }
new_app_pid() { local now; now="$(pid_of "$APP_EXE")"; [[ -n "$now" && "$now" != "$1" ]] && answers "$APP_SOCK"; }

# Closes whatever the helper shows (it quits with its last window).
onb_close_all() {
  send "$EDITOR_SOCK" onboarding-close >/dev/null 2>&1
  send "$EDITOR_SOCK" guide-close >/dev/null 2>&1
  wait_until 10 onb_no_helper
}

# onb_open_at <step>: stores the step and presses a Shortcut, which opens Onboarding at it.
onb_open_at() {
  onb_close_all
  send "$APP_SOCK" "defaults-set onboardingStep $1" >/dev/null
  send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
  wait_until 15 onb_visible
}

restart_app() {
  send "$APP_SOCK" quit >/dev/null
  wait_until 30 gone "$APP_PID"
  (nohup "$APP_EXE" >>"$RUN_ROOT/app.log" 2>&1 &)
  if wait_until 15 answers "$APP_SOCK"; then pass "snapit starts again ($1)"; else abort "snapit did not start again ($1)"; fi
  APP_PID="$(pid_of "$APP_EXE")"
}

ONB_APP_FOOT_BEFORE="$(footprint_mb "$APP_PID")"

# 1. Test mode starts finished: nothing shows, and a Shortcut still captures (every other flow).
expect_equal "Onboarding starts finished in test mode: the launch check shows nothing" "none" "$(send "$APP_SOCK" onboarding-launch-check)"
onb_no_helper && pass "no helper process while Onboarding is finished" || fail "a helper runs while Onboarding is finished"

# 2. First launch: Onboarding opens at Welcome, in the helper, with a Dock icon.
send "$APP_SOCK" "defaults-set onboardingStep welcome" >/dev/null
restart_app "first launch"
if wait_until 20 onb_visible; then pass "Onboarding opens at the first launch"; else fail "Onboarding did not open at the first launch"; fi
expect_equal "Onboarding starts at Welcome" "welcome" "$(onb step)"
expect_equal "Welcome is step 1" "1" "$(onb step-number)"
expect_equal "the window is called Onboarding" "Onboarding" "$(onb title)"
expect_equal "the helper is a regular app (Dock icon) while Onboarding shows" "regular" "$(onb activation)"
expect_contains "Welcome points at the menu bar" "menu bar" "$(onb text)"
expect_equal "Welcome has no Back button" "" "$(onb_button back)"
expect_equal "Welcome's Continue button says where it goes" "button next|Continue|Go on to Screen Recording" "$(onb_button next)"
if onb_tooltips; then pass "every button of Welcome has a tooltip"; else fail "a button of Welcome has no tooltip"; fi
if lsappinfo info -only applicationType "$(lsappinfo find pid="$APP_PID")" 2>/dev/null | grep -q UIElement; then pass "the menu bar app shows no window and no Dock icon: Onboarding is the helper's"; else fail "the menu bar app has a Dock icon while Onboarding shows"; fi

# 3. Every step stores itself as it appears, and Back goes back.
onb_press next >/dev/null
expect_equal "Continue goes to Screen Recording" "screenRecording" "$(onb step)"
expect_equal "the step is stored at once" "screenRecording" "$(send "$APP_SOCK" "defaults-get onboardingStep")"
expect_equal "Screen Recording is step 2" "2" "$(onb step-number)"
expect_equal "Screen Recording's Back button names the step before" "button back|Back|Go back to Welcome" "$(onb_button back)"
onb_press back >/dev/null
expect_equal "Back goes back to Welcome" "welcome" "$(onb step)"
expect_equal "Back stores Welcome" "welcome" "$(send "$APP_SOCK" "defaults-get onboardingStep")"
onb_press next >/dev/null

# 4. Screen Recording granted (the fake macOS grants by default): the guide says so and plays nothing.
wait_until 10 onb_is guide-state granted
expect_equal "a granted Screen Recording says it is on" "Screen Recording is on" "$(onb guide-headline)"
expect_equal "a granted Screen Recording plays no animation" "idle" "$(onb guide-animation)"
expect_equal "snapit asked macOS for nothing when it was granted" "0" "$(sr_fact requests)"
expect_equal "the permission was looked at once, when the step appeared" "1" "$(onb guide-checks)"
expect_equal "no button but Back and Continue when it is granted" "" "$(onb_button open-system-settings)"

# 5. Resume at the next launch: close at Save location, relaunch, and Onboarding is back there.
onb_press next >/dev/null
expect_equal "Continue goes to Save location" "saveLocation" "$(onb step)"
expect_equal "Save location shows the Save location folder" "$ONB_SAVE_BEFORE" "$(onb save-location)"
expect_equal "Save location has a Choose… button with a tooltip" "button choose-save-location|Choose…|Choose the folder Save writes into" "$(onb_button choose-save-location)"
send "$EDITOR_SOCK" "onboarding-choose-save-location $ONB_ELSEWHERE" >/dev/null
expect_equal "choosing a folder shows it" "$ONB_ELSEWHERE" "$(onb save-location)"
expect_equal "choosing a folder is the Save location Settings and Save use" "$ONB_ELSEWHERE" "$(send "$APP_SOCK" test-seams | sed -n 's/^save=//p')"
expect_equal "choosing a folder is stored under the Settings key" "$ONB_ELSEWHERE" "$(send "$APP_SOCK" "defaults-get saveLocation")"
send "$APP_SOCK" "defaults-set saveLocation $ONB_SAVE_BEFORE" >/dev/null
onb_close_all
if onb_no_helper; then pass "closing Onboarding quits the helper, and the menu bar app stays"; else fail "the helper outlived Onboarding"; fi
kill -0 "$APP_PID" 2>/dev/null && pass "closing Onboarding leaves the menu bar app running" || fail "closing Onboarding stopped the menu bar app"
expect_equal "closing at Save location stores Save location" "saveLocation" "$(send "$APP_SOCK" "defaults-get onboardingStep")"
restart_app "resume at the next launch"
if wait_until 20 onb_visible; then pass "Onboarding resumes at the next launch"; else fail "Onboarding did not resume at the next launch"; fi
expect_equal "it resumes at Save location" "saveLocation" "$(onb step)"

# 6. Resume at a Shortcut press: nothing is captured meanwhile.
onb_close_all
LAST_CAPTURE_BEFORE="$(send "$APP_SOCK" last-capture)"
send_slow "$APP_SOCK" "press-shortcut capture-area" >/dev/null
if wait_until 15 onb_visible; then pass "a Shortcut press opens Onboarding while it is unfinished"; else fail "a Shortcut press did not open Onboarding"; fi
expect_equal "the Shortcut press resumes at Save location" "saveLocation" "$(onb step)"
expect_equal "an unfinished Onboarding takes the Shortcut press: no overlay" "none" "$(send "$APP_SOCK" overlay-facts)"
expect_equal "an unfinished Onboarding takes the Shortcut press: no Capture was taken" "$LAST_CAPTURE_BEFORE" "$(send "$APP_SOCK" last-capture)"
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
expect_equal "a second press brings the same window forward" "saveLocation" "$(onb step)"

# 7. Shortcuts: the defaults, a clash flagged, a recorded Shortcut applied by the menu bar app.
onb_press next >/dev/null
expect_equal "Continue goes to Shortcuts" "shortcuts" "$(onb step)"
shortcut_line() { onb_facts | grep "^shortcut $1|" | head -1; }
shortcut_loaded() { [[ "$(shortcut_line capture-area)" != "shortcut capture-area|unknown|"* ]]; }
wait_until 10 shortcut_loaded
expect_contains "Area is ⌃⌥⌘4 by default" "shortcut capture-area|21 control,option,command|⌃⌥⌘4|" "$(shortcut_line capture-area)"
expect_contains "Window is ⌃⌥⌘5 by default" "shortcut capture-window|23 control,option,command|⌃⌥⌘5|" "$(shortcut_line capture-window)"
expect_contains "Screen is ⌃⌥⌘3 by default" "shortcut capture-screen|20 control,option,command|⌃⌥⌘3|" "$(shortcut_line capture-screen)"
expect_contains "Pick Color is unassigned by default" "shortcut pick-color|none|" "$(shortcut_line pick-color)"
expect_equal "no default Shortcut is flagged while macOS uses none of them" "0" "$(onb_facts | grep '^shortcut ' | awk -F'|' '$4 != "" { n++ } END { print n + 0 }')"
send "$EDITOR_SOCK" "system-shortcut-fixture add 21 control,option,command" >/dev/null
onb_press back >/dev/null
onb_press next >/dev/null
wait_until 10 shortcut_loaded
expect_contains "a default Shortcut that macOS also uses is flagged" "shortcut capture-area|21 control,option,command|⌃⌥⌘4|macOS also uses this key combination." "$(shortcut_line capture-area)"
expect_equal "only the clashing default is flagged" "1" "$(onb_facts | grep '^shortcut ' | awk -F'|' '$4 != "" { n++ } END { print n + 0 }')"
send "$EDITOR_SOCK" "system-shortcut-fixture reset" >/dev/null
onb_press shortcut.capture-area >/dev/null
expect_equal "pressing a recorder starts recording" "recording" "$(onb_facts | grep '^shortcut capture-area|' | cut -d'|' -f2)"
expect_equal "the recorder refuses ⌘3 alone" "ok" "$(send "$EDITOR_SOCK" "onboarding-key 20 command")"
expect_equal "a refused key leaves the recorder waiting" "recording" "$(onb_facts | grep '^shortcut capture-area|' | cut -d'|' -f2)"
expect_equal "⌘⇧3 is recorded" "ok" "$(send "$EDITOR_SOCK" "onboarding-key 20 shift,command")"
expect_contains "the recorded Shortcut is flagged (macOS uses ⌘⇧3)" "shortcut capture-area|20 shift,command|⇧⌘3|macOS also uses this key combination." "$(shortcut_line capture-area)"
expect_equal "the menu bar app applied the recorded Shortcut" "20 shift,command" "$(send "$APP_SOCK" "shortcut-combo capture-area")"
onb_press shortcut-clear.capture-window >/dev/null
expect_equal "clearing a Shortcut unassigns it in the menu bar app" "none" "$(send "$APP_SOCK" "shortcut-combo capture-window")"
send "$APP_SOCK" "shortcut-set capture-area 21 control option command" >/dev/null
send "$APP_SOCK" "shortcut-set capture-window 23 control option command" >/dev/null
if onb_has_button open-screenshot-shortcuts && onb_tooltips; then pass "the Screenshots shortcuts button is there, with a tooltip"; else fail "the Screenshots shortcuts button or a tooltip is missing"; fi
: >"$RUN_ROOT/system-settings-links"
onb_press open-screenshot-shortcuts >/dev/null
expect_contains "the Screenshots shortcuts button opens the Keyboard page" "com.apple.Keyboard-Settings.extension" "$(links_log)"

# 8. Open at Login goes through the login item the menu bar app owns.
send "$APP_SOCK" "login-item-simulate notRegistered" >/dev/null
onb_press next >/dev/null
expect_equal "Continue goes to Open at Login" "openAtLogin" "$(onb step)"
wait_until 10 onb_is login off
expect_equal "Open at Login shows the login item's status" "off" "$(onb login)"
onb_press open-at-login >/dev/null
expect_equal "the toggle turns Open at Login on" "enabled" "$(send "$APP_SOCK" login-item-status)"
expect_equal "the step shows it on" "on" "$(onb login)"
onb_press open-at-login >/dev/null
expect_equal "the toggle turns it off again" "notRegistered" "$(send "$APP_SOCK" login-item-status)"
send "$APP_SOCK" "login-item-simulate enabled" >/dev/null
onb_press back >/dev/null
onb_press next >/dev/null
wait_until 10 onb_is login on
expect_equal "a login item that is on shows on when the step opens" "on" "$(onb login)"
send "$APP_SOCK" "login-item-simulate $ONB_LOGIN_BEFORE" >/dev/null

# 9. Done finishes Onboarding at once ("Try it: press ⌃⌥⌘4"), and the User Guide link is wired to a hook.
onb_press next >/dev/null
expect_equal "Continue goes to Done" "done" "$(onb step)"
expect_equal "reaching Done finishes Onboarding" "finished" "$(send "$APP_SOCK" "defaults-get onboardingStep")"
expect_equal "Done is step 6" "6" "$(onb step-number)"
onb_press back >/dev/null
expect_equal "going back from Done does not start Onboarding over" "finished" "$(send "$APP_SOCK" "defaults-get onboardingStep")"
onb_press next >/dev/null
wait_until 10 onb_is try-it "Try it: press ⌃⌥⌘4"
expect_equal "Done says what to try" "Try it: press ⌃⌥⌘4" "$(onb try-it)"
expect_equal "the User Guide link shows without any fixture: the helper sets its hook when it launches" "available" "$(onb user-guide)"
expect_equal "Done has a Done button and no Continue" "button done|Done|Close Onboarding" "$(onb_button done)"
send "$EDITOR_SOCK" "onboarding-user-guide-fixture off" >/dev/null
expect_equal "the User Guide link is absent while no hook is set" "unavailable" "$(onb user-guide)"
send "$EDITOR_SOCK" "onboarding-user-guide-fixture on" >/dev/null
expect_equal "the User Guide link shows once the hook is set" "button user-guide|Open the User Guide|Open the User Guide" "$(onb_button user-guide)"
rm -f "$RUN_ROOT/user-guide-opened"
onb_press user-guide >/dev/null
if [[ -f "$RUN_ROOT/user-guide-opened" ]]; then pass "the User Guide link calls the hook"; else fail "the User Guide link did not call the hook"; fi
send "$EDITOR_SOCK" "onboarding-user-guide-fixture off" >/dev/null
if onb_tooltips; then pass "every button of Done has a tooltip"; else fail "a button of Done has no tooltip"; fi
# A Shortcut pressed while the Done step is still open starts a Capture: Onboarding is finished.
send_slow "$APP_SOCK" "press-shortcut capture-area" >/dev/null
expect_equal "with Onboarding finished a Shortcut starts the Area Capture" "state" "$(send "$APP_SOCK" overlay-facts | sed -n 's/^\(state\)=.*/\1/p')"
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels it" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
onb_press done >/dev/null
if wait_until 10 onb_no_helper; then pass "Done closes Onboarding and the helper quits"; else fail "the helper outlived Done"; fi

# 10. Finished: it never shows again, at a launch or at a Shortcut press.
restart_app "Onboarding finished"
sleep 2
expect_equal "a finished Onboarding does not open at launch" "none" "$(send "$APP_SOCK" onboarding-launch-check)"
onb_no_helper && pass "no helper process at a launch after Onboarding finished" || fail "a helper runs after Onboarding finished"
send_slow "$APP_SOCK" "press-shortcut capture-area" >/dev/null
if [[ "$(send "$APP_SOCK" overlay-facts)" == *"state="* ]]; then pass "a Shortcut starts a Capture again"; else fail "a Shortcut after Onboarding finished did not start a Capture"; fi
if [[ "$(onb_facts)" != *"window=visible"* ]]; then pass "and Onboarding does not show"; else fail "Onboarding showed after it finished"; fi
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
wait_until 10 onb_no_helper

# 11. The Permission guide, never granted: macOS's prompt, then "Don't Allow" switches the drawing.
send "$APP_SOCK" "screen-recording-simulate notDetermined" >/dev/null
onb_open_at screenRecording
wait_until 10 onb_is guide-state denied
expect_equal "the guide asked macOS once" "1" "$(sr_fact requests)"
expect_equal "a never granted snapit resets nothing" "0" "$(sr_fact resets)"
expect_equal "the guide starts with macOS's prompt, then System Settings" "prompt" "$(onb guide-variant)"
expect_equal "a first-time guide is not the update's" "no" "$(onb guide-update)"
expect_equal "the guide asks to turn snapit on" "Turn on Screen Recording for snapit" "$(onb guide-headline)"
expect_equal "the Open System Settings button has its tooltip" "button open-system-settings|Open System Settings|Open System Settings at Privacy & Security › Screen Recording" "$(onb_button open-system-settings)"
expect_equal "Relaunch snapit waits for the System Settings version" "" "$(onb_button relaunch)"
expect_equal "the animation plays while the guide is visible" "playing" "$(onb guide-animation)"
expect_equal "it plays a few loops of a few seconds" "3 3" "$(onb guide-loops) $(onb guide-loop-seconds)"
: >"$RUN_ROOT/system-settings-links"
onb_press open-system-settings >/dev/null
expect_equal "Open System Settings opens the Screen Recording page" "$ONB_URL" "$(links_log | tail -1)"
# "Don't Allow": once macOS's message is over, the next time the window is active the guide switches.
CHECKS_BEFORE="$(onb guide-checks)"
send "$EDITOR_SOCK" onboarding-activate >/dev/null
expect_equal "the window becoming active looks at Screen Recording again" "$((CHECKS_BEFORE + 1))" "$(onb guide-checks)"
expect_equal "after Don't Allow the guide shows the System Settings version" "systemSettings" "$(onb guide-variant)"
expect_contains "the System Settings version says to turn snapit on in the list" "turn snapit on in the Screen Recording list" "$(onb guide-message)"
expect_equal "snapit did not ask macOS again" "1" "$(sr_fact requests)"
expect_equal "Relaunch snapit is there for the user who chose Later" "button relaunch|Relaunch snapit|Relaunch snapit, so it can use Screen Recording once you turned it on" "$(onb_button relaunch)"
if onb_tooltips; then pass "every button of the guide has a tooltip"; else fail "a button of the guide has no tooltip"; fi

# 12. The grant is looked at when the window becomes active, never on a timer.
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
CHECKS_BEFORE="$(onb guide-checks)"
sleep 5
expect_equal "five seconds on, with Screen Recording granted in the meantime, the guide has not looked" "$CHECKS_BEFORE" "$(onb guide-checks)"
expect_equal "so it still says denied" "denied" "$(onb guide-state)"
send "$EDITOR_SOCK" onboarding-activate >/dev/null
expect_equal "becoming active shows the grant" "granted" "$(onb guide-state)"
expect_equal "a granted guide says Screen Recording is on" "Screen Recording is on" "$(onb guide-headline)"
expect_equal "a granted guide stops its animation" "idle" "$(onb guide-animation)"
expect_equal "a granted guide has only Back and Continue" "" "$(onb_button open-system-settings)"

# 13. "Quit & Reopen" (and Later, then Relaunch snapit): the relaunched snapit resumes Onboarding at the same step.
send "$APP_SOCK" "screen-recording-simulate denied" >/dev/null
send "$EDITOR_SOCK" onboarding-activate >/dev/null
expect_equal "a guide that finds Screen Recording off again shows System Settings" "systemSettings" "$(onb guide-variant)"
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
OLD_APP_PID="$APP_PID"
OLD_HELPER="$(helper_pid)"
# The helper goes down with the menu bar app before it can reply, so the reply is not checked.
onb_press relaunch >/dev/null
if wait_until 30 new_app_pid "$OLD_APP_PID"; then pass "snapit relaunches as a new process"; else fail "snapit did not relaunch"; fi
APP_PID="$(pid_of "$APP_EXE")"
if wait_until 10 gone "$OLD_HELPER"; then pass "the old helper is gone with the old snapit"; else fail "the old helper outlived the relaunch"; fi
if wait_until 30 onb_visible; then pass "Onboarding opens again after the relaunch"; else fail "Onboarding did not open after the relaunch"; fi
expect_equal "it resumes at the Screen Recording step" "screenRecording" "$(onb step)"
wait_until 10 onb_is guide-state granted
expect_equal "and the relaunched snapit has Screen Recording" "granted" "$(onb guide-state)"

# 14. The update path: granted before, gone now. snapit clears its own entry (a fixture, never the
#     real tccutil) and asks afresh; only the guide shows, worded for the update; it resets once.
onb_close_all
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" "screen-recording-simulate grantedStale" >/dev/null
expect_equal "the fake macOS says snapit was granted before and is not now" "grantedStale" "$(sr_fact state)"
RESETS_BEFORE="$(sr_fact resets)"
REQUESTS_BEFORE="$(sr_fact requests)"
expect_equal "an update shows only the guide" "permission-guide" "$(send_slow "$APP_SOCK" onboarding-launch-check)"
if wait_until 15 guide_visible; then pass "the Permission guide opens on its own after an update"; else fail "the guide did not open after an update"; fi
expect_equal "Onboarding itself is not shown after an update" "window=none" "$(onb_facts)"
wait_until 15 guide_is guide-state denied
expect_equal "the guide opens for the update" "yes" "$(gf guide-update)"
expect_equal "snapit cleared its own entry once" "$((RESETS_BEFORE + 1))" "$(sr_fact resets)"
expect_equal "and asked afresh once" "$((REQUESTS_BEFORE + 1))" "$(sr_fact requests)"
expect_equal "the update guide says what is needed" "snapit needs Screen Recording turned back on" "$(gf guide-headline)"
expect_contains "the update guide explains the update" "Each update needs Screen Recording again" "$(gf guide-message)"
if [[ "$(gf guide-message)" == *toggle* || "$(gf guide-message)" == *"switch on"* || "$(gf guide-message)" == *"already"* ]]; then fail "the update guide tells people to work the old switch: $(gf guide-message)"; else pass "the update guide never tells people to toggle the existing switch"; fi
expect_equal "the update guide starts with macOS's fresh prompt" "prompt" "$(gf guide-variant)"
expect_equal "the update guide plays its animation" "playing" "$(gf guide-animation)"
expect_equal "the guide window is a regular helper window with a title" "Screen Recording" "$(gf title)"
expect_equal "snapit is no longer granted before: the next launch resets nothing" "none" "$(send_slow "$APP_SOCK" onboarding-launch-check)"
expect_equal "so it reset only once" "$((RESETS_BEFORE + 1))" "$(sr_fact resets)"
if gfacts | grep '^button ' | awk -F'|' '$3 == "" { bad = 1 } END { exit bad }'; then pass "every button of the update guide has a tooltip"; else fail "a button of the update guide has no tooltip"; fi
send "$EDITOR_SOCK" guide-activate >/dev/null
expect_equal "after Don't Allow the update guide shows System Settings" "systemSettings" "$(gf guide-variant)"
expect_contains "the update guide offers Relaunch snapit" "button relaunch|Relaunch snapit|" "$(gfacts)"
: >"$RUN_ROOT/system-settings-links"
send "$EDITOR_SOCK" "guide-press open-system-settings" >/dev/null
expect_equal "the update guide's button opens the Screen Recording page" "$ONB_URL" "$(links_log | tail -1)"

# The relaunched copy (Relaunch snapit, or Quit & Reopen) reads denied, not stale: it resets nothing.
send "$EDITOR_SOCK" guide-close >/dev/null 2>&1
wait_until 10 onb_no_helper
restart_app "after the update guide"
expect_equal "the relaunched copy reads denied, not stale" "denied" "$(sr_fact state)"
expect_equal "the relaunched copy shows no guide of its own" "none" "$(send_slow "$APP_SOCK" onboarding-launch-check)"
expect_equal "and resets nothing again" "$((RESETS_BEFORE + 1))" "$(sr_fact resets)"

# 15. The reset can fail (tccutil missing, or an error): reported, tried again at the next launch. snapit asks
#     macOS anyway: that does nothing while the old entry exists and prompts once the user removed it, so
#     the relaunch the guide asks for ends in a grant.
send "$APP_SOCK" "screen-recording-simulate grantedStale" >/dev/null
send "$APP_SOCK" "tcc-reset-fail on" >/dev/null
RESETS_BEFORE="$(sr_fact resets)"
REQUESTS_BEFORE="$(sr_fact requests)"
send_slow "$APP_SOCK" onboarding-launch-check >/dev/null
wait_until 15 guide_visible
wait_until 15 guide_is guide-state grantedStale
expect_equal "a failed reset leaves Screen Recording stale" "grantedStale" "$(sr_fact state)"
expect_contains "the guide reports why the reset failed" "fixture reset fails" "$(gf guide-reset-failure)"
expect_equal "a failed reset resets nothing" "$RESETS_BEFORE" "$(sr_fact resets)"
expect_equal "and still asks macOS, so a removed entry prompts" "$((REQUESTS_BEFORE + 1))" "$(sr_fact requests)"
expect_contains "the guide tells the user to remove the old entry and relaunch" "press − to remove it, then choose Relaunch snapit and allow Screen Recording when macOS asks" "$(gf guide-message)"
expect_contains "the guide offers Relaunch snapit" "button relaunch|Relaunch snapit|" "$(gfacts)"
# The relaunched copy is still stale, tries the reset again and, with the entry gone, it works.
send "$EDITOR_SOCK" guide-close >/dev/null 2>&1
wait_until 10 onb_no_helper
restart_app "after a failed reset"
wait_until 15 guide_visible
wait_until 15 guide_is guide-state grantedStale
expect_equal "a copy that relaunches after a failed reset is stale again" "grantedStale" "$(sr_fact state)"
send "$APP_SOCK" "tcc-reset-fail off" >/dev/null
send "$EDITOR_SOCK" guide-close >/dev/null 2>&1
wait_until 10 onb_no_helper
RESETS_BEFORE="$(sr_fact resets)"
restart_app "after the entry was removed"
wait_until 15 guide_visible
wait_until 15 guide_is guide-state denied
expect_equal "once the reset works the guide has cleared the entry" "$((RESETS_BEFORE + 1))" "$(sr_fact resets)"
expect_equal "and the guide is the update's" "yes" "$(gf guide-update)"
send "$EDITOR_SOCK" guide-close >/dev/null 2>&1
wait_until 10 onb_no_helper
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
restart_app "with Screen Recording granted at launch"
expect_equal "the permission is back to the fake macOS's default" "granted" "$(sr_fact state)"

# 16. The animation plays only while visible, stops after a few loops and costs nothing at rest.
send "$APP_SOCK" "screen-recording-simulate notDetermined" >/dev/null
onb_open_at screenRecording
wait_until 10 onb_is guide-animation playing
expect_equal "the animation plays while Onboarding is visible" "playing" "$(onb guide-animation)"
PLAYS_BEFORE="$(onb guide-plays)"
send "$EDITOR_SOCK" onboarding-hide >/dev/null
if wait_until 5 onb_is guide-animation idle; then pass "hiding the window stops the animation"; else fail "the animation kept playing in a hidden window"; fi
HELPER_PID="$(helper_pid)"
sleep 2
assert_idle_cpu "the helper with Onboarding hidden" "$HELPER_PID" 5
send "$EDITOR_SOCK" onboarding-unhide >/dev/null
if wait_until 5 onb_is guide-animation playing; then pass "showing the window plays it again"; else fail "the animation did not play when the window came back"; fi
expect_equal "it started again, once" "$((PLAYS_BEFORE + 1))" "$(onb guide-plays)"
if wait_until 20 onb_is guide-animation stopped; then pass "the animation stops after its loops"; else fail "the animation did not stop"; fi
if onb_has_button replay; then pass "a stopped animation can be replayed"; else fail "no Replay button after the animation stopped"; fi
assert_idle_cpu "the helper after the animation stopped" "$HELPER_PID" "$IDLE_SECONDS"
onb_press replay >/dev/null
expect_equal "Replay plays it again" "playing" "$(onb guide-animation)"
send "$EDITOR_SOCK" "onboarding-snapshot $RUN_ROOT/onboarding-guide.png" >/dev/null
[[ -s "$RUN_ROOT/onboarding-guide.png" ]] && pass "the guide renders" || fail "the guide did not render"
PLAYS_BEFORE="$(onb guide-plays)"
onb_press next >/dev/null
onb_press back >/dev/null
expect_equal "leaving the step stopped the animation, and coming back plays it again" "$((PLAYS_BEFORE + 1))" "$(onb guide-plays)"

# 16b. Turning Screen Recording off on purpose is not an update: the same build that was granted is
#      denied, with the System Settings wording and no reset. Another build is stale.
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
expect_equal "the fake macOS grants this build" "granted" "$(sr_fact state)"
send "$APP_SOCK" "screen-recording-simulate revoked" >/dev/null
expect_equal "a grant switched off for the same build reads denied" "denied" "$(sr_fact state)"
send "$APP_SOCK" "screen-recording-build build-2" >/dev/null
expect_equal "a grant lost to another build (an update) reads stale" "grantedStale" "$(sr_fact state)"
send "$APP_SOCK" "screen-recording-build build-1" >/dev/null
RESETS_BEFORE="$(sr_fact resets)"
REQUESTS_BEFORE="$(sr_fact requests)"
send "$APP_SOCK" "screen-recording-simulate turnedOff" >/dev/null
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
expect_equal "a copy launched with its switch turned off shows no guide of its own" "none" "$(send_slow "$APP_SOCK" onboarding-launch-check)"
onb_open_at screenRecording
wait_until 10 onb_is guide-state denied
expect_equal "the guide knows the switch was turned off" "yes" "$(onb guide-turned-off)"
expect_equal "it shows the System Settings version" "systemSettings" "$(onb guide-variant)"
expect_equal "and says what to do" "Screen Recording is off for snapit. Turn snapit on in System Settings, then choose Quit & Reopen." "$(onb guide-message)"
expect_equal "it is not the update's" "no" "$(onb guide-update)"
expect_equal "snapit resets nothing for a switch the user turned off" "$RESETS_BEFORE" "$(sr_fact resets)"
expect_equal "and asks macOS for nothing" "$REQUESTS_BEFORE" "$(sr_fact requests)"
onb_close_all

# 16c. Granted now, but not when snapit started: macOS lets a process capture only from its next launch
#      on, so the guide keeps Relaunch snapit and a Shortcut does not pretend to work.
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" "screen-recording-simulate denied" >/dev/null
restart_app "launched without Screen Recording"
onb_open_at screenRecording
wait_until 10 onb_is guide-state denied
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
expect_equal "granted after launch is a state of its own" "grantedNeedsRelaunch" "$(sr_fact state)"
expect_contains "the permission edge reports it as not usable yet" "permission=denied" "$(send "$APP_SOCK" test-seams)"
send "$EDITOR_SOCK" onboarding-activate >/dev/null
expect_equal "the guide says to relaunch" "grantedNeedsRelaunch" "$(onb guide-state)"
expect_equal "with a headline that says so" "Relaunch snapit to start using Screen Recording" "$(onb guide-headline)"
expect_equal "Relaunch snapit stays" "button relaunch|Relaunch snapit|Relaunch snapit, so it can use Screen Recording once you turned it on" "$(onb_button relaunch)"
expect_equal "Open System Settings is not offered any more" "" "$(onb_button open-system-settings)"
expect_equal "nothing animates" "idle" "$(onb guide-animation)"
CAPTURE_BEFORE="$(send "$APP_SOCK" last-capture)"
onb_close_all
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
expect_equal "a Capture Shortcut does not capture while snapit has to relaunch" "$CAPTURE_BEFORE" "$(send "$APP_SOCK" last-capture)"
onb_open_at screenRecording
wait_until 10 onb_is guide-state grantedNeedsRelaunch
OLD_APP_PID="$APP_PID"
onb_press relaunch >/dev/null
if wait_until 30 new_app_pid "$OLD_APP_PID"; then pass "Relaunch snapit relaunches a copy that was granted after it started"; else fail "snapit did not relaunch"; fi
APP_PID="$(pid_of "$APP_EXE")"
expect_equal "the relaunched copy can use Screen Recording" "granted" "$(sr_fact state)"
onb_close_all

# 16d. A helper whose copy was killed stays with the user's Editors; the next copy uses it, does not
#      retire it (a raw quit would close the Editors), and quits it when it quits.
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send_slow "$APP_SOCK" "menu-click capture.screen" >/dev/null
editors_open() { [[ -n "$(send "$EDITOR_SOCK" editors)" ]]; }
if wait_until 15 editors_open; then pass "a Capture is open in an Editor"; else fail "no Editor opened"; fi
KEPT_EDITORS="$(send "$EDITOR_SOCK" editors)"
KEPT_HELPER="$(helper_pid)"
send "$APP_SOCK" "defaults-set onboardingStep welcome" >/dev/null
kill -9 "$APP_PID" 2>/dev/null
wait_until 10 gone "$APP_PID"
if kill -0 "$KEPT_HELPER" 2>/dev/null; then pass "the helper stays when its copy is killed"; else fail "the helper went with the killed copy"; fi
(nohup "$APP_EXE" >>"$RUN_ROOT/app.log" 2>&1 &)
if wait_until 15 answers "$APP_SOCK"; then pass "snapit starts again after being killed"; else abort "snapit did not start after being killed"; fi
APP_PID="$(pid_of "$APP_EXE")"
if wait_until 20 onb_visible; then pass "the new copy shows Onboarding in the helper that was left"; else fail "Onboarding did not show"; fi
expect_equal "it is the same helper" "$KEPT_HELPER" "$(helper_pid)"
expect_equal "the user's Editor is still open" "$KEPT_EDITORS" "$(send "$EDITOR_SOCK" editors)"
send "$EDITOR_SOCK" onboarding-close >/dev/null 2>&1
sleep 1
expect_equal "closing Onboarding leaves the helper while an Editor is open" "$KEPT_EDITORS" "$(send "$EDITOR_SOCK" editors)"
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" quit >/dev/null
if wait_until 30 gone "$APP_PID"; then pass "the new copy quits"; else fail "the new copy did not quit"; fi
if wait_until 10 gone "$KEPT_HELPER"; then pass "the helper it adopted quits with it"; else fail "the adopted helper outlived the copy that used it"; kill "$KEPT_HELPER" 2>/dev/null; fi
(nohup "$APP_EXE" >>"$RUN_ROOT/app.log" 2>&1 &)
if wait_until 15 answers "$APP_SOCK"; then pass "snapit starts again"; else abort "snapit did not start again"; fi
APP_PID="$(pid_of "$APP_EXE")"

# 17. Memory and the process list return to rest after Onboarding closes.
onb_close_all
onb_no_helper && pass "no helper process after Onboarding closes" || fail "a helper is still running after Onboarding closed"
sleep 2
ONB_APP_FOOT_AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$ONB_APP_FOOT_BEFORE" -v b="$ONB_APP_FOOT_AFTER" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(b > 0 && b - a <= max) }'; then
  pass "the menu bar app is back at its baseline after Onboarding (${ONB_APP_FOOT_BEFORE} MB before, ${ONB_APP_FOOT_AFTER} MB after)"
else
  fail "the menu bar app grew from ${ONB_APP_FOOT_BEFORE} MB to ${ONB_APP_FOOT_AFTER} MB over Onboarding"
fi
assert_idle_cpu "the menu bar app after Onboarding" "$APP_PID" "$IDLE_SECONDS"

# Put the fake macOS and Onboarding back for the flows after this one.
# The relaunch through Relaunch snapit went through LaunchServices, which leaves the process without the
# run's log file: start it again the way the run does, so later flows read its log.
send "$APP_SOCK" "screen-recording-simulate granted" >/dev/null
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" "defaults-set saveLocation $ONB_SAVE_BEFORE" >/dev/null
rm -rf "$ONB_ELSEWHERE" "$RUN_ROOT/onboarding-guide.png"
restart_app "its log is the run's again"
