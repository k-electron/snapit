# Flow: the user stays in control while an Update runs. While the release downloads the Update
# window shows a progress bar and Cancel; Cancel, or closing the window, ends the Update with the
# installed copy unchanged and nothing left behind. An Editor that is not the Last Capture and holds
# unexported edits brings Quit's question first (Cancel stops before any request, Discard goes on);
# with only the Last Capture's Editor nothing is asked. The question comes again just before the swap
# for an Editor the first answer did not cover (a Capture taken during the download makes the Last
# Capture's Editor one at risk); Cancel then ends the Update with nothing changed. When the swap begins, a Timed Capture that
# is counting down is cancelled and takes no Capture, and Cancel and the window's close button are
# disabled until the relaunch.
#
# The HTTP edge is the fixture of flow 56 and 59: `update-script hold-download <percent>` parks the
# download of the disk image once that share of it has arrived (the window then shows the progress,
# and the same command with another share moves it); `update-script hold-swap on` parks the Update
# just after the swap has begun, so the window and the Timed Capture can be looked at. Everything
# else is real inside the run's root, as in flow 59: a disk image built with `hdiutil create` from a
# copy of the built snapit at the announced version, attached for real, and the pretended install
# location in the root's Applications folder. The run never goes online.
#
# It uses the helpers of flows 40, 42 and 43 (Area, Action bar, Timed Capture), so it runs after
# them in the whole run. Sourced by scripts/check-run.sh. It ends with the one real relaunch, as flow
# 59 does, and with a menu bar app running from $APP_EXE again.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

UC_ROOT="$(real_root)"
UC_APPS="$UC_ROOT/Applications"
UC_DEST="$UC_APPS/snapit.app"
UC_ASSETS="$RUN_ROOT/update-assets"
UC_BUILT="$RUN_ROOT/update-built"
UC_STAGING="$RUN_ROOT/update-staging"
UC_CAPS="$RUN_ROOT/captures"
UC_BUILD_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
UC_VERSION="$((${UC_BUILD_VERSION%%.*} + 1)).0.0"
UC_TAG="v$UC_VERSION"
UC_PAGE="https://github.com/k-electron/snapit/releases/tag/$UC_TAG"

uc_enc() { printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge'; }
uc_val() { send "$EDITOR_SOCK" update-facts | sed -n "s/^$1=//p" | head -1; }
uc_val_is() { [[ "$(uc_val "$1")" == "$2" ]]; }
uc_buttons() { send "$EDITOR_SOCK" update-facts | sed -n 's/^button //p' | awk -F'|' '{ print $1 }' | tr '\n' ' '; }
uc_settled() { local state; state="$(uc_val state)"; [[ -n "$state" && "$state" != checking ]]; }
uc_check() {
  send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
  wait_until 20 uc_settled
}
uc_requests() { send "$APP_SOCK" update-requests; }
uc_status() { send "$APP_SOCK" update-status; }
uc_status_is() { [[ "$(uc_status)" == "$1" ]]; }
uc_version_of() { plutil -extract CFBundleShortVersionString raw "$1/Contents/Info.plist" 2>/dev/null; }
uc_exe_sum() { shasum -a 256 "$UC_DEST/Contents/MacOS/snapit" | awk '{ print $1 }'; }
# Lines of `hdiutil info` that name this run: an image of the Update still attached.
uc_attached() { hdiutil info 2>/dev/null | grep -cF "$(basename "$RUN_ROOT")"; }
# Disk images anywhere in the root but the fixture's own files: a downloaded file left behind.
uc_stray_images() { find "$RUN_ROOT" -name '*.dmg' -not -path "$UC_ASSETS/*" 2>/dev/null | wc -l | tr -d ' '; }
uc_staging_gone() { [[ ! -e "$UC_STAGING" ]]; }
uc_cleaned_after_update() { [[ ! -e "$UC_STAGING" && "$(ls -A "$UC_APPS" 2>/dev/null)" == "snapit.app" ]]; }
uc_no_helper() { [[ "$(helper_count)" == "0" ]]; }
uc_prompt() { send "$EDITOR_SOCK" editor-prompt; }
uc_prompt_shown() { [[ "$(uc_prompt)" == shown* ]]; }
uc_prompt_none() { [[ "$(uc_prompt)" == none ]]; }
uc_open() { open_editors | grep -qx "$1"; }
uc_closed() { ! uc_open "$1"; }
# uc_edit <N>: one Rectangle in Editor N, an edit that was never Exported.
uc_edit() { EDITOR_N="$1"; keystroke r >/dev/null; drag 40 30 120 90 >/dev/null; }
uc_timed() { send "$APP_SOCK" timed-facts | sed -n "s/^$1=//p"; }
uc_timed_is() { [[ "$(uc_timed "$1")" == "$2" ]]; }
# What the installed copy and the root look like after an Update that ended with nothing changed.
uc_expect_nothing_changed() { # <what>
  expect_equal "$1: the installed copy is at its version" "$UC_BUILD_VERSION" "$(uc_version_of "$UC_DEST")"
  expect_equal "$1: and is the same executable" "$UC_EXE_BEFORE" "$(uc_exe_sum)"
  expect_equal "$1: Applications holds only that copy" "snapit.app" "$(ls -A "$UC_APPS")"
  if uc_staging_gone; then pass "$1: no staging folder is left"; else fail "$1: a staging folder is left: $(ls -A "$UC_STAGING" | tr '\n' ' ')"; fi
  expect_equal "$1: no downloaded disk image is left" "0" "$(uc_stray_images)"
  expect_equal "$1: no disk image of the Update is attached" "0" "$(uc_attached)"
  expect_equal "$1: the menu bar app has no Update running" "idle" "$(uc_status)"
}

REQUESTS_AT_START="$(uc_requests)"
TIMER_BEFORE="$(send "$APP_SOCK" "defaults-get timedCaptureSeconds")"

# 1. The fixtures, as in flow 59: a disk image holding a copy of this build at the announced
#    version, signed ad hoc (the helper first, then the app), with its hash in the release's form.
mkdir -p "$UC_APPS" "$UC_BUILT" "$UC_ASSETS"
build_update_image "$UC_BUILT" "snapit-$UC_VERSION.dmg" "$UC_VERSION"
pass "the disk image and its hash are built"
cp "$UC_BUILT/snapit-$UC_VERSION.dmg" "$UC_BUILT/snapit-$UC_VERSION.dmg.sha256" "$UC_ASSETS/"
rm -rf "$UC_BUILT"

# The fixtures as the flows before left them, or not: no pretended place, no failing download, nothing held.
send "$APP_SOCK" install-reset >/dev/null
send "$APP_SOCK" "update-script download ok" >/dev/null
send "$APP_SOCK" "update-script hold off" >/dev/null
send "$APP_SOCK" "update-script hold-download off" >/dev/null
send "$APP_SOCK" "update-script hold-swap off" >/dev/null

# The running snapit pretends to be the copy in Applications: the Update swaps that copy.
ditto "$APP" "$UC_DEST"
send "$APP_SOCK" "install-pretend-bundle $UC_DEST" >/dev/null
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" "fixture-extra-display none" >/dev/null
send "$APP_SOCK" "fixture-delay 0" >/dev/null
send "$APP_SOCK" "fixture-fail off" >/dev/null
send "$APP_SOCK" "fixture-display 1 600 400" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
UC_EXE_BEFORE="$(uc_exe_sum)"
expect_equal "the installed copy is the build's version" "$UC_BUILD_VERSION" "$(uc_version_of "$UC_DEST")"
expect_equal "nothing was requested while the run set this up" "$REQUESTS_AT_START" "$(uc_requests)"
expect_equal "the menu bar app has no Update running" "idle" "$(uc_status)"
expect_equal "Cancel with no Update running is refused" "error no Update is running" "$(send "$APP_SOCK" cancel-update)"

send "$APP_SOCK" "update-script release $(uc_enc "$UC_TAG") $(uc_enc "$UC_PAGE") $(uc_enc "The newer snapit.")" >/dev/null
uc_check
expect_equal "the window announces the newer release" "newer" "$(uc_val state)"
expect_equal "with nothing to cancel yet" "error nothing to cancel" "$(send "$EDITOR_SOCK" "update-press cancel")"
expect_equal "and no Cancel button" "close release-page update " "$(uc_buttons)"
expect_equal "and no progress" "" "$(uc_val progress)"
REQ="$(uc_requests)"
sleep 2
UC_OLD_BASELINE_MB="$(footprint_mb "$APP_PID")"

# 2. While the release downloads: the window says so with its progress, and offers Cancel; the
#    title bar's close button works. The progress follows the share of the disk image that has arrived.
send "$APP_SOCK" "update-script hold-download 40" >/dev/null
expect_equal "Update and Relaunch answers at once" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
if wait_until 30 uc_val_is progress-percent 40; then pass "the window shows the download 40 per cent done"; else fail "no progress in the window (state '$(uc_val state)', progress '$(uc_val progress)')"; fi
expect_equal "the window reports downloading" "downloading" "$(uc_val state)"
expect_equal "and which version" "Downloading snapit $UC_VERSION…" "$(uc_val headline)"
expect_equal "Cancel is the button" "cancel " "$(uc_buttons)"
expect_equal "Cancel is enabled" "enabled" "$(uc_val cancel)"
expect_equal "and so is the close button" "enabled" "$(uc_val close-button)"
UC_PROGRESS="$(uc_val progress)"
if [[ "$UC_PROGRESS" =~ ^([0-9]+)/([0-9]+)$ ]] && ((BASH_REMATCH[2] > 0)) && ((BASH_REMATCH[1] > 0 && BASH_REMATCH[1] < BASH_REMATCH[2])); then
  pass "the progress is bytes received of the disk image's size ($UC_PROGRESS)"
else
  fail "the progress is not part of a file ($UC_PROGRESS)"
fi
expect_contains "the window says how much has arrived" " of " "$(uc_val detail)"
send "$APP_SOCK" "update-script hold-download 75" >/dev/null
if wait_until 10 uc_val_is progress-percent 75; then pass "the progress moves with the download (75 per cent)"; else fail "the progress did not move (still '$(uc_val progress-percent)')"; fi
expect_equal "the Update asked for the hash and the disk image, once each" "$((REQ + 2))" "$(uc_requests)"
expect_equal "the installed copy is untouched while it downloads" "$UC_BUILD_VERSION" "$(uc_version_of "$UC_DEST")"
expect_equal "a second press of Update and Relaunch does nothing" "error nothing to update" "$(send "$EDITOR_SOCK" "update-press update")"
expect_equal "an Update is running in the menu bar app" "downloading" "$(uc_status | awk '{ print $1 }')"
expect_no_internet "the menu bar app while a (fixture) download is parked" "$APP_PID"
expect_no_internet "the Editor helper while it shows the download" "$(helper_pid)"

# 3. Cancel: the Update ends, the window offers the release again, and nothing is left.
expect_equal "Cancel answers" "ok" "$(send_slow "$EDITOR_SOCK" "update-press cancel")"
if wait_until 20 uc_val_is state newer; then pass "Cancel ends the Update: the window offers the release again"; else fail "the window is still '$(uc_val state)' after Cancel"; fi
expect_equal "with Close, Release Page and Update and Relaunch" "close release-page update " "$(uc_buttons)"
uc_expect_nothing_changed "after Cancel"
expect_equal "Cancel sent no further request" "$((REQ + 2))" "$(uc_requests)"
if kill -0 "$APP_PID" 2>/dev/null && answers "$APP_SOCK"; then pass "snapit keeps running after Cancel"; else fail "snapit stopped after Cancel"; fi

# 4. Closing the window during the download is a Cancel too: the helper goes only once the Update
#    has stopped, so the menu bar app is not left downloading with no window.
REQ="$(uc_requests)"
expect_equal "Update and Relaunch answers again after a Cancel" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
if wait_until 30 uc_val_is progress-percent 75; then pass "the Update downloads again, parked at 75 per cent"; else fail "no second download (state '$(uc_val state)')"; fi
expect_equal "the close button is offered" "enabled" "$(uc_val close-button)"
UC_HELPER="$(helper_pid)"
expect_equal "the close button answers" "ok" "$(send_slow "$EDITOR_SOCK" "update-press close")"
if wait_until 30 gone "$UC_HELPER"; then pass "closing the window ends the Update and the helper, with no Editor open, quits"; else fail "the helper is still running after the window was closed"; fi
uc_expect_nothing_changed "after closing the window"
expect_equal "closing sent no further request" "$((REQ + 2))" "$(uc_requests)"
if kill -0 "$APP_PID" 2>/dev/null && answers "$APP_SOCK"; then pass "snapit keeps running after the window was closed"; else fail "snapit stopped after the window was closed"; fi
send "$APP_SOCK" "update-script hold-download off" >/dev/null
expect_memory_returns "the menu bar app is back at its baseline after two cancelled downloads" "$APP_PID" "$UC_OLD_BASELINE_MB"

# 5. Editors at risk. A (older, edited, never Exported), then B (the Last Capture, edited): the
#    question names A. Cancel ends the Update before a single request.
if ! capture_into_editor "menu-click capture.screen"; then abort "no Capture for the Update"; fi
UC_A="$EDITOR_N"
uc_edit "$UC_A"
if ! capture_into_editor "menu-click capture.screen"; then abort "no second Capture for the Update"; fi
UC_B="$EDITOR_N"
uc_edit "$UC_B"
uc_check
expect_equal "the window announces the release with two Editors open" "newer" "$(uc_val state)"
REQ="$(uc_requests)"
send "$APP_SOCK" "update-script hold-download 30" >/dev/null
expect_equal "Update and Relaunch answers" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
if wait_until 10 uc_prompt_shown; then pass "Quit's question is asked"; else fail "no question was asked ($(uc_prompt))"; fi
expect_contains "it is about the Editor that is not the Last Capture" "shown quit editor=$UC_A" "$(uc_prompt)"
expect_contains "it is Quit's own question" "Cancel,Discard and Quit" "$(uc_prompt)"
sleep 1
expect_equal "nothing was requested while the question is up" "$REQ" "$(uc_requests)"
expect_equal "the window still offers the release" "newer" "$(uc_val state)"
send "$EDITOR_SOCK" "editor-prompt-answer cancel" >/dev/null
wait_until 5 uc_prompt_none
sleep 1
expect_equal "Cancel ends the Update: no request at all, not even the hash" "$REQ" "$(uc_requests)"
expect_equal "the window offers the release again" "newer" "$(uc_val state)"
expect_equal "with Update and Relaunch" "close release-page update " "$(uc_buttons)"
uc_expect_nothing_changed "after answering Cancel"
if uc_open "$UC_A" && uc_open "$UC_B"; then pass "both Editors are still open"; else fail "an Editor closed: $(open_editors | tr '\n' ' ')"; fi

# 6. With only the Last Capture's Editor open, nothing is asked, whatever it holds: A goes (Delete
#    Capture asks nothing), B stays with its edit, and the Update starts at once.
send_slow "$EDITOR_SOCK" "editor-press $UC_A delete-capture" >/dev/null
wait_until 5 uc_closed "$UC_A"
EDITOR_N="$UC_B"
expect_equal "only the Last Capture's Editor is open" "$UC_B" "$(open_editors | tr '\n' ' ' | sed 's/ $//')"
expect_equal "Update and Relaunch answers" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
if wait_until 30 uc_val_is progress-percent 30; then pass "the Update starts at once"; else fail "the Update did not start (state '$(uc_val state)', prompt '$(uc_prompt)')"; fi
expect_equal "no question was asked" "none" "$(uc_prompt)"
expect_equal "the Update asked for the hash and the disk image" "$((REQ + 2))" "$(uc_requests)"
expect_equal "Cancel ends it" "ok" "$(send_slow "$EDITOR_SOCK" "update-press cancel")"
if wait_until 20 uc_val_is state newer; then pass "the window offers the release again"; else fail "the window is still '$(uc_val state)'"; fi
uc_expect_nothing_changed "after Cancel with only the Last Capture open"
if uc_open "$UC_B"; then pass "the Last Capture's Editor is still open"; else fail "the Last Capture's Editor closed"; fi

# 6b. A Capture taken after the click. Only the Last Capture's Editor (B, edited) is open, so nothing
#    is asked at the click. While the download is parked, a newer Capture (D) makes B an Editor that
#    is not the Last Capture, with an edit never Exported: the release is downloaded and checked, then
#    Quit's question comes before the swap and names B. Cancel ends the Update with nothing changed.
REQ="$(uc_requests)"
send "$APP_SOCK" "update-script hold-download 30" >/dev/null
expect_equal "Update and Relaunch answers" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
if wait_until 30 uc_val_is progress-percent 30; then pass "the Update starts at once, nothing at risk"; else fail "the Update did not start (state '$(uc_val state)', prompt '$(uc_prompt)')"; fi
if ! capture_into_editor "menu-click capture.screen"; then abort "no Capture during the Update"; fi
UC_D="$EDITOR_N"
expect_equal "no question yet: the Update is still downloading" "none" "$(uc_prompt)"
send "$APP_SOCK" "update-script hold-download off" >/dev/null
if wait_until 90 uc_prompt_shown; then pass "Quit's question is asked before the swap"; else fail "no question before the swap (state '$(uc_val state)', status '$(uc_status)')"; fi
expect_contains "it names the Editor that stopped being the Last Capture" "shown quit editor=$UC_B" "$(uc_prompt)"
expect_equal "the Update has not swapped: Cancel is still offered" "enabled" "$(uc_val cancel)"
expect_equal "the installed copy is untouched" "$UC_BUILD_VERSION" "$(uc_version_of "$UC_DEST")"
send "$EDITOR_SOCK" "editor-prompt-answer cancel" >/dev/null
if wait_until 20 uc_val_is state newer; then pass "Cancel ends the Update: the window offers the release again"; else fail "the window is still '$(uc_val state)' after Cancel"; fi
uc_expect_nothing_changed "after answering Cancel before the swap"
if uc_open "$UC_B" && uc_open "$UC_D"; then pass "both Editors are still open"; else fail "an Editor closed: $(open_editors | tr '\n' ' ')"; fi
send_slow "$EDITOR_SOCK" "editor-press $UC_D delete-capture" >/dev/null
wait_until 5 uc_closed "$UC_D"
EDITOR_N="$UC_B"

# 7. The one real Update. B is no longer the Last Capture once C is taken, so the question names B,
#    and Discard goes on; B is unchanged by the time the release is ready, so it is not asked again
#    before the swap. The download parks at 30 per cent; a Timed Capture starts counting down
#    (10 s, which the check of the copy is well inside); the download is released and the Update parks
#    again just after the swap has begun.
if ! capture_into_editor "menu-click capture.screen"; then abort "no third Capture for the Update"; fi
UC_C="$EDITOR_N"
REQ="$(uc_requests)"
expect_equal "the window still offers the release" "newer" "$(uc_val state)"
expect_equal "Update and Relaunch answers" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
if wait_until 10 uc_prompt_shown; then pass "Quit's question is asked again, for B"; else fail "no question was asked ($(uc_prompt))"; fi
expect_contains "it names the Editor that is no longer the Last Capture" "shown quit editor=$UC_B" "$(uc_prompt)"
expect_equal "still nothing requested while it is up" "$REQ" "$(uc_requests)"
send "$APP_SOCK" "update-script hold-swap on" >/dev/null
send "$EDITOR_SOCK" "editor-prompt-answer discard" >/dev/null
if wait_until 30 uc_val_is progress-percent 30; then pass "Discard goes on: the download starts"; else fail "no download after Discard (state '$(uc_val state)')"; fi
expect_equal "the Update asked for the hash and the disk image" "$((REQ + 2))" "$(uc_requests)"
expect_equal "Cancel is still offered during the download" "enabled" "$(uc_val cancel)"

send "$APP_SOCK" "defaults-set timedCaptureSeconds 10" >/dev/null
# A stored value that is not one of the two counts as the default: the Action bar, as in flow 43.
send "$APP_SOCK" "defaults-set afterSelectingArea nonsense" >/dev/null
UC_FRESH="$(uc_timed fresh-captures)"
area_start "press-shortcut capture-area" >/dev/null
area_drag 0 200 100 400 300
expect_contains "the Action bar offers a 10 s Timed Capture" "item timed-capture|Capture in 10 s|" "$(send "$APP_SOCK" overlay-actionbar)"
press_tile timed-capture 10 10
UC_TIMED_AT="$SECONDS"
if wait_until 5 uc_timed_is state counting; then pass "a Timed Capture is counting down"; else fail "no countdown started (the Capture is '$(send "$APP_SOCK" overlay-facts | head -1)')"; fi
UC_OLD_APP_PID="$APP_PID"
UC_OLD_HELPER="$(helper_pid)"
send "$APP_SOCK" "update-script hold-download off" >/dev/null
if wait_until 60 uc_val_is cancel disabled; then pass "the swap has begun: Cancel is disabled"; else fail "the swap did not begin (state '$(uc_val state)', progress '$(uc_val progress)', status '$(uc_status)')"; fi
expect_equal "the swap began without asking again: B is as Discard left it" "none" "$(uc_prompt)"
expect_equal "the window says it is installing" "installing" "$(uc_val state)"
expect_equal "and which version" "Installing snapit $UC_VERSION…" "$(uc_val headline)"
expect_equal "the title bar's close button is disabled" "disabled" "$(uc_val close-button)"
expect_equal "the menu bar app says it is swapping" "swapping" "$(uc_status)"
expect_equal "the Cancel button is refused" "error nothing to cancel" "$(send "$EDITOR_SOCK" "update-press cancel")"
expect_contains "the close button is refused" "error" "$(send "$EDITOR_SOCK" "update-press close")"
expect_contains "and so is Cancel when the menu bar app is asked directly" "error" "$(send "$APP_SOCK" cancel-update)"
expect_equal "the window is still there, installing" "installing" "$(uc_val state)"
expect_equal "the Update still runs" "swapping" "$(uc_status)"
expect_equal "the installed copy has not been swapped yet" "$UC_BUILD_VERSION" "$(uc_version_of "$UC_DEST")"
# The countdown ended with the swap's start: it was cancelled, not run out.
if uc_timed_is state none; then pass "the Timed Capture that was counting down is cancelled"; else fail "the countdown is '$(uc_timed state)' after the swap began"; fi
if ((SECONDS - UC_TIMED_AT > 9)); then fail "the countdown could have run out before the swap began (the check took $((SECONDS - UC_TIMED_AT)) s): this case proves nothing"; fi
# Wait out the rest of the 10 s and a little more: a countdown that was not cancelled would fire now.
while ((SECONDS - UC_TIMED_AT < 13)); do sleep 0.5; done
expect_equal "no Capture is taken at zero" "$UC_FRESH" "$(uc_timed fresh-captures)"
expect_equal "no Editor opened" "$UC_B $UC_C" "$(open_editors | tr '\n' ' ' | sed 's/ $//')"
expect_equal "the window is still installing, Cancel still disabled" "disabled" "$(uc_val cancel)"
expect_equal "and the close button too" "disabled" "$(uc_val close-button)"
send "$APP_SOCK" "defaults-set timedCaptureSeconds ${TIMER_BEFORE:-3}" >/dev/null

# 8. Released: the swap, and the relaunch. B's edits are discarded with the old copy; the Last
#    Capture, C, is carried over.
send "$APP_SOCK" "update-script hold-swap off" >/dev/null
if wait_until 90 gone "$UC_OLD_APP_PID"; then pass "the snapit that updated quits"; else fail "the snapit that updated is still running"; fi
if wait_until 20 gone "$UC_OLD_HELPER"; then pass "the helper, with the Update window and the Editors, quits"; else fail "the helper is still running"; fi
UC_NEW_PID="$(wait_for_pid "$UC_DEST/Contents/MacOS/snapit" 60)"
if [[ -n "$UC_NEW_PID" ]] && wait_until 30 answers "$APP_SOCK"; then
  pass "the new snapit starts at the installed copy's path"
  APP_PID="$UC_NEW_PID"
else
  abort "the new snapit did not start"
fi
expect_equal "the installed copy is at the announced version" "$UC_VERSION" "$(uc_version_of "$UC_DEST")"
expect_equal "the new snapit has no Update running" "idle" "$(uc_status)"
if wait_until 30 uc_cleaned_after_update; then pass "the old copy and the staging folder are gone"; else fail "left behind: $(ls -A "$UC_APPS" | tr '\n' ' ')$([[ -e "$UC_STAGING" ]] && echo "update-staging")"; fi
expect_equal "no disk image of the Update is attached" "0" "$(uc_attached)"
expect_equal "no downloaded disk image is left" "0" "$(uc_stray_images)"
expect_equal "the Last Capture is C" "$UC_C" "$(send "$APP_SOCK" last-capture)"
expect_equal "the Capture's files are the Last Capture's alone" "1" "$(find "$UC_CAPS" -name '*.pixels' | wc -l | tr -d ' ')"
expect_no_internet "the new menu bar app" "$APP_PID"
sleep 3
UC_BASELINE_MB="$(footprint_mb "$APP_PID")"
expect_equal "Reopen Last Capture brings back C" "ok" "$(send_slow "$APP_SOCK" "menu-click reopen-last-capture")"
EDITOR_N="$(open_editors | tail -1)"
expect_equal "the Editor is the Last Capture's" "$UC_C" "$EDITOR_N"
expect_equal "it is the only Editor: B's edits went with Discard" "$UC_C" "$(open_editors | tr '\n' ' ' | sed 's/ $//')"
UC_NEW_HELPER="$(pid_of "$UC_DEST/Contents/Helpers/")"
send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
wait_until 10 gone "$UC_NEW_HELPER"
expect_memory_returns "the new menu bar app is back at its baseline after the Reopen" "$APP_PID" "$UC_BASELINE_MB"
expect_not_spinning "the new menu bar app" "$APP_PID" 3

# 9. Back to the menu bar app the rest of the run drives, with the fixtures as they were.
send "$APP_SOCK" quit >/dev/null
wait_until 15 gone "$APP_PID"
"$LSREGISTER" -u "$UC_STAGING/snapit.app" 2>/dev/null
unregister_fixture_apps
chmod -R u+w "$UC_APPS" 2>/dev/null
rm -rf "$UC_APPS" "$UC_ASSETS" "$UC_STAGING"
relaunch_app "the menu bar app is running from the build again"
