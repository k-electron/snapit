# Manual checks

Things only a person can check, because they need Gatekeeper, macOS's own permission dialogs or a real Finder window. Each section says when to run it and how to clean up afterwards.

## Release DMG install (#34)

Run before announcing a release, and after changing `scripts/package-release.sh`, `packaging/dmg/` or how the helper is signed. The automated checks (`scripts/check-dmg.sh`, `scripts/check-bundle.sh`) already cover the DMG's contents and signatures; this covers what macOS does with a downloaded copy.

Get a quarantined DMG one of two ways:

- **From a release (best).** Download `snapit-X.Y.Z.dmg` from the draft or published GitHub Release in Safari. Safari quarantines it as a real download would.
- **From a local build.** Run `scripts/package-release.sh v0.1.0-beta.1`, then mark the DMG as downloaded:
  `xattr -w com.apple.quarantine "0083;$(printf '%x' "$(date +%s)");Safari;$(uuidgen)" build/release/snapit-0.1.0-beta.1.dmg`

Then, on a Mac where this snapit has never been opened (a second user account is ideal; otherwise remove any snapit from Applications first):

1. Open the DMG. The window shows the snapit icon, an arrow, the Applications folder and the line "First open: System Settings › Privacy & Security › Open Anyway". Both icons sit on the arrow's line, and the text is readable in Light and Dark appearance.
2. Drag snapit onto Applications.
3. Eject the DMG.
4. Open snapit from Applications. macOS says it can't verify snapit.
5. Open System Settings › Privacy & Security, click **Open Anyway** and enter your password.
6. snapit starts in the menu bar. Take a Capture so the Editor opens. Check that macOS does not ask again for the Editor helper inside the app (no second Open Anyway, no second "can't verify" dialog).
7. Allow Screen Recording as the release notes say, quit snapit, open it again and take a Capture.

Clean up:

- Quit snapit and drag it from Applications to the Trash.
- Eject the DMG if it is still mounted, and delete the downloaded file.
- `tccutil reset ScreenCapture dev.snapit.snapit`
- `lsregister -u /Applications/snapit.app` (before moving it to the Trash), with `lsregister` from `/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/`.

## Move to Applications and the translocation check (#32)

Run before announcing a release, and after changing anything in `snapit/Install/` or `snapit-editor/Install/`. The scripted run (`scripts/run/flows/80-move-to-applications.sh`) drives the whole check against fixture paths: a fake read-only volume below the run's `Volumes` folder, a fake Applications folder, a fake eject and real relaunches. What only a person can check: a real mounted disk image, the real eject, macOS's real `AppTranslocation` mount and Gatekeeper's real Open Anyway.

Use a build with an identity of its own, so Gatekeeper asks about it afresh and does not reuse another build's Open Anyway. Get a quarantined DMG as in the "Get a quarantined DMG" paragraph of the Release DMG install section above. Quit any running snapit and remove `/Applications/snapit.app` first.

Read where snapit runs from at any time with
`echo install-location | nc -w 2 -U ~/Library/Caches/dev.snapit.snapit/app.sock`. Every launch also logs the check's outcome: `log stream --predicate 'process == "snapit"'` shows a `launch check: <outcome> (bundle ..., origin ..., translocated ..., on disk image ...)` line, where the outcome is `none`, `move-screen-shown`, `fixed-in-place` or `not-approved`.

### From a disk image

1. Double-click the quarantined DMG. Open the snapit inside it **from the mounted volume** (do not drag it out first). macOS blocks it. Open System Settings > Privacy & Security, click **Open Anyway**, enter your password, then open snapit again.
2. Expect the menu bar icon and the "Move snapit to Applications" window (a Dock icon shows while it is open), with "Move to Applications" and "Not Now" buttons, each with a tooltip on hover. The log shows `launch check: move-screen-shown`.
3. `install-location` prints `translocated=true`, `on-disk-image=true`, `origin=/Volumes/<DMG name>/snapit.app`, `decision=move`.
4. Click **Not Now**. The window closes, the Dock icon goes, snapit keeps running, nothing is copied and the DMG stays mounted.
5. Quit snapit, open it from the DMG again (no new Open Anyway), click **Move to Applications**.
6. Within a few seconds:
   - the window closes and the snapit that ran from the DMG quits,
   - a snapit starts from `/Applications/snapit.app` with no second Gatekeeper block and no new Open Anyway,
   - the DMG volume disappears from Finder and `ls /Volumes` (ejected; snapit ejects only a volume that `hdiutil info` lists, so if it stays, record what `hdiutil info` printed),
   - `xattr -lr /Applications/snapit.app | grep -c quarantine` prints `0`,
   - `install-location` prints `bundle=/Applications/snapit.app`, `translocated=false`, `on-disk-image=false`, `decision=none`,
   - take a Capture: the Editor opens with no Gatekeeper dialog.
7. Quit snapit first, then repeat steps 1 to 6 with a snapit already in `/Applications` (a second snapit quits at launch while the one in Applications runs, so the check never starts). The window says the existing snapit is replaced; afterwards there is one snapit, the new one.
8. Make `/Applications` unwritable for your user (or fill the disk) and choose Move: the window stays open and shows why; nothing in `/Applications` changed.

### Translocated copy already in Applications (update case)

1. With the quarantined DMG mounted, install the way the prototype proved (a Finder-equivalent duplicate that keeps quarantine):
   `osascript -e 'tell application "Finder" to duplicate (POSIX file "/Volumes/<vol>/snapit.app" as alias) to (POSIX file "/Applications" as alias) with replacing'`
   Eject the DMG.
2. Start `log stream --predicate 'process == "snapit"'` in a terminal. Open `/Applications/snapit.app`. macOS blocks it; click **Open Anyway** and open it again.
3. Expect a `launch check: fixed-in-place` line on the **first** launch after Open Anyway, then a new snapit process at `/Applications/snapit.app` (`pgrep -x snapit` shows a new pid), `install-location` printing `translocated=false`, and `xattr -lr /Applications/snapit.app | grep -c quarantine` printing `0`.
4. If the line says `not-approved`, macOS had not yet marked the app approved when snapit checked: record that, with the `xattr -l /Applications/snapit.app` value. If it says `none`, macOS did not translocate it.
5. Repeat step 1 to 3 with a hand drag in Finder instead of the `osascript` duplicate, and record separately whether macOS translocates it.

### Clean up

- Quit snapit and the Editor helper, eject the DMG (`diskutil eject /Volumes/<name>`), delete the DMG and any build you made.
- Unregister every copy: `lsregister -u /Applications/snapit.app`, the build folder copies, and each `Contents/Helpers/snapit Editor.app`, with `lsregister` from `/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/`.
- Remove `/Applications/snapit.app` if you installed it for the check.

## Area overlay on real displays (#18)

Run on a real install, with Screen Recording granted, before a release and after changing anything in `snapit/Area/`. The scripted run drives the overlay over fixture displays; only a real screen shows ScreenCaptureKit's frames, Retina scaling and several displays. Steps 3 and 4 assume "After selecting an Area" is at Capture on release: run `defaults write dev.snapit.snapit afterSelectingArea captureOnRelease` first, and `defaults delete dev.snapit.snapit afterSelectingArea` afterwards to go back to the default (Show Action bar).

1. Press ⌃⌥⌘4 on a Retina display. The overlay appears at once (well under a blink), the frozen frame looks identical to the live screen (no color shift, no scale jump), the crosshair spans the display and the loupe follows the pointer.
2. Hover over a few windows. The window under the pointer is highlighted, the front one when they overlap.
3. Drag an Area and let go. The Editor opens on exactly that Area at native pixels. Paste it somewhere and zoom in: the edges are where the selection's edges were.
4. Click a highlighted window without dragging: that window is captured. Press ⌃⌥⌘4 again and press Esc: the overlay goes and nothing opens.
5. With two displays (ideally one Retina, one not), start a drag on one and move the pointer onto the other: the selection stops at the edge of the display it started on. Repeat starting on the other display.
6. Memory, with `footprint <pid>` (or Activity Monitor): note snapit's resting footprint (about 15 MB). With the overlay up it should be at most the resting footprint plus width x height x 4 bytes for every display (a 3024 x 1964 display is 24 MB) plus about 10 MB, and it returns to the resting footprint a moment after the Capture or Esc. The scripted run proves this only for IOSurface-backed fixture frames, the best case; if the real ScreenCaptureKit images cost more (Core Animation copying them), this is where it shows. While here, record the layout of the real frame: set a breakpoint or an `NSLog` where `ScreenCaptureKitSource.capture(filter:)` gets `output.sdrImage` and note its `alphaInfo`, `bitsPerPixel` and `bitmapInfo`. `premultipliedFirst`, 32 bits, little-endian is the layout the engine crops in place; anything else is cropped through its fallback, which copies the whole display once.
7. Start the overlay on a display showing a full-screen app in its own Space (the menu bar and the notch are covered): the overlay covers the whole display, menu bar and notch included, and Esc and a drag both work.
8. With another app frontmost, press ⌃⌥⌘4 and then Esc: the overlay goes and that app is frontmost again, with the keyboard.
9. Plug in or unplug a display (or change the arrangement) while the overlay is up: the overlay ends.

## Action bar on a real screen (#19)

Run on a real install, with Screen Recording granted, before a release and after changing anything in `snapit/Area/` (`ActionBar/` especially). The scripted run drives the Action bar with synthetic mouse events and reads its tiles and tooltips back; only a real screen and a real mouse show its look, the blur and the cursors. Start from the default ("After selecting an Area" at Show Action bar: `defaults delete dev.snapit.snapit afterSelectingArea`).

1. Press ⌃⌥⌘4 and drag an Area. Letting go keeps the selection: eight square handles, the size label above the top-left corner, and the Action bar (Capture, Cancel) below the selection on a Liquid Glass capsule (dark appearance) that refracts the dimmed screen behind it. The pointer over the bar is an arrow; over a handle it is a resize cursor; inside the selection it is a hand; elsewhere the crosshair.
2. Rest the pointer on Capture, then on Cancel. After half a second a dark pill with "Capture this Area (Enter)" or "Cancel (Esc)" appears below the bar (above it near the bottom of the display) and goes when the pointer moves. The tile under the pointer lights up. Click each button near its corner, away from its glyph and title: it must act (the whole tile is the button). Press on a tile and let go away from it: nothing happens.
3. Drag each handle, including past the opposite edge, and drag inside the selection. The selection and the bar follow; the bar never leaves the screen. While a handle is dragged the loupe shows the exact pixel under the pointer. Put selections against each corner and each edge of the display, and make one that covers the whole display: the bar stays fully visible (below, above or inside the selection).
4. Press Enter, or double-click inside the selection: the Editor opens on exactly that Area. Make a selection, double-click inside it with a slightly unsteady hand: the Capture is the selection as it was. A plain click away from the selection changes nothing; a drag away makes a new selection.
5. Click a highlighted window: it becomes the selection with its handles and the bar. Press Enter: the window's frame is captured.
6. With another app frontmost, press ⌃⌥⌘4, drag an Area and press Esc (and again with the Cancel button): the overlay goes, that app is frontmost with the keyboard, and ⌃⌥⌘4 works again at once.
7. With two displays, make a selection on one and drag a handle toward the other: the selection stops at its own display's edge, and the bar is on that display.
8. Memory, with `footprint <pid>`: the first Action bar adds about 2 MB that stays (the glass); later bars add nothing. Idle CPU is 0% with the bar and a tooltip showing.

## Timed Capture on a real screen (#20)

Run on a real install, with Screen Recording granted, before a release and after changing anything in `snapit/Area/Timed/`. The scripted run drives the countdown with synthetic mouse events and a fixture Capture; only a real screen shows ScreenCaptureKit excluding snapit's windows, clicks passing through the border to real apps, and the panels over full-screen Spaces and open menus. Start from the default ("After selecting an Area" at Show Action bar).

1. Press ⌃⌥⌘4, drag an Area. The Action bar offers Capture, a slider, "Capture in 3 s" and Cancel. Drag the slider across its whole length: the button says 1 to 10 s, and it follows the pointer even when the pointer leaves the bar. Quit snapit and open it again: the slider and the button still show the last value.
2. Click "Capture in N s". The dimmed overlay goes at once; the previous app is frontmost with the keyboard. A thin border sits just outside the Area (not over its pixels), and a small Liquid Glass badge with the seconds left and a ✕ sits below it, at the Area's right edge (above it, or inside its corner, when there is no room below).
3. While it counts, use the apps under the border: click, scroll and type into the window inside the Area and on the border itself. Every click passes through to the app beneath; the border never takes one. Open a menu, hover a button for its tooltip, or start a video: whatever is on screen at zero is what is captured.
4. Let it reach zero. The Editor opens on exactly the Area as it is at that moment (the menu, the hover and the video frame), with no border, badge or tooltip of snapit's in it, also at the Area's edges. Zoom in on the Area's edge in the Editor: no pixel of the border.
5. Rest the pointer on the ✕: after half a second a "Cancel the countdown" pill appears and goes when the pointer leaves. Press on the ✕ and let go away from it: nothing happens. Press and release on it: the countdown ends, the border and badge go, no Editor opens, and ⌃⌥⌘4 works again at once.
6. Start another countdown and press ⌃⌥⌘4: it cancels the same way. Press ⌃⌥⌘3 (Screen) and ⌃⌥⌘5 (Window) during a countdown: nothing happens and the countdown carries on; the Pick Color Shortcut (once you have recorded one in Settings) does nothing either.
7. Press ⌃⌥⌘4 with another app frontmost, start a countdown, switch to a third app and press the ✕: the third app stays frontmost.
8. With an app in a full-screen Space, start a Timed Capture of an Area in it: the border and badge show over the full-screen app, and the Capture at zero is that Space as it is. Repeat with a menu open at zero: the menu is in the Capture.
9. With two displays, start a countdown on one and move the mouse to the other: the border and badge stay with the Area. Change the display arrangement during a countdown: it ends.
10. Close the last Editor (⌘W) while a countdown runs, then let it reach zero: the Capture still opens, in a new Editor.
11. Memory and CPU, with `footprint <pid>` and Activity Monitor: while a countdown runs snapit holds no frozen frame (about the resting footprint, plus the Action bar's glass, about 2 MB); at zero and after the Editor opens it returns to the resting footprint and idles at 0% CPU.
12. Take a Timed Capture right after launching snapit, before ScreenCaptureKit could have listed it. The fallback hides the border and badge, waits 200 ms and fetches again: the Capture has neither (the scripted run cannot reach this path).
13. Rest the pointer on the ✕ in the last half second of a countdown: no tooltip is in the Capture.
14. Quit snapit (menu, Quit) during a countdown: the border and badge go and nothing is captured. Switch Spaces, or enter and leave a full-screen app, during a countdown: note whether it ends (the display-change notification may or may not fire); if it carries on, the Capture at zero is of the Space you are in. Lock the screen or put the display to sleep during a countdown: it ends, with no Capture of the lock screen on waking.
15. Make an Area against the display's edge, and one over the whole display: the border shows only on the display, and the badge sits inside the Area's top-right corner when there is no room outside.

## Window Capture on a real screen (#22)

Run on a real install, with Screen Recording granted, before a release and after changing anything in `snapit/Window/`. The scripted run drives the window overlay over a fixture window list and a fixture window image; only a real screen shows ScreenCaptureKit's single-window capture: the shadow, covered and full-screen windows, and the real corner alpha.

1. Press ⌃⌥⌘5 (or choose Capture Window). The overlay appears at once; the screen is dimmed except the window under the pointer, which has a white and blue outline. There is no crosshair, loupe or Action bar. Move over overlapping windows: the front one is highlighted.
2. Click a window: the Editor opens on exactly that window. Paste it into an app that shows transparency (Preview, a design tool): the rounded corners are transparent (no black or white corner pixels) and there is no shadow. Zoom in on an edge: it is where the window's edge was. While here, record the layout of the real window image: set a breakpoint or an `NSLog` where `ScreenCaptureKitSource.capture(filter:ignoresShadows:)` gets `output.sdrImage` and note its `alphaInfo`, `bitsPerPixel` and `bitmapInfo`. It should be premultiplied alpha first, 32 bits, little-endian, with the corner pixels' alpha 0; the Capture file is written by drawing the image into engine memory with the copy blend mode, which keeps the alpha whatever the layout. (The in-place layout check is the Area Capture's, step 6 of "Area overlay on real displays".)
3. Window Captures do not include the shadow (`WindowCapture.includesShadow` is false). The Capture's size is the window's size in points times the display's scale, e.g. a 1200 x 800 pt window on a Retina display is 2400 x 1600 pixels. To try the other choice, set the constant to true and rebuild: ScreenCaptureKit then scales the window plus its shadow into the requested size, so check the pixel size against `filter.contentRect` and add the shadow's margin to the requested width and height if the image is squeezed. Put the constant back afterwards.
4. Cover part of a window with another one, hover the covered part, click: the Capture is the whole window, including the part that was covered (the single-window filter reads the window itself, not the screen). The overlay's frozen frame shows what was on screen when you pressed the Shortcut.
5. A window with a sheet (a Save dialog attached to a document window): a sheet is probably its own entry in the window list, in front of its parent. Hover the sheet, then the parent's title bar, and record what each highlights and what each click captures: with child windows included (the default), the parent's Capture should include the sheet, and the sheet's own Capture should be the sheet alone. If hovering the sheet picks the parent, or clicking the parent leaves the sheet out, say so in the ticket.
6. A window that is partly off the screen (dragged past an edge): the highlight is cut at the display's edge, the Capture is the whole window.
7. A full-screen app in its own Space: press ⌃⌥⌘5 there; the overlay covers the display, the window is highlighted, and clicking captures it.
8. Close the window you picked between pressing the Shortcut and clicking (a window that shows a timed dialog): the Capture fails without an Editor opening, and ⌃⌥⌘5 works again at once.
9. The window is captured while snapit is still not the active app (the overlay never activates snapit in Window mode). With a document window of another app in front, press ⌃⌥⌘5, hover and click it: the captured window has coloured traffic lights and a normal (not dimmed) toolbar and title, and a panel that hides when its app is inactive (a floating inspector) is in the window list and can be picked. Press Esc while the overlay is up: it closes, which shows a non-activating panel still receives the keyboard. Then repeat from step 1 with another app frontmost and press Esc: the overlay goes and that app is frontmost again with the keyboard; no Editor helper process is left (`pgrep -f "snapit Editor"`).
10. Copy the Capture (⌘C) and Save it (⌘S); open the PNG in Preview's Inspector: it has an alpha channel and the corners are transparent. With "Export at standard resolution (1x)" on, the corners stay transparent and their edge is smooth (no dark fringe).
11. With two displays of different scale, capture a window on each: each Capture is at its own display's native pixels.

## Last Capture and Reopen Last Capture (#27)

Run after changing the Last Capture store, the Editor's state file or the menu. The scripted run reads the files in the private cache and what the Editor shows and exports; it cannot look at the real menu bar menu's greyed item or at the real cache folder.

1. **The real menu.** With no Capture since launch, open the menu bar menu: "Reopen Last Capture" is greyed out. Take a Capture and close its Editor: the item is enabled the next time the menu opens. Choose it: the Editor comes back with its Annotations and Undo history. Delete Capture in that Editor, then open the menu: the item is greyed out again.
2. **The real cache.** While a Last Capture exists, `ls -la ~/Library/Caches/dev.snapit.snapit/captures` shows `capture-<N>.pixels` and, after an edit, `capture-<N>.state` (mode 600) in a folder of mode 700. Choose Quit snapit: the folder and both files are gone.
3. **A real Retina Screen Capture.** Close its Editor and reopen it from the menu: the pixels, colors and size match the first Editor, and no pause longer than a blink shows (nothing is decoded).

4. **The message in front.** In a normal build (not test mode), take a Capture, close its Editor, damage its state file (`echo '{' > ~/Library/Caches/dev.snapit.snapit/captures/capture-<N>.state`), make another app frontmost, and choose Reopen Last Capture. "That Capture couldn't be reopened." shows in front of that app, and the menu item is greyed out afterwards.

Clean up: quit snapit, so the cache folder's `captures` folder is removed.

## Delete Capture, several Editors and the prompts (#28)

Run on a real install after changing the Editor's close path, the Quit menu or the prompt. The scripted run answers the sheet with test commands and clicks with synthetic events; only a real mouse, keyboard and screen show the sheet's look, the Dock and the real first click.

1. **The first click.** Take two Captures. Click the older Editor's trash button while the newer Editor is in front: the older window comes forward and nothing is deleted. Click the trash button again: the Editor closes at once with no question, and "Reopen Last Capture" stays enabled (it is the newer one's).
2. **The close prompt.** In the older Editor, draw an Annotation and click the red close button: a sheet slides down from that Editor's title bar, "Discard this Capture?", with Cancel and Discard; Esc cancels and ⌘D discards. Cancel keeps the Editor. Copy, then close: no question. Draw another Annotation and press ⌘W: the question returns. The newer (Last Capture) Editor closes with no question however much it holds.
3. **The Quit prompt.** With the older Editor holding an unexported Annotation and the newer one in front, choose Quit snapit in the menu bar: the older Editor comes forward with "Quit snapit?" on it. Cancel keeps snapit running. Choose it again and press "Discard and Quit": snapit and the Dock icon go. Repeat with ⌘Q from the Editor's own menu.
4. **Hover and first click from another app.** Hover each button of the sheet: its tooltip shows. Make another app frontmost, then click the older Editor's trash button: the window comes forward and nothing is deleted.
5. **Quit by the system.** With the older Editor holding an unexported Annotation, log out (or choose Restart): the Editor comes forward asking "Quit snapit?"; Cancel cancels the logout. Quit from Activity Monitor or `osascript -e 'tell application "snapit" to quit'` asks the same. Leave the prompt up past an hour (or let the Mac sleep through it) and press "Discard and Quit": nothing quits, because snapit stopped waiting and stayed.
6. **The Dock.** While any Editor is open snapit shows in the Dock and Cmd-Tab; it goes when the last Editor closes. Open three, close the middle one, take another: the new window does not sit exactly on another's.

## Settings (#29)

Run after changing the Settings window, the recorders or Open at Login. The scripted run drives the window through its model, with the fake login item and injected Shortcuts; it cannot show a real chooser, real hot keys, the real login items or System Settings.

1. **Rebind live.** Open Settings (menu bar menu, or ⌘, in the helper). Record a new Area Shortcut: the old keys stop working and the new ones start the Area Capture at once, with no relaunch, and the menu's Capture Area shows the new glyph the next time the menu opens. Record a combination another snapit Shortcut has: it is removed from that one, and only the new one fires. Press ⌘C, ⌥A and ⇧A while recording: each is refused with a beep and a hint.
2. **Capture on release, live.** In Settings choose Capture on release, close the window, then press the Area Shortcut with no relaunch: letting go of the mouse takes the Capture. Choose Show Action bar again: the Action bar shows. (The two processes share the bundle ID's defaults through macOS; the scripted run replaces that with a file.)
3. **Save location.** Choose… opens a folder chooser as a sheet; pick a folder, take a Capture and press ⌘S: the file lands there, and the page shows the folder (with `~`).
4. **Open at Login.** On a fresh install in Applications, Login Items lists snapit after the first launch (there may be a "Background item added" notification). Turn Open at Login off in Settings: snapit leaves the list. Relaunch snapit: it stays off. From a build folder or a disk image the first launch registers nothing.
5. **The deep link.** Keyboard Shortcuts in System Settings… opens System Settings on the Keyboard page; Keyboard Shortcuts… › Screenshots is one click further (the link has no anchor for it).
6. **Look.** The page is a grouped form on Liquid Glass; every button has a full-capsule hit area and a hover tooltip, and Settings alone shows a Dock icon that goes when it closes.

## Onboarding and the Screen Recording Permission guide (#30)

Run after changing Onboarding, the Permission guide, the Screen Recording questions the menu bar app answers, or resetting snapit's own entry. The scripted run drives both windows through a fake macOS (no prompt, no real TCC database, a fixture instead of `tccutil`) and cannot see macOS's prompt, System Settings, "Quit & Reopen", the real `tccutil` or the glass look.

Use a normal build in `/Applications`. To start over: quit snapit, `defaults delete dev.snapit.snapit`, and remove snapit from System Settings › Privacy & Security › Screen Recording (select it, press −), or `tccutil reset ScreenCapture dev.snapit.snapit` from Terminal.

1. **First launch.** Open snapit: Onboarding opens at Welcome, with a Dock icon. Its drawing is a mock menu bar with snapit's icon circled: check it looks like the real menu bar's icon (the window is not placed under the real one). Close it at any step and press ⌃⌥⌘4 (or reopen snapit): Onboarding comes back at that step and no Capture starts. Finish it (Done) and neither a launch nor a Shortcut opens it again.
2. **The prompt, then System Settings.** At Screen Recording macOS shows its own message once. The drawing's first picture should match it (title, "Open System Settings", and the label of its other button: the drawing says "Don't Allow"; macOS 26 may say "Deny", in which case change `GuideDrawing` to match) and the second one System Settings' Screen Recording list (Privacy & Security in the sidebar, the list's title, a switch per app); note any wording on macOS 26 that differs. "Open System Settings" opens Privacy & Security › Screen Recording. Turn snapit on: macOS offers "Quit & Reopen". Choose it: snapit relaunches and Onboarding reopens at Screen Recording saying "Screen Recording is on", and Continue goes on.
3. **Later.** Turn snapit on, choose "Later" instead. Click back into snapit's window: the guide shows the System Settings version with "Relaunch snapit". Click it: snapit relaunches and Onboarding resumes at Screen Recording, on. (macOS cannot tell "Later" from "not turned on yet", so the button shows whenever the permission is off after macOS's prompt.)
4. **Don't Allow.** Reset as above, choose "Don't Allow" in macOS's prompt, then click back into snapit's window: the drawing switches to System Settings only, and the text says macOS will not ask again. Turn snapit on in System Settings and use Quit & Reopen: it works.
5. **The grant is looked at when the window becomes active, never on a timer.** With the guide showing and the permission off, turn snapit on in System Settings and choose "Later"; leave snapit's window alone for a minute: nothing changes and Activity Monitor shows the helper at 0% CPU. Click into snapit's window: the guide looks again.
6. **The update path, with the real `tccutil`.** Install build A and grant it Screen Recording (its switch is on). Quit it and replace it with build B (a different ad-hoc build: a new code identity), then open B. Only the Screen Recording guide opens (no Onboarding), worded for the update ("snapit needs Screen Recording turned back on"). snapit removed its own old entry from the list and macOS showed its message afresh: this proves `tccutil reset ScreenCapture dev.snapit.snapit` works when run from inside the app (it had only been shown from Terminal). If it did not, the guide says "snapit could not clear its old Screen Recording entry (…)" with the reason: record it, and `log show --predicate 'process == "snapit"'` shows the same line. Grant, Quit & Reopen: Captures work, and no launch after that resets anything again (the Screen Recording list's entry stays).
7. **The animation.** It plays about nine seconds (three loops) and stops on its last picture, snapit's switch on; Replay plays it again. Minimise the window, or cover it fully with another window, switch to another Space, or hide snapit with ⌘H: each time Activity Monitor shows the helper at 0% CPU within a second or two, and the animation plays again when the window is back in view. Leaving the step and coming back plays it again. (A scripted run only minimises: it ignores occlusion, so covered windows, Spaces and ⌘H are checked here.)
8. **Shortcuts, Save location and Open at Login steps.** Record ⌘⇧3 for Area: the flag "macOS also uses this key combination." shows (turn ⌘⇧3 off in Screenshots shortcuts and the flag is gone at the next visit). Choose a folder through the real chooser sheet: it shows with `~`, and ⌘S writes there. The Open at Login switch is on for a copy in Applications and Login Items lists snapit; flipping it off removes it.
9. **Turned off on purpose.** With snapit granted and working, turn its Screen Recording switch off in System Settings (macOS may offer Quit & Reopen: choose Later, or relaunch snapit yourself). Relaunch snapit: no guide opens by itself, and nothing is reset (the Screen Recording list's entry stays). Take a Capture with its Shortcut: the Permission guide opens; in Onboarding's Screen Recording step the text says "Screen Recording is off for snapit. Turn snapit on in System Settings, then choose Quit & Reopen." and never calls it an update. Quit & Reopen: it works.
10. **Granted while snapit runs.** With snapit running without Screen Recording, turn it on in System Settings and choose Later. Click back into the guide: if it says "Relaunch snapit to start using Screen Recording" with Relaunch snapit, that is the state macOS leaves a running process in; if macOS instead lets Captures work at once, record it (snapit then never needs the relaunch, and the state is only reached through the fake). Press ⌃⌥⌘4 before relaunching: it must not fail silently.
11. **A killed snapit.** Take a Capture and leave its Editor open. Force quit snapit (Activity Monitor, or `kill -9`): the Editor stays. Open snapit again: the Editor is still open, Onboarding (if unfinished) opens beside it, and choosing Quit snapit later closes the Editor too.
12. **Look.** The window follows the Liquid Glass look in light and dark: glass cards behind the drawing, the Shortcut rows and the Save location, a Dock icon while it is open, and a hover tooltip on every button. The Done step's "Try it: press ⌃⌥⌘4" follows a Shortcut recorded in step 4. (The User Guide link appears once the User Guide window sets `UserGuideLink.open`.)

Clean up: quit snapit; reset Screen Recording and Onboarding as above if you want the next run to start fresh.
## Check for Updates over the real network (#33)

Run before a release, and after changing `snapit/Updates/`. The scripted run answers the request from a fixture (the status and body GitHub would send) and never goes online, so these steps are the only look at the real endpoint, the real browser and real failures.

1. **A newer release.** Install a build whose version is older than the newest published release (for example `MARKETING_VERSION` 0.0.1), choose Check for Updates… in the menu. The window opens at once saying "Checking for updates…", then shows "snapit X.Y.Z is available.", "You have snapit 0.0.1.", the release's notes drawn as headings, bullets and paragraphs (bold, code and links in place), the Open Anyway and Screen Recording reminder, and Close and Download. Download opens the release page in your default browser and closes the window. Click a link in the notes: it opens in the browser.
2. **Up to date.** With the installed version equal to the newest release (or newer), the window is one line: "snapit X.Y.Z is up to date." and Close.
3. **From Settings.** Settings › About has the version and a Check for Updates… button with a tooltip; it opens the same window and sends one request.
4. **Pre-releases and drafts.** Publish a `-beta` pre-release and a draft newer than the latest full release: neither is offered (the latest-release endpoint skips them). A tag that is not `vX.Y.Z` on the newest full release gives "Couldn't read GitHub's answer."
5. **A private repository.** While the repository is private, the unauthenticated endpoint answers 404, so the window says "GitHub has no release of snapit to compare with." until the repository (or the release) is public. Check this once before going public.
6. **No connection.** Turn Wi-Fi off and choose Check for Updates…: "Couldn't reach GitHub. Check your connection and try again." within a few seconds, then back on and again: it works. With a proxy that never answers (or Network Link Conditioner at 100% loss) the timeout answer, "GitHub didn't answer in time.", comes after about 10 seconds.
7. **Rate limit.** Send the request from a network that GitHub rate limits (or run `curl -s -o /dev/null -w '%{http_code}' https://api.github.com/repos/k-electron/snapit/releases/latest` 60 times in an hour first): the window says "GitHub is limiting requests right now."
8. **Only on click, only one request.** With a network monitor (`nettop -p snapit`, Little Snitch, or a proxy such as mitmproxy), launch snapit, leave it for several minutes and open Settings: no connection is opened. Choose Check for Updates…: exactly one connection, to `api.github.com`, a `GET /repos/k-electron/snapit/releases/latest` carrying `User-Agent: snapit`, `Accept: application/vnd.github+json` and `Accept-Language: en` (not your own languages), plus only the transport headers the system's HTTP client adds itself (`Host`, `Accept-Encoding`, `Connection`), and no `Authorization` or `Cookie` header. Click it twice quickly: still one request. If the proxy answers 301 with a `Location` on another host, the window says "Couldn't read GitHub's answer." and the other host receives nothing.
9. **Resting footprint, the real network path.** The scripted run answers from a fixture and never starts the system's HTTP client, so this is the only check of its footprint, idle CPU and teardown. Choose Check for Updates… ten times, closing the window each time: `footprint -p $(pgrep -x snapit)` is back to about 15 MB and Activity Monitor shows 0% CPU for the menu bar app, and no `snapit Editor` process is left once the window is closed.
10. **Look.** The window is on a material with the app icon and Liquid Glass buttons; Close and Download are glass buttons with full-capsule hit areas and hover tooltips; Return presses Download and Esc presses Close.

## Missing permissions on a real install (#31)

Run after changing `snapit/Onboarding/`, `snapit-editor/Onboarding/` (the Permission guides), the Capture flows' permission check or Save's failure paths. The scripted run uses a fake macOS (no prompt, no real TCC database, a fixture instead of `tccutil`) and a test seam for the `errno` macOS's folder denial gives; only a real install shows macOS's own messages, System Settings, the real `tccutil` and the real folder prompts. Use a normal build in `/Applications`.

1. **The real reset, from inside the app.** This is the acceptance check that `tccutil reset ScreenCapture dev.snapit.snapit` works when snapit runs it itself (it was only shown from Terminal): follow step 6 of "Onboarding and the Screen Recording Permission guide" (install build A, grant it, replace it with build B, open B). Then, with B still without the grant, press a Capture Shortcut (⌃⌥⌘3, ⌃⌥⌘4, ⌃⌥⌘5) and choose Capture Area, Capture Window, Capture Screen and Pick Color in the menu: each shows only the Screen Recording guide ("snapit needs Screen Recording turned back on" the first time, "Turn on Screen Recording for snapit" after the reset, since the history is gone), never Onboarding, never a silent failure, and no Capture starts. Log: `log show --last 5m --predicate 'process == "snapit"' | grep -i "reset"` has no "could not reset" line.
2. **Every state.** Repeat a Shortcut press in each state: never granted (`tccutil reset ScreenCapture dev.snapit.snapit` and `defaults delete dev.snapit.snapit`, with Onboarding finished: `defaults write dev.snapit.snapit onboardingStep finished`): macOS's own message appears with the guide; "Don't Allow" then a second press: the guide shows System Settings only, macOS does not ask again; the switch turned off for this build: "Screen Recording is off for snapit…"; turned on while snapit runs (and Later chosen): "Relaunch snapit to start using Screen Recording", a press does not capture, Relaunch snapit then a Capture works. With Onboarding unfinished a press shows Onboarding at its stored step instead, never both.
3. **A protected folder.** In Settings choose `~/Documents` (or `~/Desktop`) as the Save location, then Save a Capture. macOS shows its own folder message the first time: Allow, and the Save simply works with no guide. Reset it (`tccutil reset SystemPolicyDocumentsFolder dev.snapit.snapit`), Save again and choose "Don't Allow": the Editor stays open and the folder Permission guide opens: "snapit can't save into “Documents”", mentioning macOS access, with Open System Settings (Privacy & Security › Files & Folders opens), Choose another folder and Try again. Note whether macOS reports the denial as `EPERM` (the guide's wording depends on it; the scripted run only simulates it) and whether snapit appears in the Files & Folders list with the Documents Folder switch off, as the drawing shows. Turn it on there and choose Try again: the Capture is saved and the guide closes. Deny again, choose Choose another folder, pick `~/Pictures`: the Capture is saved there at once and Settings shows the new Save location.
4. **Other folders.** A folder that is read-only for you (`chmod 500` it, or Get Info › Sharing & Permissions), a drive that was unplugged after you chose it, a read-only disk image: the guide says the folder can't be written to and why, never mentions macOS access, and offers Choose another folder and Try again (Open System Settings is not offered).
5. **After the hand-over.** Choose a folder on a USB drive or a small disk image, Save, and eject it (or fill it) while the write runs (a large 6K Capture makes the window long enough; "Close the Editor after Save" on closes the Editor first): a window with "Your Capture was not saved" opens in a helper started for it (Dock icon while it shows), with Choose another folder and no Try again. Closing it quits the helper. With the Editor still open the Capture can be saved again from it once the folder works.
6. **Look and focus.** The folder Permission guide follows the macOS 26 glass look in light and dark (its buttons are Liquid Glass buttons), its drawing plays about nine seconds and stops (Replay plays it again), a hover tooltip on every button, and the helper idles at 0% CPU when it stops. Opening it does not steal typing from the app you were in beyond the normal window activation.
7. **Downloads, the default.** The spec says saving into `~/Downloads` raised no folder prompt in testing, perhaps because testing ran from a Terminal launch. On a fresh install (`tccutil reset SystemPolicyDownloadsFolder dev.snapit.snapit`, snapit launched from Finder or the Dock, not Terminal), take a Capture and Save with the default Save location. Record whether macOS shows a Downloads Folder prompt. If it does, Allow: the Save works. Choose "Don't Allow" on a second run: the folder Permission guide opens for "Downloads Folder", and Try again after turning it on in Files & Folders saves.
8. **Whose consent, and which switch.** The folder chooser is the helper's panel, while the menu bar app writes the file. After choosing `~/Desktop` through Choose another folder (or Settings) the first Save may ask again, as snapit or as "snapit Editor": note which name macOS shows, whether a second prompt appears, and which entry Files & Folders lists (the drawing assumes one switch under snapit). Note the switch's label for each of Desktop, Documents, Downloads, a USB drive and a network share against the labels the guide uses ("Desktop Folder", "Documents Folder", "Downloads Folder", "Removable Volumes", "Network Volumes"), and for a folder in iCloud Drive (`~/Library/Mobile Documents`, label "iCloud Drive"). Choose a project folder outside those and make it `chflags uchg`: the guide says macOS is refusing, with no Open System Settings and no animation. With Settings open, change the Save location through the guide: Settings shows the new path.
