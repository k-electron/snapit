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

1. Press ⌃⌥⌘4 and drag an Area. Letting go keeps the selection: eight square handles, the size label above the top-left corner, and the Action bar (Capture, Cancel) below the selection on a dark blurred capsule with a hairline edge; the dimmed screen shows through the blur. The pointer over the bar is an arrow; over a handle it is a resize cursor; inside the selection it is a hand; elsewhere the crosshair.
2. Rest the pointer on Capture, then on Cancel. After half a second a dark pill with "Capture this Area (Enter)" or "Cancel (Esc)" appears below the bar (above it near the bottom of the display) and goes when the pointer moves. The tile under the pointer lights up. Click each button near its corner, away from its glyph and title: it must act (the whole tile is the button). Press on a tile and let go away from it: nothing happens.
3. Drag each handle, including past the opposite edge, and drag inside the selection. The selection and the bar follow; the bar never leaves the screen. While a handle is dragged the loupe shows the exact pixel under the pointer. Put selections against each corner and each edge of the display, and make one that covers the whole display: the bar stays fully visible (below, above or inside the selection).
4. Press Enter, or double-click inside the selection: the Editor opens on exactly that Area. Make a selection, double-click inside it with a slightly unsteady hand: the Capture is the selection as it was. A plain click away from the selection changes nothing; a drag away makes a new selection.
5. Click a highlighted window: it becomes the selection with its handles and the bar. Press Enter: the window's frame is captured.
6. With another app frontmost, press ⌃⌥⌘4, drag an Area and press Esc (and again with the Cancel button): the overlay goes, that app is frontmost with the keyboard, and ⌃⌥⌘4 works again at once.
7. With two displays, make a selection on one and drag a handle toward the other: the selection stops at its own display's edge, and the bar is on that display.
8. Memory, with `footprint <pid>`: the first Action bar adds under 1 MB that stays; later bars add nothing. Idle CPU is 0% with the bar and a tooltip showing.

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

## Settings (#29)

Run after changing the Settings window, the recorders or Open at Login. The scripted run drives the window through its model, with the fake login item and injected Shortcuts; it cannot show a real chooser, real hot keys, the real login items or System Settings.

1. **Rebind live.** Open Settings (menu bar menu, or ⌘, in the helper). Record a new Area Shortcut: the old keys stop working and the new ones start the Area Capture at once, with no relaunch, and the menu's Capture Area shows the new glyph the next time the menu opens. Record a combination another snapit Shortcut has: it is removed from that one, and only the new one fires. Press ⌘C, ⌥A and ⇧A while recording: each is refused with a beep and a hint.
2. **Capture on release, live.** In Settings choose Capture on release, close the window, then press the Area Shortcut with no relaunch: letting go of the mouse takes the Capture. Choose Show Action bar again: the Action bar shows. (The two processes share the bundle ID's defaults through macOS; the scripted run replaces that with a file.)
3. **Save location.** Choose… opens a folder chooser as a sheet; pick a folder, take a Capture and press ⌘S: the file lands there, and the page shows the folder (with `~`).
4. **Open at Login.** On a fresh install in Applications, Login Items lists snapit after the first launch (there may be a "Background item added" notification). Turn Open at Login off in Settings: snapit leaves the list. Relaunch snapit: it stays off. From a build folder or a disk image the first launch registers nothing.
5. **The deep link.** Keyboard Shortcuts in System Settings… opens System Settings on the Keyboard page; Keyboard Shortcuts… › Screenshots is one click further (the link has no anchor for it).
6. **Look.** The page is a grouped form on macOS 26 glass; every button has a full-capsule hit area and a hover tooltip, and Settings alone shows a Dock icon that goes when it closes.
