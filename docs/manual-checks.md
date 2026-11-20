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
