# Flow: the User Guide. The menu's User Guide item opens one window in the Editor helper, and so
# does the link on Onboarding's Done step; asking again brings the same window forward. The guide is
# bundled (read from the helper's bundle, no network) and drawn natively: its section list covers a
# checklist of the spec's flows (scripts/user-guide-checklist.txt), every section has the icon its
# source gives, every anchor resolves, a guide with image lines and comments (a fixture file read
# through the same parser) shows neither the images, their alternative text nor the comments, a link to
# another section navigates in the window, a link to GitHub opens through the fake browser edge, and
# any other link is dropped. Closing the guide quits the helper (unless another window is open), and
# the menu bar app, which never hosts the guide, stays at its baseline. Sourced by
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

# 1. The docs check: the guide's source has unique anchors, every in-window link resolves and the checklist is covered (and every relative link in the repo's Markdown resolves).
if "$ROOT_DIR/scripts/check-docs.sh" >"$RUN_ROOT/user-guide-check.log" 2>&1; then
  pass "the guide's source covers the checklist and every anchor resolves ($(tail -n 1 "$RUN_ROOT/user-guide-check.log"))"
else
  fail "the docs check fails (scripts/check-docs.sh): $(tr '\n' ' ' <"$RUN_ROOT/user-guide-check.log")"
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
expect_onscreen_windows "the guide is one window" "$UG_PID" "1"
expect_onscreen_windows "the menu bar app has no window of its own" "$APP_PID" "0"
expect_equal "the guide starts on its first section, the overview" "overview" "$(ugv section)"
expect_equal "no text field has the keyboard when the guide opens (a blinking caret is CPU)" "first-responder-is-text=false" "$(ugfacts | grep '^first-responder-is-text=')"
expect_no_internet "the Editor helper with the User Guide open" "$UG_PID"
expect_no_internet "the menu bar app with the User Guide open" "$APP_PID"

# 4. A second request brings the same window forward: same process, still one window.
expect_equal "User Guide again runs" "ok" "$(send_slow "$APP_SOCK" "menu-click user-guide")"
expect_equal "and show-user-guide answers too" "ok" "$(send_slow "$EDITOR_SOCK" "show-user-guide")"
expect_equal "the same helper serves it" "$UG_PID" "$(helper_pid)"
expect_onscreen_windows "there is still one guide window" "$UG_PID" "1"

# 5. The checklist: the sections of the guide the helper loaded cover every flow of the spec.
UG_FACTS="$(ugfacts)"
UG_SECTIONS="$(printf '%s\n' "$UG_FACTS" | sed -n 's/^section [^=|]*|\([^|]*\)|.*/\1/p')"
UG_COUNT="$(printf '%s\n' "$UG_SECTIONS" | grep -c .)"
expect_equal "the helper counts the sections it lists" "$UG_COUNT" "$(ugv sections)"
expect_equal "no two sections share an anchor" "" "$(ugv duplicate-ids)"
expect_equal "every link in the guide resolves to a section or to GitHub" "" "$(ugv broken-links)"
UG_SOURCE="$ROOT_DIR/docs/UserGuide.md"
expect_equal "every section has the icon its source gives" \
  "$(sed -n 's/^## <a id="\([a-z0-9-]*\)"><\/a>.* <!-- icon: \([A-Za-z0-9.]*\) -->$/\1|\2/p' "$UG_SOURCE")" \
  "$(printf '%s\n' "$UG_FACTS" | sed -n 's/^section [^|]*|\([^|]*\)|[^|]*|\(.*\)$/\1|\2/p')"
expect_equal "the loaded guide links to the same sections, in the same order, as the source's [text](#id) links" \
  "$(grep -o '](#[a-z0-9-]*)' "$UG_SOURCE" | sed 's/^](#//; s/)$//' | paste -sd, -)" "$(ugv section-links)"
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

# 5b. What the page draws for a section: its blocks by kind and text, with none of the markup that only GitHub shows.
send "$EDITOR_SOCK" "user-guide-select install" >/dev/null
UG_BLOCKS="$(ugfacts | sed -n 's/^block //p')"
expect_contains "the install section draws its steps" "numbered|1. Open the DMG." "$UG_BLOCKS"
expect_contains "and its note" "note|snapit is not notarized" "$UG_BLOCKS"
for id in $UG_SECTIONS; do
  text="$(send "$EDITOR_SOCK" "user-guide-text $id")"
  if [[ "$text" == *"<!--"* || "$text" == *"<a id"* || "$text" == *"icon:"* ]]; then fail "the section #$id draws markup that only GitHub hides"; fi
done
pass "no section draws an anchor, a comment or an icon as text"

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
for odd in "http://github.com/k-electron/snapit" "https://github.com/someone-else/x" "https://github.com:8443/k-electron/snapit" \
  "https://user@github.com/k-electron/snapit" "https://github.com/k-electron/snapit-evil" "https://evil.example/snapit" "https://github.com.evil.example/x" \
  "file:///etc/passwd" "javascript:alert(1)" "x-apple.systempreferences:com.apple.preference.security" "mailto:someone@example.com"; do
  reply="$(send "$EDITOR_SOCK" "user-guide-link $(printf '%s' "$odd" | perl -pe 's/([^A-Za-z0-9._~-])/sprintf("%%%02X", ord($1))/ge')")"
  expect_equal "the link $odd is dropped" "refused $odd" "$reply"
done
expect_equal "no dropped link reached the browser edge" "$GITHUB" "$(ug_links)"

# 9. The page draws.
expect_equal "the window renders to a PNG" "ok" "$(send_slow "$EDITOR_SOCK" "user-guide-snapshot $RUN_ROOT/user-guide.png")"
if [[ -s "$RUN_ROOT/user-guide.png" ]]; then pass "the rendered PNG has pixels"; else fail "the rendered PNG is empty"; fi
expect_no_internet "the Editor helper after following links" "$UG_PID"

# 10. Closing the only window quits the helper, and the menu bar app is where it was.
send_slow "$EDITOR_SOCK" user-guide-close >/dev/null
if wait_until 10 ug_no_helper; then pass "closing the guide, the only window, quits the helper"; else fail "the helper outlived the User Guide"; fi
expect_memory_returns "the menu bar app is at its baseline after the guide" "$APP_PID" "$UG_BASELINE_MB"

# 11. Opening and closing it again and again leaves the menu bar app at baseline too.
for _ in 1 2 3 4 5 6; do
  send_slow "$APP_SOCK" "menu-click user-guide" >/dev/null
  wait_until 10 ug_visible
  send_slow "$EDITOR_SOCK" user-guide-close >/dev/null
  wait_until 10 ug_no_helper
done
expect_memory_returns "the menu bar app is at its baseline after six cycles" "$APP_PID" "$UG_BASELINE_MB"

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
expect_onscreen_windows "Onboarding and the guide are two windows" "$ONB_PID" "2"
send_slow "$EDITOR_SOCK" user-guide-close >/dev/null
wait_until 10 ug_onscreen_is "$ONB_PID" 1
expect_onscreen_windows "closing the guide leaves Onboarding open" "$ONB_PID" "1"
expect_equal "and the helper running" "$ONB_PID" "$(helper_pid)"
# 13. A guide with image lines, as the helper parses any guide (the same parser reads the bundled one):
#     an image line is no block and leaves no alternative text, a comment leaves nothing, in any form.
cat >"$RUN_ROOT/user-guide-fixture.md" <<'FIXTURE'
# Fixture group

## <a id="fixture-shots"></a>Fixture with shots <!-- icon: camera.viewfinder -->

Before the picture. <!-- FIXTURE-INLINE-COMMENT -->

![FIXTURE-ALT-TEXT](images/user-guide/fixture.png)

[![FIXTURE-LINKED-ALT-TEXT](images/user-guide/fixture-linked.png)](https://github.com/k-electron/snapit)

<!-- slot: FIXTURE-SLOT-LINE
FIXTURE-SLOT-MORE -->

After the picture, see [the next section](#fixture-next).

- A bullet ![FIXTURE-INLINE-ALT-TEXT](images/user-guide/fixture-inline.png) with a picture inside

## <a id="fixture-next"></a>Fixture next <!-- icon: arrow.right -->

The next section.
FIXTURE
expect_equal "the helper takes a guide file from the test root" "ok" "$(send "$EDITOR_SOCK" "user-guide-fixture $RUN_ROOT/user-guide-fixture.md")"
expect_equal "and refuses one outside it" "error file must be inside the test root" "$(send "$EDITOR_SOCK" "user-guide-fixture /etc/hosts")"
expect_equal "the fixture window opens" "ok" "$(send_slow "$EDITOR_SOCK" "show-user-guide")"
if wait_until 10 ug_visible; then pass "the fixture guide's window opens"; else fail "the fixture guide's window did not open"; fi
UG_FACTS="$(ugfacts)"
expect_equal "it lists the two sections of the fixture, with their icons" \
  "section Fixture group|fixture-shots|Fixture with shots|camera.viewfinder
section Fixture group|fixture-next|Fixture next|arrow.right" "$(printf '%s\n' "$UG_FACTS" | grep '^section ')"
expect_equal "it opens on the section with the image lines" "fixture-shots" "$(ugv section)"
expect_equal "which draws two paragraphs and a bullet and no image or alternative text" \
  "block paragraph|Before the picture.
block paragraph|After the picture, see the next section.
block bullet|A bullet  with a picture inside" "$(printf '%s\n' "$UG_FACTS" | grep '^block ')"
expect_equal "an image line is no block of any kind" "" "$(printf '%s\n' "$UG_FACTS" | grep '^block ' | grep -iE 'image|FIXTURE' || true)"
text="$(send "$EDITOR_SOCK" "user-guide-text fixture-shots")"
if [[ "$text" == *FIXTURE* || "$text" == *images/* || "$text" == *"<!--"* ]]; then fail "the section's text holds an alternative text, a path or a comment: $text"; else pass "the section's text holds no alternative text, path or comment"; fi
expect_equal "its link to the next section is the only link" "fixture-next" "$(ugv section-links)"
expect_equal "every link resolves" "" "$(ugv broken-links)"
send "$EDITOR_SOCK" "user-guide-search FIXTURE-ALT-TEXT" >/dev/null
expect_equal "a search for an alternative text finds nothing" "" "$(ugv visible)"
for hidden in FIXTURE-LINKED-ALT-TEXT FIXTURE-INLINE-ALT-TEXT FIXTURE-INLINE-COMMENT FIXTURE-SLOT-LINE FIXTURE-SLOT-MORE; do
  send "$EDITOR_SOCK" "user-guide-search $hidden" >/dev/null
  expect_equal "a search for $hidden finds nothing" "" "$(ugv visible)"
done
send "$EDITOR_SOCK" "user-guide-search picture" >/dev/null
expect_equal "a search for words that are shown finds the section" "fixture-shots" "$(ugv visible)"
expect_no_internet "the Editor helper with the fixture guide open" "$ONB_PID"
send_slow "$EDITOR_SOCK" user-guide-close >/dev/null
wait_until 10 ug_onscreen_is "$ONB_PID" 1
expect_equal "the fixture is dropped" "ok" "$(send "$EDITOR_SOCK" "user-guide-fixture off")"
expect_equal "and Onboarding keeps the helper" "$ONB_PID" "$(helper_pid)"

send_slow "$EDITOR_SOCK" onboarding-close >/dev/null
if wait_until 10 ug_no_helper; then pass "closing the last window quits the helper"; else fail "the helper outlived its last window"; fi
send "$APP_SOCK" "defaults-set onboardingStep finished" >/dev/null
rm -f "$RUN_ROOT/browser-links"
