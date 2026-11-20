# Flow: the User Guide. The menu's User Guide item opens one window in the Editor helper, and so
# does the link on Onboarding's Done step; asking again brings the same window forward. The guide is
# bundled (read from the helper's bundle, no network) and drawn natively: its section list covers a
# checklist of the spec's flows (scripts/user-guide-checklist.txt), every anchor resolves, a link to
# another section navigates in the window, a link to GitHub opens through the fake browser edge, and
# any other link is dropped. Closing the guide quits the helper (unless another window is open), and
# the menu bar app, which never hosts the guide, stays at its baseline and idle. Sourced by
# scripts/check-run.sh.
# shellcheck shell=bash

ugfacts() { send "$EDITOR_SOCK" user-guide-facts; }
# ugv <key>: one value of `user-guide-facts`.
ugv() { ugfacts | sed -n "s/^$1=//p" | head -1; }
ug_visible() { [[ "$(ugv window)" == visible ]]; }
ug_no_helper() { [[ -z "$(helper_pid)" ]]; }
ug_onscreen_is() { [[ "$(onscreen_windows "$1")" == "$2" ]]; }
ug_section_is() { [[ "$(ugv section)" == "$1" ]]; }
ug_links() { cat "$RUN_ROOT/browser-links" 2>/dev/null; }
ug_buttons() { ugfacts | sed -n 's/^button //p' | awk -F'|' '{ print $1 }' | tr '\n' ' '; }

# 0. Nothing is running for the guide, and nothing of it is in the menu bar app.
wait_until 10 ug_no_helper
expect_equal "no helper process runs before the guide is asked for" "" "$(helper_pid)"
sleep 1
UG_BASELINE_MB="$(footprint_mb "$APP_PID")"
rm -f "$RUN_ROOT/browser-links"

# 1. The guide's source: unique anchors, every in-window link resolves, the checklist is covered.
if "$ROOT_DIR/scripts/check-user-guide.sh" >"$RUN_ROOT/user-guide-check.log" 2>&1; then
  pass "the guide's source covers the checklist and every anchor resolves ($(cat "$RUN_ROOT/user-guide-check.log"))"
else
  fail "the guide's source fails scripts/check-user-guide.sh: $(tr '\n' ' ' <"$RUN_ROOT/user-guide-check.log")"
fi

# 2. The menu: User Guide sits between Settings… and Check for Updates…, with no key.
expect_in_order "the menu offers Settings…, User Guide, Check for Updates… and Quit snapit, in that order" \
  "$(send "$APP_SOCK" menu-titles)" "Settings…" "User Guide" "Check for Updates…" "Quit snapit"
expect_equal "User Guide has no shortcut" "none" "$(send "$APP_SOCK" "menu-shortcut user-guide")"

# 3. The first click starts the helper and opens one window with a Dock icon.
expect_equal "User Guide runs" "ok" "$(send_slow "$APP_SOCK" "menu-click user-guide")"
if wait_until 10 ug_visible; then pass "the User Guide window opens"; else fail "the User Guide window did not open"; fi
UG_PID="$(helper_pid)"
UG_FACTS="$(ugfacts)"
expect_contains "the window is called User Guide" "title=User Guide" "$UG_FACTS"
expect_contains "the helper is a regular app while the guide is open" "activation=regular" "$UG_FACTS"
if wait_until 10 is_foreground "$UG_PID"; then pass "a Dock icon shows while the guide is open"; else fail "the helper has no Dock icon"; fi
if wait_until 10 has_onscreen_window "$UG_PID"; then pass "the guide is on screen (the window server lists it)"; else fail "no guide window on screen"; fi
expect_equal "the guide is one window" "1" "$(onscreen_windows "$UG_PID")"
expect_equal "the menu bar app has no window of its own" "0" "$(onscreen_windows "$APP_PID")"
expect_equal "the guide starts on its first section, the overview" "overview" "$(ugv section)"
expect_no_internet "the Editor helper with the User Guide open" "$UG_PID"
expect_no_internet "the menu bar app with the User Guide open" "$APP_PID"

# 4. A second request brings the same window forward: same process, still one window.
expect_equal "User Guide again runs" "ok" "$(send_slow "$APP_SOCK" "menu-click user-guide")"
expect_equal "and show-user-guide answers too" "ok" "$(send_slow "$EDITOR_SOCK" "show-user-guide")"
expect_equal "the same helper serves it" "$UG_PID" "$(helper_pid)"
expect_equal "there is still one guide window" "1" "$(onscreen_windows "$UG_PID")"

# 5. The checklist: the sections of the guide the helper loaded cover every flow of the spec.
UG_FACTS="$(ugfacts)"
UG_SECTIONS="$(printf '%s\n' "$UG_FACTS" | sed -n 's/^section [^=|]*|\([^|]*\)|.*/\1/p')"
UG_COUNT="$(printf '%s\n' "$UG_SECTIONS" | grep -c .)"
expect_equal "the helper counts the sections it lists" "$UG_COUNT" "$(ugv sections)"
expect_equal "no two sections share an anchor" "" "$(ugv duplicate-ids)"
expect_equal "every link in the guide resolves to a section or to GitHub" "" "$(ugv broken-links)"
expect_contains "the guide links to GitHub" "https://github.com/k-electron/snapit" "$(ugv external-links)"
if printf '%s\n' "$UG_FACTS" | grep '^section ' | awk -F'|' '$3 == "" || $1 == "section " { bad = 1 } END { exit bad }'; then
  pass "every section has a title and a group"
else
  fail "a section has no title or no group"
fi
while IFS='|' read -r id terms; do
  [[ -z "$id" || "$id" == \#* ]] && continue
  if ! grep -qx "$id" <<<"$UG_SECTIONS"; then fail "the checklist wants a section #$id and the loaded guide has none"; continue; fi
  text="$(send "$EDITOR_SOCK" "user-guide-text $id")"
  missing=""
  IFS=';' read -ra wanted <<<"$terms"
  for term in "${wanted[@]}"; do
    [[ "$text" == *"$term"* ]] || missing+="\"$term\" "
  done
  if [[ -z "$missing" ]]; then pass "the guide covers #$id"; else fail "the section #$id does not mention $missing"; fi
done <"$ROOT_DIR/scripts/user-guide-checklist.txt"

# 6. Navigation: a section from the sidebar, a link to another section, a link that goes nowhere.
expect_equal "choosing a section in the sidebar shows it" "ok" "$(send "$EDITOR_SOCK" "user-guide-select install")"
expect_equal "the page is that section" "install" "$(ugv section)"
expect_equal "its title is on the page" "Install and Open Anyway" "$(ugv section-title)"
expect_equal "a link to another section navigates in the window" "section screen-recording" "$(send "$EDITOR_SOCK" "user-guide-link %23screen-recording")"
expect_equal "the page is now Screen Recording" "screen-recording" "$(ugv section)"
expect_equal "a link to a section that is not there goes nowhere" "refused #no-such-section" "$(send "$EDITOR_SOCK" "user-guide-link %23no-such-section")"
expect_equal "and the page stays" "screen-recording" "$(ugv section)"
expect_equal "choosing a section that is not there is refused" "error no section no-such-section" "$(send "$EDITOR_SOCK" "user-guide-select no-such-section")"
expect_equal "no link so far reached the browser" "" "$(ug_links)"
send "$EDITOR_SOCK" "user-guide-select overview" >/dev/null
expect_equal "the first section has a Next button and no Previous" "next " "$(ug_buttons)"
expect_contains "Next has a tooltip" "button next|Next|Go to the next section" "$(ugfacts)"
send "$EDITOR_SOCK" "user-guide-select screen-recording" >/dev/null
expect_equal "a middle section has both" "previous next " "$(ug_buttons)"
expect_contains "Previous has a tooltip" "button previous|Previous|Go to the previous section" "$(ugfacts)"
expect_equal "Next runs" "ok" "$(send "$EDITOR_SOCK" "user-guide-press next")"
expect_equal "it shows the section after" "screen-recording-notices" "$(ugv section)"
expect_equal "Previous runs" "ok" "$(send "$EDITOR_SOCK" "user-guide-press previous")"
expect_equal "it shows the section before" "screen-recording" "$(ugv section)"
LAST_ID="$(printf '%s\n' "$UG_SECTIONS" | tail -1)"
send "$EDITOR_SOCK" "user-guide-select $LAST_ID" >/dev/null
expect_equal "the last section has a Previous button and no Next" "previous " "$(ug_buttons)"
expect_equal "pressing Next there is refused" "error no such button now: previous|next" "$(send "$EDITOR_SOCK" "user-guide-press next")"

# 7. Search: the sidebar lists the sections that hold every word, in any case.
send "$EDITOR_SOCK" "user-guide-select overview" >/dev/null
expect_equal "searching runs" "ok" "$(send "$EDITOR_SOCK" "user-guide-search eyedropper")"
VISIBLE="$(ugv visible)"
expect_contains "a search for Eyedropper finds the Annotation color section" "annotation-color" "$VISIBLE"
expect_contains "and the Color picker section, which tells it apart" "color-picker" "$VISIBLE"
if [[ ",$VISIBLE," == *",install,"* ]]; then fail "the search kept a section that does not mention it"; else pass "the search drops sections that do not mention it"; fi
expect_equal "the page moves to a result" "1" "$([[ ",$VISIBLE," == *",$(ugv section),"* ]] && echo 1)"
expect_equal "the search words are remembered" "eyedropper" "$(ugv query)"
send "$EDITOR_SOCK" "user-guide-search %20OPEN%20anyway%20" >/dev/null
expect_contains "a search ignores case and surrounding spaces" "install" "$(ugv visible)"
send "$EDITOR_SOCK" "user-guide-search zzzzqqqq" >/dev/null
expect_equal "a search with no match lists nothing" "" "$(ugv visible)"
send "$EDITOR_SOCK" "user-guide-search" >/dev/null
expect_equal "clearing the search lists every section" "$UG_COUNT" "$(ugv visible | tr ',' '\n' | grep -c .)"

# 8. Links: GitHub through the browser edge, only when followed; everything else is dropped.
GITHUB="https://github.com/k-electron/snapit/releases"
send "$EDITOR_SOCK" "user-guide-select overview" >/dev/null
expect_equal "a link to GitHub opens in the browser" "browser $GITHUB" "$(send "$EDITOR_SOCK" "user-guide-link $(printf '%s' "$GITHUB" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge')")"
expect_equal "the browser edge got exactly that link" "$GITHUB" "$(ug_links)"
expect_equal "and the guide stayed where it was" "overview" "$(ugv section)"
for odd in "http://github.com/k-electron/snapit" "https://evil.example/snapit" "https://github.com.evil.example/x" \
  "file:///etc/passwd" "javascript:alert(1)" "x-apple.systempreferences:com.apple.preference.security" "mailto:someone@example.com"; do
  reply="$(send "$EDITOR_SOCK" "user-guide-link $(printf '%s' "$odd" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge')")"
  expect_equal "the link $odd is dropped" "refused $odd" "$reply"
done
expect_equal "no dropped link reached the browser edge" "$GITHUB" "$(ug_links)"

# 9. The page draws, and only while it is on screen it costs anything: idle CPU with the guide open.
expect_equal "the window renders to a PNG" "ok" "$(send_slow "$EDITOR_SOCK" "user-guide-snapshot $RUN_ROOT/user-guide.png")"
if [[ -s "$RUN_ROOT/user-guide.png" ]]; then pass "the rendered PNG has pixels"; else fail "the rendered PNG is empty"; fi
assert_idle_cpu "the Editor helper with the User Guide open" "$UG_PID" 5
expect_no_internet "the Editor helper after following links" "$UG_PID"

# 10. Closing the only window quits the helper, and the menu bar app is where it was.
send_slow "$EDITOR_SOCK" user-guide-close >/dev/null
if wait_until 10 ug_no_helper; then pass "closing the guide, the only window, quits the helper"; else fail "the helper outlived the User Guide"; fi
sleep 1
UG_AFTER_MB="$(footprint_mb "$APP_PID")"
if awk -v a="$UG_AFTER_MB" -v b="$UG_BASELINE_MB" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app is at its baseline after the guide (${UG_BASELINE_MB} MB before, ${UG_AFTER_MB} MB after)"
else
  fail "the menu bar app grew from ${UG_BASELINE_MB} MB to ${UG_AFTER_MB} MB across the guide"
fi
assert_idle_cpu "menu bar app after the User Guide" "$APP_PID" 5

# 11. Opening and closing it again and again leaves the menu bar app at baseline too.
for _ in 1 2 3 4 5 6; do
  send_slow "$APP_SOCK" "menu-click user-guide" >/dev/null
  wait_until 10 ug_visible
  send_slow "$EDITOR_SOCK" user-guide-close >/dev/null
  wait_until 10 ug_no_helper
done
sleep 1
UG_CYCLES_MB="$(footprint_mb "$APP_PID")"
if awk -v a="$UG_CYCLES_MB" -v b="$UG_BASELINE_MB" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app is at its baseline after six cycles (${UG_BASELINE_MB} MB before, ${UG_CYCLES_MB} MB after)"
else
  fail "the menu bar app grew from ${UG_BASELINE_MB} MB to ${UG_CYCLES_MB} MB over six guide cycles"
fi
assert_idle_cpu "menu bar app after six User Guide cycles" "$APP_PID" 5

# 12. Onboarding's Done step opens the guide from the helper itself, once; closing the guide leaves
#     Onboarding (the helper stays), closing Onboarding then ends the helper.
send "$APP_SOCK" "defaults-set onboardingStep openAtLogin" >/dev/null
send_slow "$APP_SOCK" "press-shortcut capture-screen" >/dev/null
ug_onb_visible() { [[ "$(send "$EDITOR_SOCK" onboarding-facts | sed -n 's/^window=//p')" == visible ]]; }
if wait_until 15 ug_onb_visible; then pass "Onboarding opens at its stored step"; else fail "Onboarding did not open"; fi
ONB_PID="$(helper_pid)"
send_slow "$EDITOR_SOCK" "onboarding-press next" >/dev/null
expect_contains "Onboarding reaches Done" "step=done" "$(send "$EDITOR_SOCK" onboarding-facts)"
expect_contains "the User Guide link shows, set when the helper launched, before any guide window opened" "user-guide=available" "$(send "$EDITOR_SOCK" onboarding-facts)"
expect_equal "there is no guide window yet" "window=none" "$(ugfacts | head -1)"
expect_equal "the link runs" "ok" "$(send_slow "$EDITOR_SOCK" "onboarding-press user-guide")"
if wait_until 10 ug_visible; then pass "the Done step's link opens the User Guide"; else fail "the Done step's link did not open the guide"; fi
expect_equal "in the helper that shows Onboarding" "$ONB_PID" "$(helper_pid)"
expect_equal "pressing it again brings the same window forward" "ok" "$(send_slow "$EDITOR_SOCK" "onboarding-press user-guide")"
expect_equal "Onboarding and the guide are two windows" "2" "$(onscreen_windows "$ONB_PID")"
send_slow "$EDITOR_SOCK" user-guide-close >/dev/null
wait_until 10 ug_onscreen_is "$ONB_PID" 1
expect_equal "closing the guide leaves Onboarding open" "1" "$(onscreen_windows "$ONB_PID")"
expect_equal "and the helper running" "$ONB_PID" "$(helper_pid)"
send_slow "$EDITOR_SOCK" onboarding-close >/dev/null
if wait_until 10 ug_no_helper; then pass "closing the last window quits the helper"; else fail "the helper outlived its last window"; fi
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
assert_idle_cpu "menu bar app after Onboarding opened the guide" "$APP_PID" 3
rm -f "$RUN_ROOT/browser-links"
