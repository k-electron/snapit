# Flow: Settings. The menu bar menu's Settings… opens one window in the Editor helper: a single
# page with General, Capturing, Editor, Shortcuts, Export and About. Every control writes its key
# inside the helper and changes what the rest of snapit does at once: Close the Editor after
# Copy keeps the Editor open, 1x changes the Export's size, the Save location redirects Saves,
# Capture on release changes the Area flow, a re-recorded Shortcut rebinds the injected Shortcut
# and the menu glyph, Open at Login goes through the fake login item (never the real one). The
# window opens once, brings itself forward on a second request, shows a Dock icon while it is the
# only window, and the helper quits when it closes, leaving the menu bar app where it was.
# Uses helpers of flows 20 (the profile checksums), 40 (the Area drag) and 45 (`check_png`).
# Sourced by scripts/check-run.sh.
# shellcheck shell=bash

SETTINGS_ELSEWHERE="$RUN_ROOT/save-elsewhere"
mkdir -p "$SETTINGS_ELSEWHERE" "$SAVE"
clear_save_folder
send "$APP_SOCK" "fixture-extra-display none" >/dev/null
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
send "$APP_SOCK" pasteboard-clear >/dev/null
# Earlier flows left their own values: start from the defaults.
for pair in "afterSelectingArea showActionBar" "closeEditorAfterCopy true" "closeEditorAfterSave true" \
  "exportStandardResolution false" "saveLocation $SAVE"; do
  send "$APP_SOCK" "defaults-set $pair" >/dev/null
done

sfacts() { send "$EDITOR_SOCK" settings-facts; }
# sval <control id>: the value of the control's line; soption <control id> <title>: of one option.
sval() { sfacts | awk -F'|' -v id="control $1" '$1 == id { print $4; exit }'; }
soption() { sfacts | awk -F'|' -v id="control $1" -v title="$2" '$1 == id && $3 == title { print $4; exit }'; }
snote() { sfacts | awk -F'|' -v id="note $1" '$1 == id { print $2; exit }'; }
sdisplay() { sfacts | awk -F'|' -v id="display $1" '$1 == id { print $2; exit }'; }
settings_is() { [[ "$(sval "$1")" == "$2" ]]; }
spress() { send_slow "$EDITOR_SOCK" "settings-press $*"; }
skey() { send_slow "$EDITOR_SOCK" "settings-key $*"; }
helper_default() { send "$EDITOR_SOCK" "defaults-get $1"; }
settings_windows() { onscreen_windows "$(helper_pid)"; }
no_helper_process() { [[ -z "$(helper_pid)" ]]; }
helper_is_foreground() { is_foreground "$(helper_pid)"; }

# 1. The menu bar menu has Settings… (⌘,) between the Captures and Quit. No helper at rest.
expect_in_order "the menu offers Capture Area, Capture Screen, Settings… and Quit snapit, in that order" \
  "$(send "$APP_SOCK" menu-titles)" "Capture Area" "Capture Screen" "Settings…" "Quit snapit"
expect_equal "Settings… is ⌘," "," "$(send "$APP_SOCK" "menu-shortcut settings" | awk '{ print $1 }')"
expect_contains "Settings… uses the command key" "command" "$(send "$APP_SOCK" "menu-shortcut settings")"
wait_until 10 no_helper_process
expect_equal "no helper runs before Settings opens" "" "$(helper_pid)"
sleep 1
SETTINGS_BASELINE_MB="$(footprint_mb "$APP_PID")"

# 2. Settings opens in the helper: one window, a Dock icon while it is the only window.
expect_equal "Settings… runs" "ok" "$(send_slow "$APP_SOCK" "menu-click settings")"
if wait_until 10 answers "$EDITOR_SOCK"; then pass "Settings… starts the Editor helper"; else fail "the helper did not start for Settings"; fi
SETTINGS_PID="$(helper_pid)"
wait_until 10 settings_is open-at-login on
FACTS="$(sfacts)"
expect_contains "the window is visible" "window=visible" "$FACTS"
expect_contains "the window is called Settings" "title=Settings" "$FACTS"
expect_contains "the helper is a regular app while Settings is open" "activation=regular" "$FACTS"
if wait_until 10 helper_is_foreground; then pass "a Dock icon shows while Settings is open"; else fail "the helper has no Dock icon with Settings open"; fi
if wait_until 10 has_onscreen_window "$SETTINGS_PID"; then pass "Settings is on screen (the window server lists it)"; else fail "no Settings window on screen"; fi
expect_equal "the page is one window" "1" "$(settings_windows)"
expect_in_order "the page has General, Capturing, Editor, Shortcuts, Export and About, in that order" \
  "$FACTS" "section General" "section Capturing" "section Editor" "section Shortcuts" "section Export" "section About"
expect_in_order "General has Open at Login, then the Save location with Choose…" \
  "$(printf '%s\n' "$FACTS" | awk -F'|' '{ print $1 }')" "control open-at-login" "control save-location" "control save-location-choose"
EMPTY_TOOLTIPS="$(printf '%s\n' "$FACTS" | grep '^control ' | awk -F'|' '$5 == "" { print $1 }')"
expect_equal "every control has a tooltip" "" "$EMPTY_TOOLTIPS"
expect_contains "the Save location starts at the test Save folder" "|path|Save location|$SAVE|" "$FACTS"
expect_equal "After selecting an Area starts at Show Action bar" "selected" "$(soption after-selecting-area "Show Action bar")"
expect_equal "Capture on release starts unselected" "unselected" "$(soption after-selecting-area "Capture on release")"
expect_equal "Close the Editor after Copy starts on" "on" "$(sval close-editor-after-copy)"
expect_equal "Close the Editor after Save starts on" "on" "$(sval close-editor-after-save)"
expect_equal "Export at standard resolution (1x) starts off" "off" "$(sval export-standard-resolution)"
expect_in_order "the Shortcuts section has recorders for Area, Window, Screen and Pick Color" \
  "$(printf '%s\n' "$FACTS" | grep '^control shortcut\.' | awk -F'|' '{ print $3 }')" "Area" "Window" "Screen" "Pick Color"
expect_equal "Area records ⌃⌥⌘4 by default" "21 control,option,command" "$(sval shortcut.capture-area)"
expect_equal "Window records ⌃⌥⌘5 by default" "23 control,option,command" "$(sval shortcut.capture-window)"
expect_equal "Screen records ⌃⌥⌘3 by default" "20 control,option,command" "$(sval shortcut.capture-screen)"
expect_equal "Pick Color has no Shortcut by default" "none" "$(sval shortcut.pick-color)"
expect_equal "Area shows ⌃⌥⌘4" "⌃⌥⌘4" "$(sdisplay capture-area)"
expect_contains "the Shortcuts section has the button that opens macOS's Screenshots shortcuts" "control open-screenshot-shortcuts|button|" "$FACTS"
expect_contains "About shows the version" "control version|text|Version|" "$FACTS"
expect_equal "the menu bar app has no window of its own" "0" "$(onscreen_windows "$APP_PID")"

# 3. A second request brings the same window forward: still one window, still one helper.
send_slow "$APP_SOCK" "menu-click settings" >/dev/null
expect_equal "a second request opens no second window" "1" "$(settings_windows)"
expect_equal "a second request starts no second helper" "1" "$(pgrep -f "$HELPER_EXE" | wc -l | tr -d " ")"
expect_equal "the helper's own request also opens no second window" "ok" "$(send "$EDITOR_SOCK" show-settings)"
expect_equal "still one window after the helper's own request" "1" "$(settings_windows)"
expect_equal "the helper's app menu has Settings… (⌘,)" "Settings…" "$(menu_items "$(send "$EDITOR_SOCK" main-menu)" snapit | grep '^Settings')"

# 4. Open at Login goes through the menu bar app and the fake login item; its status is read
#    when Settings opens, never polled.
expect_equal "the fake login item is on, as Onboarding leaves it" "enabled" "$(send "$APP_SOCK" login-item-status)"
spress open-at-login >/dev/null
expect_equal "turning Open at Login off unregisters the login item" "notRegistered" "$(send "$APP_SOCK" login-item-status)"
expect_equal "the switch shows off" "off" "$(sval open-at-login)"
spress open-at-login >/dev/null
expect_equal "turning it on registers the login item" "enabled" "$(send "$APP_SOCK" login-item-status)"
expect_equal "the switch shows on" "on" "$(sval open-at-login)"
send "$APP_SOCK" "login-item-simulate requiresApproval" >/dev/null
sleep 3
expect_equal "a status change behind Settings' back is not noticed: nothing polls" "on" "$(sval open-at-login)"
assert_idle_cpu "the helper with Settings open" "$SETTINGS_PID" 5
send_slow "$APP_SOCK" "menu-click settings" >/dev/null
wait_until 5 settings_is open-at-login needs-approval
expect_equal "asking for Settings again reads the status: approval is needed" "needs-approval" "$(sval open-at-login)"
send "$APP_SOCK" "login-item-simulate enabled" >/dev/null
send_slow "$APP_SOCK" "menu-click settings" >/dev/null
wait_until 5 settings_is open-at-login on
expect_equal "and reads it again: on" "on" "$(sval open-at-login)"

# 5. Every setting is stored by the helper under its key, and takes effect without a relaunch.
spress close-editor-after-copy >/dev/null
spress close-editor-after-save >/dev/null
spress export-standard-resolution >/dev/null
spress after-selecting-area captureOnRelease >/dev/null
send_slow "$EDITOR_SOCK" "settings-choose-save-location $SETTINGS_ELSEWHERE" >/dev/null
expect_equal "Close the Editor after Copy off is stored" "0" "$(helper_default closeEditorAfterCopy)"
expect_equal "Close the Editor after Save off is stored" "0" "$(helper_default closeEditorAfterSave)"
expect_equal "Export at standard resolution (1x) on is stored" "1" "$(helper_default exportStandardResolution)"
expect_equal "Capture on release is stored" "captureOnRelease" "$(helper_default afterSelectingArea)"
expect_equal "the chosen Save location is stored" "$SETTINGS_ELSEWHERE" "$(helper_default saveLocation)"
expect_equal "the page shows the new Save location" "$SETTINGS_ELSEWHERE" "$(sval save-location)"
expect_equal "the page shows Capture on release" "selected" "$(soption after-selecting-area "Capture on release")"
expect_equal "a Save location outside the test root is refused" "error folder must be inside the test root" \
  "$(send "$EDITOR_SOCK" "settings-choose-save-location /tmp")"

# 5a. 1x changes the Export size, live: Settings and the Editor share the helper.
if capture_into_editor "menu-click capture.screen"; then
  expect_equal "the Editor opens alongside Settings in the same helper" "$SETTINGS_PID" "$HELPER_PID"
  send "$APP_SOCK" pasteboard-clear >/dev/null
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N copy" >/dev/null
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/clip.png" >/dev/null
  check_png "1x on (Settings): Copy of a 2x Capture" "$RUN_ROOT/clip.png" 301 187 2835 "$P3_SHA" scaled:2 602 374
  # 5b. Close the Editor after Copy off: the Editor stays open.
  expect_equal "with Close the Editor after Copy off the Editor stays open after Copy" "$EDITOR_N" "$(open_editors | tail -1)"
  # 5c. Save goes to the chosen folder, and the Editor stays open with Close after Save off.
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N save" >/dev/null
  wait_until 15 save_idle
  expect_equal "the Save wrote one file into the chosen Save location" "1" "$(ls -A "$SETTINGS_ELSEWHERE" | grep -c '^snapit-.*\.png$')"
  expect_equal "the default test Save folder got nothing" "0" "$(save_dir_entries)"
  SAVED="$(ls "$SETTINGS_ELSEWHERE" | grep '^snapit-.*\.png$' | head -1)"
  check_png "1x Save into the chosen folder" "$SETTINGS_ELSEWHERE/$SAVED" 301 187 2835 "$P3_SHA" scaled:2 602 374
  expect_equal "with Close the Editor after Save off the Editor stays open after Save" "$EDITOR_N" "$(open_editors | tail -1)"
  # 1x off: back to the native size, live.
  spress export-standard-resolution >/dev/null
  send "$APP_SOCK" pasteboard-clear >/dev/null
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N copy" >/dev/null
  send "$APP_SOCK" "pasteboard-dump-png $RUN_ROOT/clip.png" >/dev/null
  check_png "1x off (Settings): Copy of a 2x Capture" "$RUN_ROOT/clip.png" 602 374 5669 "$P3_SHA" verify-fixture
  rm -f "$RUN_ROOT/clip.png"
  # Turned back on, the Editor closes after Copy and after Save again.
  spress close-editor-after-copy >/dev/null
  spress close-editor-after-save >/dev/null
  send_slow "$EDITOR_SOCK" "editor-press $EDITOR_N copy" >/dev/null
  expect_equal "with Close the Editor after Copy on again, Copy closes the Editor" "" "$(open_editors)"
  expect_equal "the helper stays up because Settings is still open" "$SETTINGS_PID" "$(helper_pid)"
fi
send "$APP_SOCK" pasteboard-clear >/dev/null
clear_save_folder

# 5d. Capture on release changes the Area flow; Show Action bar changes it back.
send "$APP_SOCK" "fixture-display 1 301 187" >/dev/null
area_start "press-shortcut capture-area" >/dev/null
expect_equal "the Area flow follows Settings: Capture on release" "captureOnRelease" "$(fact after-selecting)"
area_drag 0 20 20 120 90
if area_result; then
  pass "with Capture on release, letting go takes the Capture"
  send_slow "$EDITOR_SOCK" "editor-key $EDITOR_N close" >/dev/null
else
  fail "Capture on release did not take the Capture (reply: $AREA_REPLY)"
fi
spress after-selecting-area showActionBar >/dev/null
expect_equal "Show Action bar is stored" "showActionBar" "$(helper_default afterSelectingArea)"
area_start "press-shortcut capture-area" >/dev/null
expect_equal "the Area flow follows Settings: Show Action bar" "showActionBar" "$(fact after-selecting)"
area_drag 0 20 20 120 90
expect_equal "with Show Action bar, letting go keeps the selection" "adjusting" "$(fact state)"
send "$APP_SOCK" "overlay-key escape" >/dev/null
expect_equal "Esc cancels the selection" "cancelled" "$(send_slow "$APP_SOCK" overlay-wait)"
send "$APP_SOCK" "fixture-display 2 301 187" >/dev/null
wait_until 10 settings_is close-editor-after-copy on

# 6. Shortcuts: re-recording rebinds the Shortcut, stores it, and the menu glyph follows.
expect_equal "the Area menu item shows ⌃⌥⌘4" "4 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.area")"
spress shortcut.capture-area >/dev/null
expect_equal "pressing the recorder starts recording" "recording" "$(sval shortcut.capture-area)"
expect_equal "a key without ⌘, ⌃ or ⌥ is not a Shortcut: still recording" "ok" "$(skey 22)"
expect_equal "still recording" "recording" "$(sval shortcut.capture-area)"
expect_equal "⌃⌥⌘6 is recorded" "ok" "$(skey 22 control,option,command)"
expect_equal "the recorder shows ⌃⌥⌘6 at once" "22 control,option,command" "$(sval shortcut.capture-area)"
expect_equal "the combination is stored" "22 control,option,command" "$(helper_default shortcut.capture-area)"
expect_equal "the menu bar app rebound the Area Shortcut" "22 control,option,command" "$(send "$APP_SOCK" "shortcut-combo capture-area")"
expect_equal "the Area menu item's glyph follows: ⌃⌥⌘6" "6 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.area")"
expect_equal "Area's recorder displays ⌃⌥⌘6" "⌃⌥⌘6" "$(sdisplay capture-area)"
expect_equal "the Area Shortcut still takes a Capture after the rebind" "ok" "$(area_start "press-shortcut capture-area")"
send "$APP_SOCK" "overlay-key escape" >/dev/null
send_slow "$APP_SOCK" overlay-wait >/dev/null
# Esc cancels a recording, Delete clears the Shortcut.
spress shortcut.capture-screen >/dev/null
expect_equal "Esc cancels the recording" "ok" "$(skey 53)"
expect_equal "Screen keeps ⌃⌥⌘3 after Esc" "20 control,option,command" "$(sval shortcut.capture-screen)"
spress shortcut.capture-screen >/dev/null
skey 51 >/dev/null
expect_equal "Delete clears the Screen Shortcut" "none" "$(sval shortcut.capture-screen)"
expect_equal "the menu bar app unassigned it" "none" "$(send "$APP_SOCK" "shortcut-combo capture-screen")"
expect_equal "the Capture Screen menu item shows no key" "none" "$(send "$APP_SOCK" "menu-shortcut capture.screen")"
# A Shortcut macOS also uses is flagged; one another snapit Shortcut uses is flagged too.
spress shortcut.capture-screen >/dev/null
skey 21 shift,command >/dev/null
expect_contains "⌘⇧4 is flagged as a macOS shortcut" "macOS" "$(snote capture-screen)"
spress shortcut.capture-screen >/dev/null
skey 22 control,option,command >/dev/null
expect_contains "a key combination another snapit Shortcut uses is flagged" "Area" "$(snote capture-screen)"
expect_equal "the Area recorder flags it too" "Screen uses this key combination too." "$(snote capture-area)"
spress shortcut.capture-screen >/dev/null
skey 20 control,option,command >/dev/null
expect_equal "a free combination carries no flag" "" "$(snote capture-screen)"
expect_equal "the Screen menu item shows ⌃⌥⌘3 again" "3 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.screen")"
# Pick Color: unassigned by default, recorded like the others.
spress shortcut.pick-color >/dev/null
skey 35 control,option,command >/dev/null
expect_equal "Pick Color records ⌃⌥⌘P" "35 control,option,command" "$(helper_default shortcut.pick-color)"
spress shortcut-clear.pick-color >/dev/null
expect_equal "its clear button unassigns it" "none" "$(helper_default shortcut.pick-color)"
# Restore Area.
spress shortcut.capture-area >/dev/null
skey 21 control,option,command >/dev/null
expect_equal "Area is back to ⌃⌥⌘4 in the menu" "4 control,option,command" "$(send "$APP_SOCK" "menu-shortcut capture.area")"
# The Screenshots button goes through the System Settings deep link (recorded, not opened, in a run).
spress open-screenshot-shortcuts >/dev/null
expect_contains "the Screenshots shortcuts button opens the System Settings deep link" \
  "x-apple.systempreferences:" "$(cat "$RUN_ROOT/system-settings-links" 2>/dev/null)"

# 7. Closing Settings: the helper quits, the Dock icon goes, the menu bar app is at baseline.
send_slow "$EDITOR_SOCK" settings-close >/dev/null
if wait_until 10 gone "$SETTINGS_PID"; then pass "closing Settings, the only window, quits the helper"; else fail "the helper is still running after Settings closed"; fi
expect_equal "no helper process is left" "" "$(helper_pid)"
sleep 1
SETTINGS_AFTER_MB="$(footprint_mb "$APP_PID")"
if awk -v a="$SETTINGS_AFTER_MB" -v b="$SETTINGS_BASELINE_MB" -v max="$FOOTPRINT_GROWTH_MB_MAX" 'BEGIN { exit !(a > 0 && a - b <= max) }'; then
  pass "the menu bar app is at its baseline after Settings (${SETTINGS_BASELINE_MB} MB before, ${SETTINGS_AFTER_MB} MB after)"
else
  fail "the menu bar app grew from ${SETTINGS_BASELINE_MB} MB to ${SETTINGS_AFTER_MB} MB across Settings"
fi
assert_idle_cpu "menu bar app after Settings" "$APP_PID" 5

# 8. The chosen Shortcut and the settings are still there when Settings opens again (a fresh helper).
send_slow "$APP_SOCK" "menu-click settings" >/dev/null
wait_until 10 settings_is open-at-login on
expect_equal "a fresh Settings window shows the stored Save location" "$SETTINGS_ELSEWHERE" "$(sval save-location)"
expect_equal "and shows Close the Editor after Copy on" "on" "$(sval close-editor-after-copy)"
send_slow "$EDITOR_SOCK" settings-close >/dev/null
wait_until 10 no_helper_process

# Put every setting back for the flows after this one.
send "$APP_SOCK" "defaults-set saveLocation $SAVE" >/dev/null
send "$APP_SOCK" "defaults-set afterSelectingArea showActionBar" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterCopy true" >/dev/null
send "$APP_SOCK" "defaults-set closeEditorAfterSave true" >/dev/null
send "$APP_SOCK" "defaults-set exportStandardResolution false" >/dev/null
rm -rf "$SETTINGS_ELSEWHERE"
