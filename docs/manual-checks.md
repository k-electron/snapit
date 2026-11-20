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

## Area overlay on real displays (#18)

Run on a real install, with Screen Recording granted, before a release and after changing anything in `snapit/Area/`. The scripted run drives the overlay over fixture displays; only a real screen shows ScreenCaptureKit's frames, Retina scaling and several displays.

1. Press ⌃⌥⌘4 on a Retina display. The overlay appears at once (well under a blink), the frozen frame looks identical to the live screen (no color shift, no scale jump), the crosshair spans the display and the loupe follows the pointer.
2. Hover over a few windows. The window under the pointer is highlighted, the front one when they overlap.
3. Drag an Area and let go. The Editor opens on exactly that Area at native pixels. Paste it somewhere and zoom in: the edges are where the selection's edges were.
4. Click a highlighted window without dragging: that window is captured. Press ⌃⌥⌘4 again and press Esc: the overlay goes and nothing opens.
5. With two displays (ideally one Retina, one not), start a drag on one and move the pointer onto the other: the selection stops at the edge of the display it started on. Repeat starting on the other display.
6. Memory, with `footprint <pid>` (or Activity Monitor): note snapit's resting footprint (about 15 MB). With the overlay up it should be at most the resting footprint plus width x height x 4 bytes for every display (a 3024 x 1964 display is 24 MB) plus about 10 MB, and it returns to the resting footprint a moment after the Capture or Esc. The scripted run proves this only for IOSurface-backed fixture frames, the best case; if the real ScreenCaptureKit images cost more (Core Animation copying them), this is where it shows. While here, record the layout of the real frame: set a breakpoint or an `NSLog` where `ScreenCaptureKitSource.capture(filter:)` gets `output.sdrImage` and note its `alphaInfo`, `bitsPerPixel` and `bitmapInfo`. `premultipliedFirst`, 32 bits, little-endian is the layout the engine crops in place; anything else is cropped through its fallback, which copies the whole display once.
7. Start the overlay on a display showing a full-screen app in its own Space (the menu bar and the notch are covered): the overlay covers the whole display, menu bar and notch included, and Esc and a drag both work.
8. With another app frontmost, press ⌃⌥⌘4 and then Esc: the overlay goes and that app is frontmost again, with the keyboard.
9. Plug in or unplug a display (or change the arrangement) while the overlay is up: the overlay ends.
