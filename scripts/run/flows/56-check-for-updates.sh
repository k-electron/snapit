# Flow: Check for Updates. Choosing Check for Updates… in the menu, or pressing the button in
# Settings › About, opens one window in the Editor helper and sends one request, made by the menu
# bar app, to GitHub's latest-release endpoint. A run never goes online: the HTTP edge is a
# fixture that answers from a script and logs each request it is asked to send. The flow checks
# that nothing is requested until a click, the version comparison (a table through a command),
# every kind of reply (a newer, the same and an older version, garbage, a tag that is not
# X.Y.Z, a pre-release, offline, a timeout, a rate limit), what the window says (the version,
# the release notes drawn from Markdown, the Open Anyway and Screen Recording reminder), what
# Download opens (through the browser edge, never a real browser), that a click while a check
# runs sends no second request, and that the menu bar app is back at its baseline and idle.
# Sourced by scripts/check-run.sh.
# shellcheck shell=bash

# uenc <text>: the text as one command argument (percent-encoded, as SocketRequest sends it).
uenc() { printf '%s' "$1" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge'; }
ufacts() { send "$EDITOR_SOCK" update-facts; }
# uval <key>: one value of `update-facts` (`notes` is percent-encoded).
uval() { ufacts | sed -n "s/^$1=//p" | head -1; }
ublocks() { ufacts | sed -n 's/^notes-block //p'; }
ubuttons() { ufacts | sed -n 's/^button //p' | awk -F'|' '{ print $1 }' | tr '\n' ' '; }
update_settled() { local state; state="$(uval state)"; [[ -n "$state" && "$state" != checking ]]; }
update_requests() { send "$APP_SOCK" update-requests; }
requests_are() { [[ "$(update_requests)" == "$1" ]]; }
# expect_no_internet <label> <pid>: the process has no internet (TCP or UDP) socket open. The fixture
# endpoint opens none, so neither process may ever have one in a run, whatever API would open it.
expect_no_internet() {
  local sockets
  sockets="$(lsof -nP -a -i -p "$2" 2>/dev/null)"
  if [[ -z "$sockets" ]]; then pass "$1 has no internet socket open"; else fail "$1 has an internet socket open: ${sockets//$'\n'/ | }"; fi
}
onscreen_is() { [[ "$(onscreen_windows "$1")" == "$2" ]]; }
u_no_helper() { [[ -z "$(helper_pid)" ]]; }
# uscript release <tag> <html_url> <notes> [draft|prerelease]: what GitHub answers from now on.
uscript_release() { send "$APP_SOCK" "update-script release $(uenc "$1") $(uenc "$2") $(uenc "$3") ${4:-}" >/dev/null; }
# uscript_raw <status> [<body>]
uscript_raw() { send "$APP_SOCK" "update-script raw $1 $(uenc "${2:-}")" >/dev/null; }
# ucheck: Check for Updates… from the menu, then wait for the answer.
ucheck() {
  send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
  wait_until 10 update_settled
}
# expect_one_line <description> <headline fragment>: the window answers with that one line and a Close button only.
expect_one_line() {
  expect_equal "$1: the answer is a single line" "unreachable" "$(uval state)"
  expect_contains "$1: it says so" "$2" "$(uval headline)"
  expect_equal "$1: the window offers Close only" "close " "$(ubuttons)"
  expect_equal "$1: there are no release notes" "" "$(uval notes)"
}

UPDATE_URL="https://github.com/k-electron/snapit/releases/tag/v2.6.0"
UPDATE_NOTES=$'## What\'s new\n- Faster **Area** Capture\n- Fixed `crash` on [Settings](https://github.com/k-electron/snapit)\n\nThanks for using snapit!'
BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
sleep 1

# 0. Nothing has asked GitHub for anything: no check at launch, none in the background, none from
#    the flows before this one (the app has been running for the whole run).
expect_equal "no request has been sent since snapit started" "0" "$(update_requests)"
if [[ ! -e "$RUN_ROOT/update-requests" ]]; then pass "no request is logged"; else fail "a request was logged before any click"; fi
expect_equal "the menu bar app has no window of its own" "0" "$(onscreen_windows "$APP_PID")"
expect_no_internet "the menu bar app at rest" "$APP_PID"

# 1. The version comparison: three integers, compared number by number.
compare() { send "$APP_SOCK" "update-compare $(uenc "$1") $(uenc "$2")"; }
while read -r a b expected; do
  expect_equal "$a against $b is ${expected//_/ }" "${expected//_/ }" "$(compare "$a" "$b")"
done <<'TABLE'
0.10.0 0.9.0 newer
0.9.0 0.10.0 older
0.9.9 0.10.0 older
1.2.3 1.2.3 same
v1.2.3 1.2.3 same
V1.2.3 1.2.3 same
1.2.3 v1.2.3 same
1.2.4 1.2.3 newer
1.3.0 1.2.9 newer
1.2.3 1.3.0 older
2.0.0 1.99.99 newer
10.0.0 9.9.9 newer
1.10.0 1.9.9 newer
1.9.9 1.10.0 older
0.0.0 0.0.0 same
0.0.1 0.0.0 newer
01.2.3 1.2.3 same
1.2 1.2.3 invalid_a
1.2.3 1.2 invalid_b
1.2.3.4 1.2.3 invalid_a
1.2.3-beta 1.2.3 invalid_a
1.2.3 1.2.3-beta.1 invalid_b
v1.2.3-rc1 1.2.3 invalid_a
+1.2.3 1.2.3 invalid_a
1.2.3 -1.2.3 invalid_b
1.2.x 1.2.3 invalid_a
1..3 1.2.3 invalid_a
.. 1.2.3 invalid_a
v 1.2.3 invalid_a
vv1.2.3 1.2.3 invalid_a
99999999999999999999.0.0 1.2.3 invalid_a
１.２.３ 1.2.3 invalid_a
latest 1.2.3 invalid_a
TABLE
expect_equal "a blank is not a version" "invalid a" "$(send "$APP_SOCK" "update-compare %20 1.2.3")"
expect_equal "an invalid version is reported for a" "invalid a" "$(compare 1.2 1.2.3)"
expect_equal "an invalid version is reported for b" "invalid b" "$(compare 1.2.3 1.2)"

# 2. The menu: Check for Updates… sits after Settings… (and the User Guide, once the menu has one)
#    and before Quit snapit, with no key.
MENU_TITLES="$(send "$APP_SOCK" menu-titles)"
MENU_ORDER=("Settings…")
[[ "$MENU_TITLES" == *"User Guide"* ]] && MENU_ORDER+=("User Guide")
expect_in_order "the menu offers Settings…, User Guide (when there is one), Check for Updates… and Quit snapit, in that order" \
  "$MENU_TITLES" "${MENU_ORDER[@]}" "Check for Updates…" "Quit snapit"
expect_equal "Check for Updates… has no shortcut" "none" "$(send "$APP_SOCK" "menu-shortcut check-for-updates")"
wait_until 10 u_no_helper
expect_equal "no helper runs before the first click" "" "$(helper_pid)"
sleep 1
UPDATE_BASELINE_MB="$(footprint_mb "$APP_PID")"

# 3. The first click starts the helper, opens the window and sends one request. Unscripted, the
#    fixture answers as if offline.
send "$APP_SOCK" "update-installed-version 2.5.7" >/dev/null
expect_equal "Check for Updates… runs" "ok" "$(send_slow "$APP_SOCK" "menu-click check-for-updates")"
if wait_until 10 update_settled; then pass "the window shows an answer"; else fail "the window never left Checking"; fi
UPDATE_PID="$(helper_pid)"
FACTS="$(ufacts)"
expect_no_internet "the Editor helper with the update window open" "$UPDATE_PID"
expect_no_internet "the menu bar app after a check" "$APP_PID"
expect_contains "the window is visible" "window=visible" "$FACTS"
expect_contains "the window is called Check for Updates" "title=Check for Updates" "$FACTS"
expect_contains "the helper is a regular app while the window is open" "activation=regular" "$FACTS"
if wait_until 10 is_foreground "$UPDATE_PID"; then pass "a Dock icon shows while the update window is open"; else fail "the helper has no Dock icon"; fi
if wait_until 10 has_onscreen_window "$UPDATE_PID"; then pass "the update window is on screen (the window server lists it)"; else fail "no update window on screen"; fi
expect_equal "the window is one window" "1" "$(onscreen_windows "$UPDATE_PID")"
expect_equal "the menu bar app still has no window" "0" "$(onscreen_windows "$APP_PID")"
expect_equal "one click sent one request" "1" "$(update_requests)"
expect_one_line "offline" "Couldn't reach GitHub"
BUTTONS_FACTS="$(printf '%s\n' "$FACTS" | grep '^button ')"
expect_contains "Close has a tooltip" "button close|Close|Close this window" "$BUTTONS_FACTS"

# 4. Every kind of reply, through the same window (a second request each).
uscript_release v2.5.8 "$UPDATE_URL" "$UPDATE_NOTES"
ucheck
expect_equal "a newer patch version is shown as newer" "newer" "$(uval state)"
expect_equal "the headline names the new version" "snapit 2.5.8 is available." "$(uval headline)"
expect_equal "the window says which version is installed" "You have snapit 2.5.7." "$(uval detail)"
expect_equal "the window has the release notes, as GitHub sent them" "$(uenc "$UPDATE_NOTES")" "$(uval notes)"
expect_in_order "the notes are drawn as a heading, bullets with their inline Markdown applied, and a paragraph" \
  "$(ublocks)" "heading|What's new" "bullet|Faster Area Capture" "bullet|Fixed crash on Settings" "paragraph|Thanks for using snapit!"
expect_equal "the window offers Close and Download" "close download " "$(ubuttons)"
expect_contains "Download has a tooltip" "button download|Download|Open this release's page on GitHub in your browser" "$(ufacts)"
expect_equal "Download points at the release page of that tag, built from the tag" \
  "https://github.com/k-electron/snapit/releases/tag/v2.5.8" "$(uval url)"
REMINDER="$(uval reminder)"
expect_contains "the window reminds users that Open Anyway is needed again" "Open Anyway" "$REMINDER"
expect_contains "and that Screen Recording is needed again" "Screen Recording" "$REMINDER"
expect_contains "after updating" "After updating" "$REMINDER"
if wait_until 10 has_onscreen_window "$UPDATE_PID"; then pass "the window with notes is on screen"; else fail "no window with notes on screen"; fi
expect_equal "the window can be rendered to a PNG" "ok" "$(send_slow "$EDITOR_SOCK" "update-snapshot $RUN_ROOT/update-window.png")"
if [[ -s "$RUN_ROOT/update-window.png" ]]; then pass "the rendered PNG has pixels"; else fail "the rendered PNG is empty"; fi

uscript_release v2.10.0 "$UPDATE_URL" "Ten is more than nine."
send "$APP_SOCK" "update-installed-version 2.9.0" >/dev/null
ucheck
expect_equal "2.10.0 is newer than 2.9.0" "snapit 2.10.0 is available." "$(uval headline)"
send "$APP_SOCK" "update-installed-version 2.5.7" >/dev/null

uscript_release v2.5.7 "$UPDATE_URL" "Same."
ucheck
expect_equal "the same version is up to date" "up-to-date" "$(uval state)"
expect_equal "and says so in one line" "snapit 2.5.7 is up to date." "$(uval headline)"
expect_equal "the window offers Close only" "close " "$(ubuttons)"
expect_equal "an up-to-date answer carries no notes" "" "$(uval notes)"
expect_equal "an up-to-date answer carries no reminder" "" "$(uval reminder)"
uscript_release v2.5.6 "$UPDATE_URL" "Older."
ucheck
expect_equal "an older release is up to date too" "snapit 2.5.7 is up to date." "$(uval headline)"
uscript_release 2.6.0 "$UPDATE_URL" "No leading v."
ucheck
expect_equal "a tag with no leading v is tolerated" "snapit 2.6.0 is available." "$(uval headline)"
uscript_release v2.6.0 "$UPDATE_URL" $'one\r\ntwo\r\n'
ucheck
expect_equal "Windows line endings in the notes are normalised" "$(uenc $'one\ntwo')" "$(uval notes)"

# What GitHub says is not an update.
uscript_release v2.6.0-beta.1 "$UPDATE_URL" "A pre-release tag."
ucheck
expect_one_line "a pre-release tag (v2.6.0-beta.1)" "Couldn't read GitHub's answer"
uscript_release v2.6 "$UPDATE_URL" "Two integers."
ucheck
expect_one_line "a tag of two integers" "Couldn't read GitHub's answer"
uscript_release v2.6.0.1 "$UPDATE_URL" "Four integers."
ucheck
expect_one_line "a tag of four integers" "Couldn't read GitHub's answer"
uscript_release latest "$UPDATE_URL" "Not a version."
ucheck
expect_one_line "a tag that is not a version" "Couldn't read GitHub's answer"
uscript_release v9.9.9 "$UPDATE_URL" "Flagged pre-release." prerelease
ucheck
expect_one_line "a release flagged as a pre-release" "no release of snapit"
uscript_release v9.9.9 "$UPDATE_URL" "Flagged draft." draft
ucheck
expect_one_line "a release flagged as a draft" "no release of snapit"
uscript_raw 200 "this is not JSON at all"
ucheck
expect_one_line "garbage" "Couldn't read GitHub's answer"
uscript_raw 200 ""
ucheck
expect_one_line "an empty body" "Couldn't read GitHub's answer"
uscript_raw 200 '{"name":"no tag"}'
ucheck
expect_one_line "JSON without a tag_name" "Couldn't read GitHub's answer"
uscript_raw 200 '{"tag_name": 5}'
ucheck
expect_one_line "a tag_name that is not text" "Couldn't read GitHub's answer"
uscript_raw 200 '[1,2,3]'
ucheck
expect_one_line "JSON that is not a release" "Couldn't read GitHub's answer"
uscript_raw 500 '{"tag_name":"v9.9.9"}'
ucheck
expect_one_line "a server error, whatever the body says" "Couldn't read GitHub's answer"
uscript_raw 403 '{"message":"API rate limit exceeded"}'
ucheck
expect_one_line "a rate limit (403)" "limiting requests"
uscript_raw 429 ""
ucheck
expect_one_line "a rate limit (429)" "limiting requests"
uscript_raw 404 '{"message":"Not Found"}'
ucheck
expect_one_line "no release published (404)" "no release of snapit"
send "$APP_SOCK" "update-script offline" >/dev/null
ucheck
expect_one_line "offline" "Couldn't reach GitHub"
send "$APP_SOCK" "update-script timeout" >/dev/null
ucheck
expect_one_line "a timeout" "didn't answer in time"
send "$APP_SOCK" "update-installed-version 2.5" >/dev/null
uscript_release v2.6.0 "$UPDATE_URL" "Own version."
ucheck
expect_one_line "a bundle version that is not three integers" "Couldn't read the version of this snapit"
send "$APP_SOCK" "update-installed-version reset" >/dev/null
uscript_release "v$BUNDLE_VERSION" "$UPDATE_URL" "The bundle's own version."
ucheck
expect_equal "the bundle's own version is read from its Info.plist" "snapit $BUNDLE_VERSION is up to date." "$(uval headline)"
uscript_release "v$((${BUNDLE_VERSION%%.*} + 1)).0.0" "$UPDATE_URL" "A new major version."
ucheck
expect_equal "a newer major version than the bundle's is newer" "You have snapit $BUNDLE_VERSION." "$(uval detail)"
send "$APP_SOCK" "update-installed-version 2.5.7" >/dev/null

# The Download button opens the release page of the tag, built from the tag. The link in GitHub's
# reply is never used, whatever it looks like: a path that climbs out of the repository, an
# encoded one, a user name, a port, another host, another scheme.
FALLBACK_URL="https://github.com/k-electron/snapit/releases/tag/v2.6.0"
for odd in "$UPDATE_URL" "https://evil.example/k-electron/snapit/x" "file:///etc/passwd" "javascript:alert(1)" \
  "http://github.com/k-electron/snapit/releases/tag/v2.6.0" "https://github.com/someone-else/repo/releases/tag/v2.6.0" \
  "https://github.com/k-electron/snapit/../../evil/snapit/releases" \
  "https://github.com/k-electron/snapit/%2e%2e/%2e%2e/evil/snapit/releases" \
  "https://github.com/k-electron/snapit/%2E%2E%2F..%2Fevil/releases" \
  "https://x@github.com/k-electron/snapit/releases/tag/v2.6.0" \
  "https://github.com:8443/k-electron/snapit/releases/tag/v2.6.0" \
  "https://github.com.evil.example/k-electron/snapit/releases"; do
  uscript_release v2.6.0 "$odd" "Odd link."
  ucheck
  expect_equal "a release link of $odd is not used: the release page of the tag is" "$FALLBACK_URL" "$(uval url)"
done
uscript_release " v2.6.0 " "$UPDATE_URL" "A tag with spaces around it."
ucheck
expect_equal "a tag with spaces around it gives the same release page, not an encoded one" "$FALLBACK_URL" "$(uval url)"
uscript_release V2.6.0 "$UPDATE_URL" "A capital V."
ucheck
expect_equal "the release page keeps the tag as GitHub wrote it" "https://github.com/k-electron/snapit/releases/tag/V2.6.0" "$(uval url)"

# Release notes: an image is its alternative text (nothing is fetched), a link's text shows, and
# notes of any length are cut by lines and by bytes.
uscript_release v2.6.0 "$UPDATE_URL" $'![screenshot of the Editor](https://evil.example/pixel.png)\n- [a link](https://github.com/k-electron/snapit) and ![icon](https://evil.example/i.png)'
ucheck
expect_in_order "an image shows as its alternative text, a link as its text" \
  "$(ublocks)" "paragraph|screenshot of the Editor" "bullet|a link and icon"
LONG_LINES="$(awk 'BEGIN { for (i = 1; i <= 1000; i++) print "- item " i }')"
uscript_release v2.6.0 "$UPDATE_URL" "$LONG_LINES"
ucheck
expect_equal "long notes are cut at 300 lines" "300" "$(uval notes-blocks)"
expect_equal "and the last block is the 300th line, the cut marked" "bullet|item 300…" "$(ublocks | tail -1)"
LONG_BYTES="$(perl -CO -e 'print "\x{20AC}" x 7000')"
uscript_release v2.6.0 "$UPDATE_URL" "$LONG_BYTES"
ucheck
expect_equal "notes of 21000 bytes are cut to 20000 at a character boundary, plus the mark" "19998" "$(( $(uval notes-bytes) - 3 ))"
uscript_release v2.6.0 "$UPDATE_URL" "$UPDATE_NOTES"

# The redirect policy of the real endpoint: only within api.github.com.
redirect() { send "$APP_SOCK" "update-redirect $(uenc "$1")"; }
expect_equal "a redirect within api.github.com is followed" "follow" "$(redirect https://api.github.com/repositories/1/releases/latest)"
for target in http://api.github.com/x https://github.com/k-electron/snapit https://evil.example/x \
  https://api.github.com.evil.example/x https://api.github.com:8443/x https://user@api.github.com/x file:///etc/passwd; do
  expect_equal "a redirect to $target is refused" "refuse" "$(redirect "$target")"
done

# 5. Nothing but the requests the clicks made, each exactly what the real endpoint would send.
REQUESTS="$(update_requests)"
expect_equal "every click sent one request and nothing else did" "$REQUESTS" "$(wc -l <"$RUN_ROOT/update-requests" | tr -d ' ')"
expect_equal "every request is a GET of GitHub's latest-release endpoint for snapit's repository" "GET https://api.github.com/repos/k-electron/snapit/releases/latest" \
  "$(awk '{ print $1 " " $2 }' "$RUN_ROOT/update-requests" | sort -u)"
expect_equal "every request sets a generic User-Agent, Accept and a fixed Accept-Language (not the user's), and no other header (the HTTP client's own transport headers apart)" \
  "Accept=application/vnd.github+json Accept-Language=en User-Agent=snapit" "$(awk '{ $1 = ""; $2 = ""; $3 = ""; sub(/^ +/, ""); print }' "$RUN_ROOT/update-requests" | sort -u)"
if grep -qiE 'authorization|cookie|token|@' "$RUN_ROOT/update-requests"; then fail "a request carries credentials or personal details"; else pass "no request carries credentials or personal details"; fi
if grep -q "snapit-run\|$USER" "$RUN_ROOT/update-requests"; then fail "a request names the user or the run"; else pass "no request names the user or the run"; fi

# 6. A click while a check runs sends no second request; the window says it is checking.
uscript_release v2.6.0 "$UPDATE_URL" "$UPDATE_NOTES"
send "$APP_SOCK" "update-script hold on" >/dev/null
BEFORE_HOLD="$(update_requests)"
send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
wait_until 5 requests_are "$((BEFORE_HOLD + 1))"
expect_equal "the window says it is checking" "checking" "$(uval state)"
expect_no_internet "the menu bar app while a (fixture) check waits for its answer" "$APP_PID"
expect_equal "with Checking for updates… as its line" "Checking for updates…" "$(uval headline)"
expect_equal "and Close as its only button" "close " "$(ubuttons)"
send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
sleep 1
expect_equal "more clicks while it checks send no second request" "$((BEFORE_HOLD + 1))" "$(update_requests)"
expect_equal "the window is still checking" "checking" "$(uval state)"
send "$APP_SOCK" "update-script hold off" >/dev/null
if wait_until 10 update_settled; then pass "the answer arrives when GitHub answers"; else fail "the window never left Checking"; fi
expect_equal "and it is the newer version" "snapit 2.6.0 is available." "$(uval headline)"
expect_equal "still one request for the three clicks" "$((BEFORE_HOLD + 1))" "$(update_requests)"
send_slow "$EDITOR_SOCK" "update-press close" >/dev/null
wait_until 10 u_no_helper

# 6b. Closing the window while GitHub has not answered: the helper quits, the menu bar app survives
#     its reply having nowhere to go, and the next click joins the request still in flight.
send "$APP_SOCK" "update-script hold on" >/dev/null
BEFORE_CLOSE="$(update_requests)"
send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
wait_until 5 requests_are "$((BEFORE_CLOSE + 1))"
CLOSE_REPLY="$(send_slow "$EDITOR_SOCK" "update-press close")"
if wait_until 10 u_no_helper; then pass "closing the window during a check quits the helper"; else fail "the helper outlived the update window (close replied '$CLOSE_REPLY', pid $(helper_pid), $(ufacts | head -4 | tr '\n' ' '))"; fi
send_slow "$APP_SOCK" "menu-click check-for-updates" >/dev/null
sleep 1
expect_equal "a click after closing joins the check still running: no second request" "$((BEFORE_CLOSE + 1))" "$(update_requests)"
expect_equal "the new window says it is checking" "checking" "$(uval state)"
send "$APP_SOCK" "update-script hold off" >/dev/null
if wait_until 10 update_settled; then pass "the answer arrives in the new window"; else fail "the new window never left Checking"; fi
expect_equal "it is the newer version" "snapit 2.6.0 is available." "$(uval headline)"
expect_equal "still one request" "$((BEFORE_CLOSE + 1))" "$(update_requests)"
if kill -0 "$APP_PID" 2>/dev/null && answers "$APP_SOCK"; then pass "snapit survived the reply to a helper that had quit"; else fail "snapit died when the helper quit during a check"; fi
send_slow "$EDITOR_SOCK" "update-press close" >/dev/null
wait_until 10 u_no_helper

# 7. Settings › About has the button: it does what the menu item does.
expect_equal "Settings opens" "ok" "$(send_slow "$APP_SOCK" "menu-click settings")"
wait_until 10 answers "$EDITOR_SOCK"
SETTINGS_FACTS="$(send "$EDITOR_SOCK" settings-facts)"
expect_in_order "About shows the version, then Check for Updates…" \
  "$(printf '%s\n' "$SETTINGS_FACTS" | awk -F'|' '{ print $1 }')" "section About" "control version" "control check-for-updates"
expect_contains "the About button has a tooltip" "control check-for-updates|button|Check for Updates…|" "$SETTINGS_FACTS"
ABOUT_TOOLTIP="$(printf '%s\n' "$SETTINGS_FACTS" | grep '^control check-for-updates' | awk -F'|' '{ print $5 }')"
expect_contains "its tooltip says it is the only time snapit goes online" "only time snapit goes online" "$ABOUT_TOOLTIP"
BEFORE_ABOUT="$(update_requests)"
send "$APP_SOCK" "update-script release $(uenc v3.0.0) $(uenc "$UPDATE_URL") $(uenc "From About.")" >/dev/null
expect_equal "pressing the About button runs" "ok" "$(send_slow "$EDITOR_SOCK" "settings-press check-for-updates")"
wait_until 10 update_settled
expect_equal "it shows the answer in the update window" "snapit 3.0.0 is available." "$(uval headline)"
expect_equal "it sent one request" "$((BEFORE_ABOUT + 1))" "$(update_requests)"
UPDATE_PID="$(helper_pid)"
expect_equal "Settings and the update window are two windows of one helper" "2" "$(onscreen_windows "$UPDATE_PID")"
expect_equal "pressing the button again brings the same window forward" "ok" "$(send_slow "$EDITOR_SOCK" "settings-press check-for-updates")"
if wait_until 5 requests_are "$((BEFORE_ABOUT + 2))"; then pass "and sends a second request: a new check"; else fail "no second request after pressing again (requests: $(update_requests))"; fi
expect_equal "still two windows" "2" "$(onscreen_windows "$UPDATE_PID")"

# 8. Download opens the release page through the browser edge, and the update window closes.
rm -f "$RUN_ROOT/browser-links"
expect_equal "Download runs" "ok" "$(send_slow "$EDITOR_SOCK" "update-press download")"
expect_equal "the browser is asked to open the release page of the tag" "https://github.com/k-electron/snapit/releases/tag/v3.0.0" "$(cat "$RUN_ROOT/browser-links" 2>/dev/null)"
wait_until 10 onscreen_is "$UPDATE_PID" 1
expect_equal "the update window closed; Settings is still open" "1" "$(onscreen_windows "$UPDATE_PID")"
expect_contains "the update window has gone" "window=none" "$(ufacts)"
expect_equal "Download with no newer version does nothing" "error no update window" "$(send "$EDITOR_SOCK" "update-press download")"
send_slow "$EDITOR_SOCK" settings-close >/dev/null
if wait_until 10 gone "$UPDATE_PID"; then pass "closing the last window quits the helper"; else fail "the helper is still running"; fi

# A fallback link opens the release page of the tag: the same edge, one line per open.
send "$APP_SOCK" "update-script release $(uenc v2.6.0) $(uenc "https://evil.example/") $(uenc "Fallback.")" >/dev/null
ucheck
rm -f "$RUN_ROOT/browser-links"
send_slow "$EDITOR_SOCK" "update-press download" >/dev/null
expect_equal "a link GitHub should not send opens the release page of the tag" "$FALLBACK_URL" "$(cat "$RUN_ROOT/browser-links" 2>/dev/null)"
wait_until 10 u_no_helper
expect_equal "no helper process is left after Download" "" "$(helper_pid)"

# 9. Close and Esc.
ucheck
expect_equal "Close closes the window" "ok" "$(send_slow "$EDITOR_SOCK" "update-press close")"
if wait_until 10 u_no_helper; then pass "Close, with no other window, quits the helper"; else fail "the helper outlived the update window"; fi

# 10. At rest: no timer, no polling, the baseline memory, no more requests.
send "$APP_SOCK" "update-script offline" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  ucheck
  send_slow "$EDITOR_SOCK" "update-press close" >/dev/null
  wait_until 10 u_no_helper
done
ucheck
sleep 1
assert_idle_cpu "the helper with the update window open" "$(helper_pid)" 5
send_slow "$EDITOR_SOCK" "update-press close" >/dev/null
wait_until 10 u_no_helper
REQUESTS_AFTER="$(update_requests)"
sleep 3
expect_equal "an idle snapit sends no request" "$REQUESTS_AFTER" "$(update_requests)"
sleep 1
UPDATE_AFTER_MB="$(footprint_mb "$APP_PID")"
if awk -v a="$UPDATE_AFTER_MB" -v b="$UPDATE_BASELINE_MB" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app is at its baseline after the checks (${UPDATE_BASELINE_MB} MB before, ${UPDATE_AFTER_MB} MB after)"
else
  fail "the menu bar app grew from ${UPDATE_BASELINE_MB} MB to ${UPDATE_AFTER_MB} MB across the checks"
fi
assert_idle_cpu "menu bar app after the checks" "$APP_PID" 5
expect_no_internet "the menu bar app after every check" "$APP_PID"

# 11. Nothing else in snapit goes online: the code that can is in one file.
if "$ROOT_DIR/scripts/check-network.sh" >"$RUN_ROOT/check-network.log" 2>&1; then
  pass "the network is used by one file only (scripts/check-network.sh)"
else
  fail "network use outside GitHubReleaseEndpoint.swift: $(cat "$RUN_ROOT/check-network.log")"
fi

# Put the fixtures back for the flows after this one.
send "$APP_SOCK" "update-script offline" >/dev/null
send "$APP_SOCK" "update-script hold off" >/dev/null
send "$APP_SOCK" "update-installed-version reset" >/dev/null
rm -f "$RUN_ROOT/browser-links" "$RUN_ROOT/update-window.png"
