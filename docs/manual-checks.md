# Manual checks

Checks the scripted run (`scripts/check-run.sh`) cannot make: they need a real quarantined disk
image, a real Gatekeeper block or a real install. Each check has a heading; add yours below.

## Move to Applications and the translocation check

The scripted run (`scripts/run/flows/80-move-to-applications.sh`) drives the whole check against
fixture paths: a fake read-only volume below the run's `Volumes` folder, a fake Applications
folder, a fake eject, and real relaunches. What it cannot show: a real mounted disk image, the
real `diskutil eject`, macOS's real `AppTranslocation` mount and Gatekeeper's real Open Anyway.

### Setup

1. Build a release app with a build identity of its own (a distinct bundle version, or a
   different ad-hoc signature from any snapit you have approved before), so Gatekeeper asks
   about it afresh and does not reuse another build's Open Anyway.
2. Build the DMG with the release pipeline. Simulate a browser download:
   `xattr -w com.apple.quarantine "0083;$(printf '%x' $(date +%s));Safari;$(uuidgen)" snapit.dmg`.
3. Quit any snapit that runs. Remove `/Applications/snapit.app` if it exists.

### From a disk image

1. Double-click the quarantined DMG. Open the snapit inside it **from the mounted volume**
   (do not drag it out first). macOS blocks it. Open System Settings > Privacy & Security, click
   **Open Anyway**, enter your password, then open snapit again.
2. Expect: the menu bar icon appears and the "Move snapit to Applications" window opens (a
   Dock icon shows while it is open), with the title, "Move to Applications" and "Not Now" buttons,
   each with a tooltip on hover.
3. Read where it runs from: `echo install-location | nc -w 2 -U ~/Library/Caches/dev.snapit.snapit/app.sock`.
   Expect `translocated=true`, `on-disk-image=true`, `origin=/Volumes/<DMG name>/snapit.app`,
   `decision=move`.
4. Click **Not Now**. Expect: the window closes, the Dock icon goes, snapit keeps running,
   nothing is copied, the DMG stays mounted.
5. Quit snapit, open it from the DMG again (no new Open Anyway needed), click **Move to
   Applications**.
6. Expect, within a few seconds:
   - the window closes and the snapit that ran from the DMG quits,
   - a snapit starts from `/Applications/snapit.app` with no second Gatekeeper block and no new
     Open Anyway,
   - the DMG volume disappears from Finder and `ls /Volumes` (ejected),
   - `xattr -lr /Applications/snapit.app | grep -c quarantine` prints `0`,
   - the same `install-location` command now prints `bundle=/Applications/snapit.app`,
     `translocated=false`, `on-disk-image=false`, `decision=none`.
7. Repeat steps 1 to 6 with a snapit already in `/Applications`: the window says the existing
   snapit is replaced; after the move there is one snapit, and it is the new one.
8. Move with `/Applications` not writable for your user, or the disk full: the window stays open
   and shows why; nothing in `/Applications` changed.

### Translocated copy already in Applications (update case)

1. With the quarantined DMG mounted, copy snapit to `/Applications` with Finder (a Finder copy
   keeps quarantine), eject the DMG, then open `/Applications/snapit.app`. macOS blocks it; click
   **Open Anyway** and open it again.
2. Read where it runs from. Expect, if macOS translocated it, `translocated=true`,
   `origin=/Applications/snapit.app`.
3. snapit strips quarantine from `/Applications/snapit.app` and relaunches it in place, with no
   window. Expect: a new snapit process (`pgrep -x snapit` shows a new pid), `translocated=false`,
   `xattr -lr /Applications/snapit.app | grep -c quarantine` prints `0`.
4. If macOS did not translocate it, `decision=none` and nothing happens.

### Open Anyway first

Quarantine is stripped only from an app the user approved. Check: copy the app to
`/Applications` with `ditto`, set `xattr -w com.apple.quarantine "0083;...;Safari;..."` on it
(not approved), never open it through Open Anyway: snapit never strips it. (A snapit that is
running has already been approved, so the real flow always strips.)

### Clean up

- Quit snapit and the Editor helper, eject the DMG (`diskutil eject /Volumes/<name>`), delete the
  DMG and any build you made.
- Unregister every copy from LaunchServices:
  `/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -u /Applications/snapit.app`
  (and the build folder copies, and `.../Contents/Helpers/snapit Editor.app` of each).
- Remove `/Applications/snapit.app` if you installed it for the check.
