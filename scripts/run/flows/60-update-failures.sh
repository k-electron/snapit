# Flow: when an Update can't finish. Everything that stops an Update leaves the installed snapit as
# it was, shows one line naming its cause in the Update window beside the Release Page link, and
# leaves no downloaded, mounted or staged file behind:
#   - GitHub unreachable, or too slow, before the download and half-way through it;
#   - a download that does not match the hash the release publishes;
#   - a staged bundle with another bundle identifier, another version than the announced tag, or a
#     signature that fails the strict check (the Editor helper inside it is the broken part);
#   - a swap that fails (the installed copy is read-only).
# And where snapit cannot update itself (it runs from a disk image, or from a folder it cannot
# write to) the window says "Move snapit to Applications to update it here" in place of Update and
# Relaunch, beside the Release Page link, and snapit never asks for an administrator's password.
#
# Everything real happens inside the run's root, as in flow 59: the disk images are built with
# `hdiutil create` from copies of the built snapit, signed ad hoc, and put where the fixture
# release endpoint serves them (`<root>/update-assets`); snapit attaches them for real and runs the
# real checks. The running snapit pretends to be the copy in the root's Applications folder. The run
# never goes online. No Update succeeds here, so snapit is never relaunched: flow 59 covers that.
#
# Sourced by scripts/check-run.sh; leaves the menu bar app running from $APP as it found it.
# shellcheck shell=bash

UF_ROOT="$(real_root)"
UF_APPS="$UF_ROOT/Applications"
UF_DEST="$UF_APPS/snapit.app"
UF_VOL="$UF_ROOT/Volumes/snapit"
UF_ASSETS="$RUN_ROOT/update-assets"
UF_BUILT="$RUN_ROOT/update-failures-built"
UF_STAGING="$RUN_ROOT/update-staging"
UF_BUILD_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
UF_MAJOR="$((${UF_BUILD_VERSION%%.*} + 1))"
UF_VERSION="$UF_MAJOR.0.0"
UF_OTHER_VERSION="$UF_MAJOR.0.1"
UF_TAG="v$UF_VERSION"
UF_PAGE="https://github.com/k-electron/snapit/releases/tag/$UF_TAG"
UF_IMAGE="snapit-$UF_VERSION.dmg"
UF_FILES="https://github.com/k-electron/snapit/releases/download/$UF_TAG/$UF_IMAGE"
UF_MOVE_LINE="Move snapit to Applications to update it here"

uf_enc() { printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge'; }
uf_val() { send "$EDITOR_SOCK" update-facts | sed -n "s/^$1=//p" | head -1; }
uf_val_is() { [[ "$(uf_val "$1")" == "$2" ]]; }
uf_buttons() { send "$EDITOR_SOCK" update-facts | sed -n 's/^button //p' | awk -F'|' '{ print $1 }' | tr '\n' ' '; }
uf_settled() { local state; state="$(uf_val state)"; [[ -n "$state" && "$state" != checking ]]; }
uf_check() {
  send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
  wait_until 10 uf_settled
}
uf_requests() { send "$APP_SOCK" update-requests; }
uf_version_of() { plutil -extract CFBundleShortVersionString raw "$1/Contents/Info.plist" 2>/dev/null; }
uf_attached() { hdiutil info 2>/dev/null | grep -cF "$(basename "$RUN_ROOT")"; }
uf_log_lines() { if [[ -e "$RUN_ROOT/update-requests" ]]; then wc -l <"$RUN_ROOT/update-requests" | tr -d ' '; else echo 0; fi; }
uf_log_after() { tail -n +"$(($1 + 1))" "$RUN_ROOT/update-requests" 2>/dev/null | awk '{ print $2 }'; }
uf_script_release() {
  send "$APP_SOCK" "update-script release $(uf_enc "$UF_TAG") $(uf_enc "$UF_PAGE") $(uf_enc "The newer snapit.")" >/dev/null
}

# uf_variant <name> <bundle identifier or empty> <version> <tamper: yes|no>: a disk image in
# $UF_BUILT/<name>/ holding a copy of this build with that identifier and version, signed ad hoc
# (the helper first, then the app: no --deep); `tamper` changes the helper's program after signing.
uf_variant() {
  local dir="$UF_BUILT/$1" app plist
  app="$dir/src/snapit.app"
  mkdir -p "$dir/src"
  ditto --norsrc --noextattr "$APP" "$app"
  for plist in "$app/Contents/Info.plist" "$app/Contents/Helpers/snapit Editor.app/Contents/Info.plist"; do
    plutil -replace CFBundleShortVersionString -string "$3" "$plist"
  done
  if [[ -n "$2" ]]; then plutil -replace CFBundleIdentifier -string "$2" "$app/Contents/Info.plist"; fi
  codesign --force --sign - --timestamp=none --options runtime "$app/Contents/Helpers/snapit Editor.app" >/dev/null 2>&1
  codesign --force --sign - --timestamp=none --options runtime "$app" >/dev/null 2>&1
  if [[ "$4" == yes ]]; then printf 'x' >>"$app/Contents/Helpers/snapit Editor.app/Contents/MacOS/snapit Editor"; fi
  if codesign --verify --deep --strict "$app" >/dev/null 2>&1; then
    if [[ "$4" == yes ]]; then abort "the tampered copy '$1' still verifies"; fi
  elif [[ "$4" != yes ]]; then
    abort "the copy '$1' does not verify"
  fi
  hdiutil create -srcfolder "$dir/src" -volname snapit -format UDZO -quiet "$dir/$UF_IMAGE" >/dev/null 2>&1
  (cd "$dir" && shasum -a 256 "$UF_IMAGE" >"$UF_IMAGE.sha256")
  "$LSREGISTER" -u "$app/Contents/Helpers/snapit Editor.app" 2>/dev/null
  "$LSREGISTER" -u "$app" 2>/dev/null
  rm -rf "$dir/src"
  [[ -s "$dir/$UF_IMAGE" && -s "$dir/$UF_IMAGE.sha256" ]] || abort "no disk image was built for '$1'"
}
# uf_serve <name>: the release's files are that variant's.
uf_serve() { cp "$UF_BUILT/$1/$UF_IMAGE" "$UF_BUILT/$1/$UF_IMAGE.sha256" "$UF_ASSETS/"; }

# uf_attempt: presses Update and Relaunch and waits for the Update to stop.
uf_attempt() {
  send "$EDITOR_SOCK" "update-press update" >/dev/null
  wait_until 120 uf_val_is state failed
}

# uf_expect_untouched <case>: the installed copy is as it was and the Update left nothing: no staging
# folder, no downloaded disk image, nothing mounted, nothing else in Applications.
uf_expect_untouched() {
  expect_equal "$1: the installed copy is at its version" "$UF_BUILD_VERSION" "$(uf_version_of "$UF_DEST")"
  if cmp -s "$APP/Contents/MacOS/snapit" "$UF_DEST/Contents/MacOS/snapit"; then pass "$1: the installed copy's program is as it was"; else fail "$1: the installed copy's program changed"; fi
  expect_equal "$1: Applications holds the installed copy and nothing else" "snapit.app" "$(ls -A "$UF_APPS")"
  if [[ -e "$UF_STAGING" ]]; then fail "$1: a staging folder is left: $(ls -A "$UF_STAGING" | tr '\n' ' ')"; else pass "$1: no staging folder is left"; fi
  if find "$RUN_ROOT" -name '*.dmg' -not -path "$UF_ASSETS/*" -not -path "$UF_BUILT/*" 2>/dev/null | grep -q .; then fail "$1: a downloaded disk image is left"; else pass "$1: no downloaded disk image is left"; fi
  expect_equal "$1: no disk image is attached" "0" "$(uf_attached)"
  expect_equal "$1: nothing is mounted for the Update" "0" "$(mount | grep -c "update-staging")"
  if kill -0 "$APP_PID" 2>/dev/null && answers "$APP_SOCK"; then pass "$1: snapit keeps running"; else fail "$1: snapit stopped"; fi
}

# uf_expect_failed <case> <line>: the window says the Update stopped, in that one line, beside the
# Release Page link; the Update can be tried again.
uf_expect_failed() {
  expect_equal "$1: the window says the Update stopped" "failed" "$(uf_val state)"
  expect_equal "$1: in one line naming the cause" "$2" "$(uf_val notice)"
  expect_equal "$1: it still announces the release" "snapit $UF_VERSION is available." "$(uf_val headline)"
  expect_equal "$1: and offers Close, Release Page and Update and Relaunch" "close release-page update " "$(uf_buttons)"
  expect_equal "$1: the Release Page is the release's" "$UF_PAGE" "$(uf_val url)"
  uf_expect_untouched "$1"
}

REQUESTS_AT_START="$(uf_requests)"

# 1. The fixtures: one disk image per way a bundle can be wrong, and the good one.
mkdir -p "$UF_APPS" "$UF_ASSETS" "$UF_BUILT"
uf_variant good "" "$UF_VERSION" no
uf_variant wrong-identifier "dev.snapit.not-snapit" "$UF_VERSION" no
uf_variant wrong-version "" "$UF_OTHER_VERSION" no
uf_variant broken-signature "" "$UF_VERSION" yes
pass "the disk images are built: good, wrong identifier, wrong version, broken signature"

# The running snapit pretends to be the copy in Applications.
ditto "$APP" "$UF_DEST"
send "$APP_SOCK" "install-pretend-bundle $UF_DEST" >/dev/null
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
expect_equal "the installed copy is the build's version" "$UF_BUILD_VERSION" "$(uf_version_of "$UF_DEST")"
expect_equal "nothing was requested while the run set this up" "$REQUESTS_AT_START" "$(uf_requests)"

# 2. Check for Updates finds the release; the one check is the only request so far.
uf_script_release
uf_serve good
uf_check
expect_equal "the window announces the newer release" "newer" "$(uf_val state)"
expect_equal "with no line of its own" "" "$(uf_val notice)"
expect_equal "and offers Close, Release Page and Update and Relaunch" "close release-page update " "$(uf_buttons)"
expect_equal "Check for Updates sent one request" "$((REQUESTS_AT_START + 1))" "$(uf_requests)"
sleep 2
UF_BASELINE_MB="$(footprint_mb "$APP_PID")"
UF_REQUESTS="$(uf_requests)"

# 3. GitHub unreachable or too slow: the first request of the Update fails; nothing is downloaded.
send "$APP_SOCK" "update-script offline" >/dev/null
uf_attempt
uf_expect_failed "offline" "Couldn't reach GitHub. Your snapit was not changed."
expect_equal "offline: the Update asked for the hash and went no further" "$((UF_REQUESTS + 1))" "$(uf_requests)"
UF_REQUESTS="$(uf_requests)"

send "$APP_SOCK" "update-script timeout" >/dev/null
uf_attempt
uf_expect_failed "timeout" "GitHub took too long to answer. Your snapit was not changed."
expect_equal "timeout: the Update asked for the hash and went no further" "$((UF_REQUESTS + 1))" "$(uf_requests)"
UF_REQUESTS="$(uf_requests)"

# 4. Mid-download: the hash arrives, the disk image starts and the connection drops; what arrived is gone.
uf_script_release
LOG_BEFORE="$(uf_log_lines)"
send "$APP_SOCK" "update-script download offline" >/dev/null
uf_attempt
uf_expect_failed "offline mid-download" "Couldn't reach GitHub. Your snapit was not changed."
expect_equal "offline mid-download: the Update asked for the hash and then the disk image" "$UF_FILES.sha256
$UF_FILES" "$(uf_log_after "$LOG_BEFORE")"

LOG_BEFORE="$(uf_log_lines)"
send "$APP_SOCK" "update-script download timeout" >/dev/null
uf_attempt
uf_expect_failed "timeout mid-download" "GitHub took too long to answer. Your snapit was not changed."
expect_equal "timeout mid-download: the same two requests" "$UF_FILES.sha256
$UF_FILES" "$(uf_log_after "$LOG_BEFORE")"
send "$APP_SOCK" "update-script download ok" >/dev/null

# 5. A download that does not match its hash: the disk image is the good one, the hash is another.
printf '%064d  %s\n' 0 "$UF_IMAGE" >"$UF_ASSETS/$UF_IMAGE.sha256"
LOG_BEFORE="$(uf_log_lines)"
uf_attempt
uf_expect_failed "wrong hash" "The download was damaged, so it was not installed."
expect_equal "wrong hash: the disk image was downloaded to be checked" "$UF_FILES.sha256
$UF_FILES" "$(uf_log_after "$LOG_BEFORE")"

# 6. A staged bundle that fails a check is never swapped in: each check has its own line.
uf_serve wrong-identifier
uf_attempt
uf_expect_failed "wrong bundle identifier" "The download is not snapit, so it was not installed."
uf_serve wrong-version
uf_attempt
uf_expect_failed "wrong bundle version" "The download is not the version announced, so it was not installed."
uf_serve broken-signature
uf_attempt
uf_expect_failed "broken signature in the Editor helper" "The download's signature is not valid, so it was not installed."

# 7. A swap that fails: the installed copy is read-only, so nothing can be traded for it. The
#    copy is untouched and the staged one goes.
uf_serve good
chmod 555 "$UF_DEST"
uf_attempt
chmod 755 "$UF_DEST"
uf_expect_failed "swap" "snapit couldn't replace itself. Your snapit was not changed."
if codesign --verify --deep --strict "$UF_DEST" >/dev/null 2>&1; then pass "swap: the installed copy's signature still verifies"; else fail "swap: the installed copy's signature does not verify"; fi

# The Release Page link of a failure opens the release's page and closes the window.
rm -f "$RUN_ROOT/browser-links"
expect_equal "Release Page runs after a failure" "ok" "$(send_slow "$EDITOR_SOCK" "update-press release-page")"
expect_equal "the browser is asked to open the release page of the tag" "$UF_PAGE" "$(cat "$RUN_ROOT/browser-links" 2>/dev/null)"
rm -f "$RUN_ROOT/browser-links"

# 8. snapit on a disk image cannot update itself there: the window says where to move it, offers the
#    Release Page link and no Update and Relaunch, and nothing is requested or asked for.
mkdir -p "$UF_VOL"
send "$APP_SOCK" install-reset >/dev/null
send "$APP_SOCK" "install-fake-volume $UF_VOL apfs /dev/disk-fixture $UF_VOL ro" >/dev/null
send "$APP_SOCK" "install-pretend-bundle $UF_VOL/snapit.app" >/dev/null
UF_REQUESTS="$(uf_requests)"
uf_check
expect_equal "from a disk image the window announces the release but cannot install it here" "cannot-install" "$(uf_val state)"
expect_equal "it says to move snapit to Applications" "$UF_MOVE_LINE" "$(uf_val notice)"
expect_equal "and offers Close and Release Page, no Update and Relaunch" "close release-page " "$(uf_buttons)"
expect_equal "the reminder after an update is not shown" "" "$(uf_val reminder)"
expect_equal "pressing Update and Relaunch does nothing" "error nothing to update" "$(send "$EDITOR_SOCK" "update-press update")"
expect_contains "the menu bar app refuses an Update there too" "error not-here" "$(send "$APP_SOCK" "install-update $UF_VERSION")"
expect_equal "only the check was requested" "$((UF_REQUESTS + 1))" "$(uf_requests)"
expect_equal "the menu bar app has started nothing" "" "$(pgrep -P "$APP_PID" | tr '\n' ' ')"
if pgrep -f security_authtrampoline >/dev/null; then fail "an administrator's password was asked for"; else pass "no administrator's password is asked for"; fi
expect_equal "the installed copy is as it was" "$UF_BUILD_VERSION" "$(uf_version_of "$UF_DEST")"
expect_equal "and Applications holds nothing else" "snapit.app" "$(ls -A "$UF_APPS")"
[[ ! -e "$UF_STAGING" ]] && pass "no staging folder was made" || fail "a staging folder was made"
rm -f "$RUN_ROOT/browser-links"
expect_equal "Release Page runs there too" "ok" "$(send_slow "$EDITOR_SOCK" "update-press release-page")"
expect_equal "and opens the release page of the tag" "$UF_PAGE" "$(cat "$RUN_ROOT/browser-links" 2>/dev/null)"
rm -f "$RUN_ROOT/browser-links"
send "$APP_SOCK" install-reset >/dev/null
rm -rf "$UF_ROOT/Volumes"

# 9. A folder snapit cannot write to is the same: the copy is where it is, the folder is read-only.
send "$APP_SOCK" "install-pretend-bundle $UF_DEST" >/dev/null
chmod 555 "$UF_APPS"
UF_REQUESTS="$(uf_requests)"
uf_check
expect_equal "from a read-only folder the window cannot install either" "cannot-install" "$(uf_val state)"
expect_equal "it says to move snapit to Applications" "$UF_MOVE_LINE" "$(uf_val notice)"
expect_equal "and offers Close and Release Page, no Update and Relaunch" "close release-page " "$(uf_buttons)"
expect_contains "the menu bar app refuses an Update there too" "error not-here" "$(send "$APP_SOCK" "install-update $UF_VERSION")"
expect_equal "only the check was requested" "$((UF_REQUESTS + 1))" "$(uf_requests)"
expect_equal "the menu bar app has started nothing" "" "$(pgrep -P "$APP_PID" | tr '\n' ' ')"
if pgrep -f security_authtrampoline >/dev/null; then fail "an administrator's password was asked for"; else pass "no administrator's password is asked for"; fi
chmod 755 "$UF_APPS"
expect_equal "the installed copy is as it was" "$UF_BUILD_VERSION" "$(uf_version_of "$UF_DEST")"
expect_equal "and Applications holds nothing else" "snapit.app" "$(ls -A "$UF_APPS")"
[[ ! -e "$UF_STAGING" ]] && pass "no staging folder was made" || fail "a staging folder was made"

# Writable again, the next check offers Update and Relaunch again.
uf_check
expect_equal "once the folder can be written to, the window announces the release" "newer" "$(uf_val state)"
expect_equal "and offers Update and Relaunch again" "close release-page update " "$(uf_buttons)"
expect_equal "with no line of its own" "" "$(uf_val notice)"

# 10. After all of it: no request outside the Updates' own, no internet socket, memory back.
expect_no_internet "the menu bar app" "$APP_PID"
expect_no_internet "the Editor helper" "$(helper_pid)"
send_slow "$EDITOR_SOCK" "update-press close" >/dev/null
wait_until 10 no_helper
expect_memory_returns "the menu bar app is back at its baseline after the failed Updates" "$APP_PID" "$UF_BASELINE_MB"
expect_not_spinning "the menu bar app" "$APP_PID" 3

# Put the fixtures back for the flows after this one.
send "$APP_SOCK" install-reset >/dev/null
send "$APP_SOCK" "update-script download ok" >/dev/null
send "$APP_SOCK" "update-script offline" >/dev/null
"$LSREGISTER" -u "$UF_DEST" 2>/dev/null
unregister_fixture_apps
chmod -R u+w "$UF_APPS" "$UF_ROOT/Volumes" 2>/dev/null
rm -rf "$UF_APPS" "$UF_ROOT/Volumes" "$UF_ASSETS" "$UF_BUILT" "$UF_STAGING"
rm -f "$RUN_ROOT/browser-links"
