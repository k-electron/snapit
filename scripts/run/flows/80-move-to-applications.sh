# Flow: where snapit runs from. On every launch snapit checks whether it runs from a mounted
# disk image or a translocated path. From a disk image the helper shows "Move snapit to
# Applications", which copies, strips quarantine, relaunches from Applications and ejects the
# disk image. Translocated with its original in Applications, snapit strips quarantine from that
# copy and relaunches in place. Quarantine is stripped only from an app the user approved with
# Open Anyway.
#
# Everything happens under the run's root: its Applications folder, a fake read-only volume
# below its Volumes folder, a fake eject. The relaunches are real (they keep the test root), so
# the relaunched copy detects where it runs from with the real statfs. Sourced by
# scripts/check-run.sh; it ends with a menu bar app running from $APP_EXE again, for `90-`.
# shellcheck shell=bash

REAL_ROOT="$(real_root)"
APPS="$REAL_ROOT/Applications"
VOL="$REAL_ROOT/Volumes/snapit"
VOLAPP="$VOL/snapit.app"
DEST="$APPS/snapit.app"
TRANSLOCATED="$REAL_ROOT/AppTranslocation/FIXTURE-UUID/d/snapit.app"
EJECTED="$RUN_ROOT/install/ejected"

# fake_disk_image: this process behaves as if it ran from the app on a read-only disk image.
fake_disk_image() {
  send "$APP_SOCK" install-reset >/dev/null
  send "$APP_SOCK" "install-fake-volume $VOL apfs /dev/disk-fixture $VOL ro" >/dev/null
  send "$APP_SOCK" "install-pretend-bundle $VOLAPP" >/dev/null
}
# fake_translocation <origin>: this process behaves as if macOS ran it translocated from <origin>.
fake_translocation() {
  send "$APP_SOCK" install-reset >/dev/null
  send "$APP_SOCK" "install-fake-volume $TRANSLOCATED nullfs $1 $TRANSLOCATED ro" >/dev/null
  send "$APP_SOCK" "install-pretend-bundle $TRANSLOCATED" >/dev/null
}
# location_field <key>: one field of install-location.
location_field() { printf '%s\n' "$(send "$APP_SOCK" install-location)" | sed -n "s/^$1=//p"; }

# 1. A normal launch: the check ran and found nothing to do. Detection with the real statfs.
expect_equal "a launch from a normal place needs no move" "none" "$(location_field decision)"
expect_equal "a normal place is not translocated" "false" "$(location_field translocated)"
expect_equal "a normal place is not a disk image" "false" "$(location_field on-disk-image)"
expect_equal "the launch check has nothing to do from a normal place" "none" "$(send "$APP_SOCK" install-check)"
expect_contains "the real statfs does not take the read-only system volume for a disk image" "on-disk-image=false" "$(send "$APP_SOCK" "install-detect /System/Library")"
expect_contains "the real statfs finds a path under /AppTranslocation/ translocated" "translocated=true" "$(send "$APP_SOCK" "install-detect /tmp/AppTranslocation/X/d/snapit.app")"
expect_equal "no window opens in the menu bar app for the check" "0" "$(onscreen_windows "$APP_PID")"

# The fixtures: snapit's own bundle on a fake read-only volume, approved with Open Anyway.
mkdir -p "$VOL" "$APPS"
ditto "$APP" "$VOLAPP"
approve_quarantine "$VOLAPP"
SOURCE_QUARANTINED="$(quarantine_count "$VOLAPP")"

# Open at Login's default belongs to a copy in Applications: not to one on a disk image.
login_enabled() { [[ "$(send "$APP_SOCK" login-item-status)" == "enabled" ]]; }
send "$APP_SOCK" "login-item-simulate notFound" >/dev/null
send "$APP_SOCK" "defaults-set openAtLoginDefaultApplied false" >/dev/null
fake_disk_image
expect_equal "a copy on a disk image is not opened at login" "not-applied" "$(send "$APP_SOCK" login-item-default)"
expect_equal "so Open at Login is not turned on from a disk image" "notFound" "$(send "$APP_SOCK" login-item-status)"
send "$APP_SOCK" install-reset >/dev/null

# 2. From a disk image: the helper shows the screen. Not Now leaves everything as it is.
fake_disk_image
expect_equal "a fake read-only volume below /Volumes counts as a disk image" "true" "$(location_field on-disk-image)"
expect_equal "from a disk image the decision is to move" "move" "$(location_field decision)"
expect_equal "the disk image's mount point is reported" "$VOL" "$(location_field mount)"
expect_equal "the check from a disk image shows the Move screen" "move-screen-shown" "$(send "$APP_SOCK" install-check)"
HELPER_PID="$(helper_pid)"
FACTS="$(send "$EDITOR_SOCK" move-screen-facts)"
expect_contains "the Move screen is a window in the helper" "window=visible" "$FACTS"
expect_contains "the Move screen is titled Move snapit to Applications" "title=Move snapit to Applications" "$FACTS"
expect_contains "the Move screen says snapit runs from a disk image" "reason=disk-image" "$FACTS"
expect_contains "the Move screen does not mention a replacement when Applications has no snapit" "replaces=false" "$FACTS"
expect_contains "the Move to Applications button has a tooltip" "button move|Move to Applications|Copy snapit" "$FACTS"
expect_contains "the Not Now button has a tooltip" "button later|Not Now|Keep running" "$FACTS"
expect_contains "the helper is a regular app while the Move screen shows" "activation=regular" "$FACTS"
if wait_until 5 has_onscreen_window "$HELPER_PID"; then pass "the Move screen is on screen according to the window server"; else fail "the window server lists no on-screen window for the helper"; fi
expect_equal "the Move screen is the helper's only window" "1" "$(onscreen_windows "$HELPER_PID")"
expect_equal "the menu bar app stays an agent with no window while the Move screen shows" "UIElement" "$(app_type "$APP_PID")"
expect_equal "Not Now answers ok" "ok" "$(send "$EDITOR_SOCK" "move-screen-press later")"
if wait_until 10 gone "$HELPER_PID"; then pass "the helper quits when the Move screen closes"; else fail "the helper is still running after Not Now"; fi
[[ ! -e "$DEST" ]] && pass "Not Now copies nothing to Applications" || fail "Not Now left a copy in Applications"
expect_equal "Not Now leaves the source as it was" "$SOURCE_QUARANTINED" "$(quarantine_count "$VOLAPP")"
[[ ! -e "$EJECTED" ]] && pass "Not Now ejects nothing" || fail "Not Now ejected the disk image"
if answers "$APP_SOCK"; then pass "snapit keeps running after Not Now"; else fail "snapit stopped after Not Now"; fi
sleep 1
AFTER="$(footprint_mb "$APP_PID")"
if awk -v a="$AFTER" -v b="$AT_REST" -v max="$FOOTPRINT_FROM_REST_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "memory is back near the at-rest footprint after the Move screen (${AT_REST} MB at rest, ${AFTER} MB after)"
else
  fail "memory is ${AFTER} MB after the Move screen, ${AT_REST} MB at rest (limit +${FOOTPRINT_FROM_REST_MB_MAX} MB)"
fi
assert_idle_cpu "menu bar app after the Move screen" "$APP_PID" 3

# 2b. A disk image is read-only and can never gain the approved flag, and the app on a
#     double-clicked image may report 0083: running from the image is the approval. The source
#     keeps 0083 for the move in step 4.
unapprove_quarantine "$VOLAPP"
fake_disk_image
expect_equal "a disk image whose app is flagged 0083 still shows the Move screen" "move-screen-shown" "$(send "$APP_SOCK" install-check)"
HELPER_PID="$(helper_pid)"
send "$EDITOR_SOCK" "move-screen-press later" >/dev/null
if wait_until 10 gone "$HELPER_PID"; then pass "the helper quits when that Move screen closes"; else fail "the helper is still running after Not Now"; fi

expect_contains "the launch check logs its outcome with the paths" "launch check: move-screen-shown (bundle $VOLAPP" "$(cat "$RUN_ROOT/app.log")"

# 3. Translocated with its original in Applications, but not approved with Open Anyway yet:
#    nothing is stripped and nothing relaunches.
mkdir -p "$DEST"
touch "$DEST/stand-in"
unapprove_quarantine "$DEST"
fake_translocation "$DEST"
expect_equal "translocated from Applications is reported translocated" "true" "$(location_field translocated)"
expect_equal "the original path is the translocated copy's origin" "$DEST" "$(location_field origin)"
expect_equal "translocated with its original in Applications the decision is to fix in place" "fix-in-place" "$(location_field decision)"
expect_equal "an app that is not approved yet is left alone" "not-approved" "$(send "$APP_SOCK" install-check)"
expect_contains "the launch check logs that the app is not approved" "launch check: not-approved" "$(cat "$RUN_ROOT/app.log")"
expect_equal "quarantine stays on an app that is not approved yet" "2" "$(quarantine_count "$DEST")"
sleep 1
if [[ -z "$(pid_of "$DEST/Contents/MacOS/snapit")" ]] && answers "$APP_SOCK" && kill -0 "$APP_PID" 2>/dev/null; then pass "nothing relaunches for an app that is not approved yet"; else fail "snapit relaunched or stopped without approval"; fi
rm -rf "$DEST"

# 4. From a disk image with a snapit already in Applications: a failed copy costs nothing,
#    then Move replaces that copy, strips quarantine, relaunches from Applications and ejects.
mkdir -p "$DEST"
touch "$DEST/stale-copy"
fake_disk_image
expect_equal "the check from a disk image shows the Move screen again" "move-screen-shown" "$(send "$APP_SOCK" install-check)"
expect_contains "the Move screen says it replaces the snapit in Applications" "replaces=true" "$(send "$EDITOR_SOCK" move-screen-facts)"
HELPER_PID="$(helper_pid)"
chmod 555 "$APPS"
MOVE_REPLY="$(SEND_TIMEOUT=30 send "$EDITOR_SOCK" "move-screen-press move")"
chmod 755 "$APPS"
expect_contains "a move that cannot copy reports why" "error snapit could not copy itself to Applications" "$MOVE_REPLY"
expect_contains "the Move screen shows the failure and stays open" "state=failed" "$(send "$EDITOR_SOCK" move-screen-facts)"
[[ -e "$DEST/stale-copy" ]] && pass "a failed copy leaves the snapit in Applications as it was" || fail "a failed copy damaged the snapit in Applications"
expect_equal "a failed copy leaves no staged copy behind" "" "$(ls -A "$APPS" | grep '^\.snapit-move' || true)"
if answers "$APP_SOCK" && kill -0 "$APP_PID" 2>/dev/null; then pass "snapit keeps running after a failed move"; else fail "snapit stopped after a failed move"; fi

# A copy that has not finished Onboarding (a fresh install) shows it after the move, in a helper of its own:
# the helper that showed the Move screen is on its way out, and must not take Onboarding with it.
send "$APP_SOCK" "defaults-set onboardingStep welcome" >/dev/null
OLD_APP_PID="$APP_PID"
expect_equal "Move to Applications answers ok" "ok" "$(SEND_TIMEOUT=60 send "$EDITOR_SOCK" "move-screen-press move")"
if wait_until 20 gone "$OLD_APP_PID"; then pass "the snapit that ran from the disk image quits"; else fail "the snapit that ran from the disk image is still running"; fi
if wait_until 10 gone "$HELPER_PID"; then pass "the helper quits with it"; else fail "the helper outlived the move"; fi
NEW_PID="$(wait_for_pid "$DEST/Contents/MacOS/snapit")"
if [[ -n "$NEW_PID" ]] && wait_until 20 answers "$APP_SOCK"; then
  pass "snapit relaunches from Applications and takes over the command socket"
  APP_PID="$NEW_PID"
else
  fail "snapit did not relaunch from Applications"
fi
if wait_until 15 login_enabled; then pass "the first launch from Applications turns Open at Login on"; else fail "Open at Login is still '$(send "$APP_SOCK" login-item-status)' after the launch from Applications"; fi
expect_equal "the default is recorded once registering worked" "1" "$(send "$APP_SOCK" "defaults-get openAtLoginDefaultApplied")"
expect_equal "the copy in Applications has no quarantine left" "0" "$(quarantine_count "$DEST")"
[[ ! -e "$DEST/stale-copy" ]] && pass "the move replaced the snapit that was in Applications" || fail "the old snapit is still in Applications"
expect_equal "the move leaves no staged copy behind" "" "$(ls -A "$APPS" | grep '^\.snapit-move' || true)"
expect_equal "the source on the disk image is copied, not moved" "$SOURCE_QUARANTINED" "$(quarantine_count "$VOLAPP")"
expect_equal "the disk image is ejected" "$VOL" "$(cat "$EJECTED" 2>/dev/null)"
expect_equal "the relaunched snapit runs from Applications" "$DEST" "$(location_field bundle)"
expect_equal "the relaunched snapit is not translocated" "false" "$(location_field translocated)"
expect_equal "the relaunched snapit is not on a disk image" "false" "$(location_field on-disk-image)"
expect_equal "the relaunched snapit has nothing to move" "none" "$(location_field decision)"
expect_equal "the relaunched snapit's launch check does nothing" "none" "$(send "$APP_SOCK" install-check)"
expect_contains "the relaunched snapit runs in test mode with the same root" "root=$RUN_ROOT" "$(send "$APP_SOCK" test-seams)"
onboarding_up() { [[ "$(send "$EDITOR_SOCK" onboarding-facts | sed -n 's/^window=//p')" == visible ]]; }
if wait_until 20 onboarding_up; then pass "the relaunched copy shows Onboarding after the Move to Applications check"; else fail "Onboarding did not show after the move"; fi
sleep 2
if onboarding_up; then pass "Onboarding stays: the helper that showed the Move screen did not take it with it"; else fail "Onboarding went away with the old helper"; fi
send "$EDITOR_SOCK" onboarding-close >/dev/null 2>&1
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
wait_until 10 gone "$(pid_of "$DEST/Contents/Helpers/")"
sleep 3
assert_idle_cpu "the relaunched menu bar app" "$APP_PID" "$IDLE_SECONDS"
FOOTPRINT="$(footprint_mb "$APP_PID")"
if awk -v f="$FOOTPRINT" -v max="$FOOTPRINT_MB_MAX" 'BEGIN { exit !(f > 0 && f <= max) }'; then
  pass "the relaunched menu bar app footprint is ${FOOTPRINT} MB (ceiling ${FOOTPRINT_MB_MAX} MB)"
else
  fail "the relaunched menu bar app footprint is '${FOOTPRINT}' MB (ceiling ${FOOTPRINT_MB_MAX} MB)"
fi

# Translocated with an original that carries no quarantine: there is nothing to strip, so
# snapit stays put instead of relaunching on every launch.
fake_translocation "$DEST"
expect_equal "a translocated copy with no quarantine to strip stays running" "none" "$(send "$APP_SOCK" install-check)"
sleep 1
if kill -0 "$APP_PID" 2>/dev/null && answers "$APP_SOCK"; then pass "snapit does not relaunch when there is no quarantine to strip"; else fail "snapit relaunched with nothing to strip"; fi

# 5. Translocated with its original in Applications and approved: strip quarantine from that
#    copy and relaunch in place, with no Move screen and no eject.
approve_quarantine "$DEST"
fake_translocation "$DEST"
EJECT_LINES="$(cat "$EJECTED" 2>/dev/null | wc -l | tr -d ' ')"
OLD_APP_PID="$APP_PID"
send "$APP_SOCK" "login-item-set off" >/dev/null
expect_equal "an approved translocated copy is fixed in place" "fixed-in-place" "$(send "$APP_SOCK" install-check)"
if wait_until 20 gone "$OLD_APP_PID"; then pass "the translocated snapit quits"; else fail "the translocated snapit is still running"; fi
NEW_PID="$(wait_for_pid "$DEST/Contents/MacOS/snapit")"
if [[ -n "$NEW_PID" && "$NEW_PID" != "$OLD_APP_PID" ]] && wait_until 20 answers "$APP_SOCK"; then
  pass "snapit relaunches in place"
  APP_PID="$NEW_PID"
else
  fail "snapit did not relaunch in place"
fi
expect_equal "the copy that was translocated has no quarantine left" "0" "$(quarantine_count "$DEST")"
sleep 2
if [[ "$(send "$APP_SOCK" login-item-status)" != "enabled" ]]; then pass "a launch from Applications leaves an Open at Login that was turned off alone"; else fail "a relaunch from Applications turned Open at Login on again"; fi
expect_equal "the in-place fix shows no Move screen and starts no helper" "" "$(pid_of "$DEST/Contents/Helpers/")"
expect_equal "the in-place fix ejects nothing" "$EJECT_LINES" "$(cat "$EJECTED" 2>/dev/null | wc -l | tr -d ' ')"
expect_equal "the relaunched snapit runs from the same place" "$DEST" "$(location_field bundle)"
expect_equal "the relaunched snapit is not translocated after the fix" "false" "$(location_field translocated)"
sleep 3
assert_idle_cpu "the menu bar app relaunched in place" "$APP_PID" 3

# 6. Back to the menu bar app the rest of the run drives.
send "$APP_SOCK" quit >/dev/null
wait_until 10 gone "$APP_PID"
unregister_fixture_apps
chmod -R u+w "$REAL_ROOT/Applications" "$REAL_ROOT/Volumes" 2>/dev/null
rm -rf "$REAL_ROOT/Applications" "$REAL_ROOT/Volumes" "$REAL_ROOT/AppTranslocation" "$RUN_ROOT/install"
(nohup "$APP_EXE" >"$RUN_ROOT/app.log" 2>&1 &)
if wait_until 10 answers "$APP_SOCK"; then pass "the menu bar app is running from the build again"; else abort "the menu bar app did not restart"; fi
APP_PID="$(pid_of "$APP_EXE")"
