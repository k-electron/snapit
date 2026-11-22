# Flow: Update and Relaunch, the successful path. The Update window offers Update and Relaunch
# beside a Release Page link; choosing it has the menu bar app download the release's disk image
# and its .sha256, check the image against that hash, attach it read-only and hidden, copy
# snapit.app out of it into a staging folder, detach it, swap the copy in at the installed copy's
# path while snapit and the helper still run, and relaunch through the helper's quit: the new
# snapit starts under the same root, deletes the old copy and the staging folder, and takes over
# the Last Capture, which Reopen Last Capture brings back with its Annotations.
#
# Everything real happens inside the run's root. The run builds a small disk image with
# `hdiutil create` from a copy of the built snapit at the announced version (both Info.plists set,
# re-signed ad hoc, helper first), puts it and its .sha256 where the fixture release endpoint
# serves them (`<root>/update-assets`), and pretends the running snapit is the copy it places in
# the root's Applications folder (`install-pretend-bundle`). snapit attaches the image for real,
# runs the real swap and relaunches the real copy. The run never goes online: the HTTP edge is the
# fixture, which logs each request it is asked to send. A request for a file the fixture does not
# hold (the first press, before the files are there) is a 404, which leaves the installed copy as
# it was.
#
# Sourced by scripts/check-run.sh. It quits the menu bar app (the old one quits by itself) and ends
# with a menu bar app running from $APP_EXE again, as the flows after it expect.
# shellcheck shell=bash
# shellcheck source=../editor-tools.sh
source "$ROOT_DIR/scripts/run/editor-tools.sh"

UR_ROOT="$(real_root)"
UR_APPS="$UR_ROOT/Applications"
UR_DEST="$UR_APPS/snapit.app"
UR_ASSETS="$RUN_ROOT/update-assets"
UR_BUILT="$RUN_ROOT/update-built"
UR_STAGING="$RUN_ROOT/update-staging"
UR_CAPS="$RUN_ROOT/captures"
UR_BUILD_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
UR_VERSION="$((${UR_BUILD_VERSION%%.*} + 1)).0.0"
UR_TAG="v$UR_VERSION"
UR_PAGE="https://github.com/k-electron/snapit/releases/tag/$UR_TAG"
UR_FILES="https://github.com/k-electron/snapit/releases/download/$UR_TAG/snapit-$UR_VERSION.dmg"

ur_enc() { printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge'; }
ur_val() { send "$EDITOR_SOCK" update-facts | sed -n "s/^$1=//p" | head -1; }
ur_val_is() { [[ "$(ur_val "$1")" == "$2" ]]; }
ur_buttons() { send "$EDITOR_SOCK" update-facts | sed -n 's/^button //p' | awk -F'|' '{ print $1 }' | tr '\n' ' '; }
ur_settled() { local state; state="$(ur_val state)"; [[ -n "$state" && "$state" != checking ]]; }
ur_check() {
  send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
  wait_until 10 ur_settled
}
ur_requests() { send "$APP_SOCK" update-requests; }
ur_requests_are() { [[ "$(ur_requests)" == "$1" ]]; }
# The request log, one line per request, and the lines after the first <n>.
ur_log_lines() { if [[ -e "$RUN_ROOT/update-requests" ]]; then wc -l <"$RUN_ROOT/update-requests" | tr -d ' '; else echo 0; fi; }
ur_log_after() { tail -n +"$(($1 + 1))" "$RUN_ROOT/update-requests" 2>/dev/null; }
ur_version_of() { plutil -extract CFBundleShortVersionString raw "$1/Contents/Info.plist" 2>/dev/null; }
# Lines of `hdiutil info` that name this run: an image of the Update still attached.
ur_attached() { hdiutil info 2>/dev/null | grep -cF "$(basename "$RUN_ROOT")"; }
ur_gone_after_update() { [[ ! -e "$UR_STAGING" && "$(ls -A "$UR_APPS" 2>/dev/null)" == "snapit.app" ]]; }
ur_annotations() { plutil -extract history.state.annotations raw -o - "$UR_CAPS/capture-$1.state" 2>/dev/null; }
ur_has_annotation() { [[ "$(ur_annotations "$1")" == "1" ]]; }
ur_document() { send "$EDITOR_SOCK" "editor-document $EDITOR_N" | grep -E '^(annotation|undo-steps|redo-steps|revision)'; }
ur_gone_helper() { [[ -z "$(pid_of "$UR_DEST/Contents/Helpers/")" ]]; }
ur_no_captures() { [[ -z "$(ls -A "$UR_CAPS" 2>/dev/null)" ]]; }

REQUESTS_AT_START="$(ur_requests)"
LOG_AT_START="$(ur_log_lines)"

# 1. The fixtures: a disk image holding a copy of this build at the announced version, signed ad
#    hoc (the helper first, then the app: no --deep), with its hash in the form the release uses.
mkdir -p "$UR_APPS" "$UR_BUILT/src"
ditto --norsrc --noextattr "$APP" "$UR_BUILT/src/snapit.app"
for plist in "$UR_BUILT/src/snapit.app/Contents/Info.plist" "$UR_BUILT/src/snapit.app/Contents/Helpers/snapit Editor.app/Contents/Info.plist"; do
  plutil -replace CFBundleShortVersionString -string "$UR_VERSION" "$plist"
done
codesign --force --sign - --timestamp=none --options runtime "$UR_BUILT/src/snapit.app/Contents/Helpers/snapit Editor.app" >/dev/null 2>&1
codesign --force --sign - --timestamp=none --options runtime "$UR_BUILT/src/snapit.app" >/dev/null 2>&1
if codesign --verify --deep --strict "$UR_BUILT/src/snapit.app" >/dev/null 2>&1; then pass "the copy for the disk image is signed and verifies"; else abort "the copy for the disk image does not verify"; fi
hdiutil create -srcfolder "$UR_BUILT/src" -volname snapit -format UDZO -quiet "$UR_BUILT/snapit-$UR_VERSION.dmg" >/dev/null 2>&1
(cd "$UR_BUILT" && shasum -a 256 "snapit-$UR_VERSION.dmg" >"snapit-$UR_VERSION.dmg.sha256")
"$LSREGISTER" -u "$UR_BUILT/src/snapit.app/Contents/Helpers/snapit Editor.app" 2>/dev/null
"$LSREGISTER" -u "$UR_BUILT/src/snapit.app" 2>/dev/null
rm -rf "$UR_BUILT/src"
if [[ -s "$UR_BUILT/snapit-$UR_VERSION.dmg" && -s "$UR_BUILT/snapit-$UR_VERSION.dmg.sha256" ]]; then pass "the disk image and its hash are built"; else abort "no disk image was built"; fi

# The running snapit pretends to be the copy in Applications: the Update swaps that copy.
ditto "$APP" "$UR_DEST"
send "$APP_SOCK" "install-pretend-bundle $UR_DEST" >/dev/null
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
expect_equal "the installed copy is the build's version" "$UR_BUILD_VERSION" "$(ur_version_of "$UR_DEST")"

# A Capture with an Annotation, its Editor left open: it is the Last Capture the Update carries over.
if ! capture_into_editor "menu-click capture.screen"; then abort "no Capture for the Update"; fi
UR_N="$EDITOR_N"
UR_OLD_HELPER="$HELPER_PID"
keystroke r >/dev/null
drag 40 30 120 90 >/dev/null
if wait_until 5 ur_has_annotation "$UR_N"; then pass "the Last Capture's state file holds the Annotation"; else fail "no state file with the Annotation"; fi
UR_DOCUMENT="$(ur_document)"
expect_contains "the Editor holds an Annotation" "annotation" "$UR_DOCUMENT"
expect_equal "nothing was requested while the run set this up" "$REQUESTS_AT_START" "$(ur_requests)"

# 2. Check for Updates finds the release; the window offers Update and Relaunch and Release Page.
send "$APP_SOCK" "update-script release $(ur_enc "$UR_TAG") $(ur_enc "$UR_PAGE") $(ur_enc "The newer snapit.")" >/dev/null
ur_check
expect_equal "the window announces the newer release" "newer" "$(ur_val state)"
expect_equal "with its version" "snapit $UR_VERSION is available." "$(ur_val headline)"
expect_equal "and offers Close, Release Page and Update and Relaunch" "close release-page update " "$(ur_buttons)"
expect_equal "Check for Updates sent one request" "$((REQUESTS_AT_START + 1))" "$(ur_requests)"

# 3. With none of the release's files there, Update and Relaunch stops at the first request. The
#    installed copy is as it was, nothing is left, and the window says the Update stopped and
#    offers it again (flow 60 covers each way an Update stops).
expect_equal "Update and Relaunch answers at once" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
wait_until 20 ur_val_is state failed
expect_equal "the window says the Update stopped" "failed" "$(ur_val state)"
expect_equal "and offers Update and Relaunch again" "close release-page update " "$(ur_buttons)"
expect_equal "the Update asked for the hash and went no further" "$((REQUESTS_AT_START + 2))" "$(ur_requests)"
expect_equal "the installed copy is as it was" "$UR_BUILD_VERSION" "$(ur_version_of "$UR_DEST")"
expect_equal "nothing is left in Applications" "snapit.app" "$(ls -A "$UR_APPS")"
[[ ! -e "$UR_STAGING" ]] && pass "no staging folder is left" || fail "a staging folder is left"
expect_equal "the Editor is still open" "$UR_N" "$(open_editors | tail -1)"
if kill -0 "$APP_PID" 2>/dev/null && answers "$APP_SOCK"; then pass "snapit keeps running"; else fail "snapit stopped"; fi

# 4. With the files there, held at its first request: the window says it is installing.
mkdir -p "$UR_ASSETS"
cp "$UR_BUILT/snapit-$UR_VERSION.dmg" "$UR_BUILT/snapit-$UR_VERSION.dmg.sha256" "$UR_ASSETS/"
rm -rf "$UR_BUILT"
UR_REQUESTS_BEFORE="$(ur_requests)"
send "$APP_SOCK" "update-script hold on" >/dev/null
expect_equal "Update and Relaunch answers at once again" "ok" "$(send "$EDITOR_SOCK" "update-press update")"
if wait_until 10 ur_requests_are "$((UR_REQUESTS_BEFORE + 1))"; then pass "the Update asks for the release's hash"; else fail "the Update sent no request (requests: $(ur_requests))"; fi
wait_until 10 ur_val_is state installing
expect_equal "the window says it is installing" "installing" "$(ur_val state)"
expect_equal "and which version" "Installing snapit $UR_VERSION…" "$(ur_val headline)"
expect_equal "Update and Relaunch is not offered while it installs" "close " "$(ur_buttons)"
expect_equal "a second press does nothing" "error nothing to update" "$(send "$EDITOR_SOCK" "update-press update")"
expect_equal "the installed copy is untouched until the swap" "$UR_BUILD_VERSION" "$(ur_version_of "$UR_DEST")"

# 5. Released: download, check, copy, swap, relaunch.
UR_OLD_APP_PID="$APP_PID"
send "$APP_SOCK" "update-script hold off" >/dev/null
if wait_until 90 gone "$UR_OLD_APP_PID"; then pass "the snapit that updated quits"; else fail "the snapit that updated is still running"; fi
if wait_until 15 gone "$UR_OLD_HELPER"; then pass "the helper, with the Update window and the Editor, quits first"; else fail "the helper is still running"; fi
UR_NEW_PID="$(wait_for_pid "$UR_DEST/Contents/MacOS/snapit" 60)"
if [[ -n "$UR_NEW_PID" ]] && wait_until 30 answers "$APP_SOCK"; then
  pass "the new snapit starts at the installed copy's path and takes over the command socket"
  APP_PID="$UR_NEW_PID"
else
  abort "the new snapit did not start"
fi
expect_contains "the new snapit runs in test mode under the same root" "root=$RUN_ROOT" "$(send "$APP_SOCK" test-seams)"
expect_equal "the installed copy is at the announced version" "$UR_VERSION" "$(ur_version_of "$UR_DEST")"
expect_equal "and so is the helper inside it" "$UR_VERSION" "$(ur_version_of "$UR_DEST/Contents/Helpers/snapit Editor.app")"
if codesign --verify --deep --strict "$UR_DEST" >/dev/null 2>&1; then pass "the installed copy's signature is valid, the helper's included"; else fail "the installed copy's signature does not verify"; fi
expect_equal "the installed copy carries no quarantine" "0" "$(quarantine_count "$UR_DEST")"

# The old copy and the staging folder go once the old snapit has quit; the disk image is detached.
if wait_until 30 ur_gone_after_update; then pass "the old copy and the staging folder are gone"; else fail "left behind: $(ls -A "$UR_APPS" | tr '\n' ' ')$([[ -e "$UR_STAGING" ]] && echo "update-staging")"; fi
expect_equal "Applications holds the one snapit" "snapit.app" "$(ls -A "$UR_APPS")"
expect_equal "the disk image is detached" "0" "$(ur_attached)"
expect_equal "no image of the Update is mounted" "0" "$(mount | grep -c "update-staging")"
if find "$RUN_ROOT" -name '*.dmg' 2>/dev/null | grep -q "update-staging"; then fail "a disk image is left in the staging folder"; else pass "no downloaded file is left"; fi

# What was requested: the check, the hash that 404'd, then the hash and the disk image, each at an
# address built from the tag, each with the generic headers and nothing about the user.
UR_LOG="$(ur_log_after "$LOG_AT_START")"
expect_equal "the requests were the check, the hash twice and the disk image once, in that order" \
  "GET https://api.github.com/repos/k-electron/snapit/releases/latest
GET $UR_FILES.sha256
GET $UR_FILES.sha256
GET $UR_FILES" "$(printf '%s\n' "$UR_LOG" | awk '{ print $1 " " $2 }')"
expect_equal "a file's request sets a generic User-Agent, Accept and a fixed Accept-Language" \
  "Accept=application/octet-stream Accept-Language=en User-Agent=snapit" \
  "$(printf '%s\n' "$UR_LOG" | grep '/download/' | awk '{ $1 = ""; $2 = ""; $3 = ""; sub(/^ +/, ""); print }' | sort -u)"
if printf '%s\n' "$UR_LOG" | grep -qiE 'authorization|cookie|token|@'; then fail "a request carries credentials"; else pass "no request carries credentials"; fi
expect_no_internet "the new menu bar app" "$APP_PID"
# The new snapit's own baseline, once its launch work and the leftovers' removal are over.
sleep 3
UR_BASELINE_MB="$(footprint_mb "$APP_PID")"

# 6. The new copy runs at that version: Check for Updates against the same release says it is the one it has.
send "$APP_SOCK" "update-script release $(ur_enc "$UR_TAG") $(ur_enc "$UR_PAGE") $(ur_enc "Same.")" >/dev/null
ur_check
expect_equal "the new snapit is at the announced version" "snapit $UR_VERSION is up to date." "$(ur_val headline)"
expect_no_internet "the Editor helper of the new snapit" "$(pid_of "$UR_DEST/Contents/Helpers/")"
send_slow "$EDITOR_SOCK" "update-press close" >/dev/null
wait_until 10 ur_gone_helper

# 7. Reopen Last Capture brings back the Last Capture, Annotations included.
expect_equal "Reopen Last Capture is enabled" "yes" "$(send "$APP_SOCK" "menu-enabled reopen-last-capture")"
expect_equal "the Last Capture is the one before the Update" "$UR_N" "$(send "$APP_SOCK" last-capture)"
expect_equal "the Reopen shows it" "ok" "$(send_slow "$APP_SOCK" "menu-click reopen-last-capture")"
EDITOR_N="$(open_editors | tail -1)"
expect_equal "the Editor is the Last Capture's" "$UR_N" "$EDITOR_N"
expect_equal "with its Annotations, Undo and Redo steps and revision as they were" "$UR_DOCUMENT" "$(ur_document)"
UR_NEW_HELPER="$(pid_of "$UR_DEST/Contents/Helpers/")"
send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N escape" >/dev/null
wait_until 10 gone "$UR_NEW_HELPER"
expect_memory_returns "the new menu bar app is back at its baseline after the Update window and the Reopen" "$APP_PID" "$UR_BASELINE_MB"
expect_not_spinning "the new menu bar app" "$APP_PID" 3

# 8. Quitting still removes the Last Capture: the carry-over was the Update's alone.
send "$APP_SOCK" quit >/dev/null
wait_until 15 gone "$APP_PID"
if wait_until 10 ur_no_captures; then pass "a normal quit removes the Last Capture, after an Update as before"; else fail "the Last Capture is still there after a quit: $(ls -A "$UR_CAPS" | tr '\n' ' ')"; fi

# 9. Back to the menu bar app the rest of the run drives.
"$LSREGISTER" -u "$UR_STAGING/snapit.app" 2>/dev/null
unregister_fixture_apps
chmod -R u+w "$UR_APPS" 2>/dev/null
rm -rf "$UR_APPS" "$UR_ASSETS" "$UR_STAGING"
relaunch_app "the menu bar app is running from the build again"
