# ScreenCaptureKit on macOS 26 for Area, Window and Screen Captures

Research for [issue #3](https://github.com/k-electron/snapit/issues/3). Researched 2026-11-19 against Apple developer documentation, the macOS SDK headers (macOS 27.2 SDK, whose availability annotations cover macOS 26), WWDC sessions, Apple sample code, macOS release notes, and Apple DTS answers on the Developer Forums. Where Apple publishes nothing, the doc says so. A few items are marked **verify in prototype** because only a running build can settle them.

## TL;DR

- On macOS 26 the API to use is **`SCScreenshotManager.captureScreenshot(...)`** with **`SCScreenshotConfiguration`**. Both are new in macOS 26 and return an `SCScreenshotOutput` holding SDR and/or HDR `CGImage`s. The older Core Graphics capture calls are obsoleted in the SDK and return gray images on macOS 27.
- **Screen and Area:** `captureScreenshot(rect:configuration:)` captures a rectangle given in global screen points, across displays, and does not need an `SCShareableContent` fetch. **Window:** `captureScreenshot(contentFilter:configuration:)` with `SCContentFilter(desktopIndependentWindow:)`.
- **Hover-to-pick:** call `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` once when the Shortcut fires. It is documented front-to-back, is not deprecated, and never prompts. Hit-test locally after that.
- **0% idle CPU is easy to meet.** The one-shot APIs keep nothing running. Never keep an `SCStream` running, never poll `SCShareableContent`, and fetch everything at Shortcut time.
- **Permission is the big risk.** An **ad-hoc signed build has a code identity tied to that exact build**, so macOS cannot carry the Screen Recording grant over to an update. Users will probably have to re-grant after every update. macOS can also show periodic Screen Recording alerts and notifications that apps cannot turn off.

## 1. Which API takes a single-frame Capture

### The macOS 26 screenshot API

`SCScreenshotManager` has five class methods ([docs](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager); header `ScreenCaptureKit.framework/Headers/SCScreenshotManager.h`):

| Method | Since | Input | Output |
|---|---|---|---|
| [`captureScreenshot(rect:configuration:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/capturescreenshot(rect:configuration:completionhandler:)) | macOS 26.0 | `CGRect` in screen points + `SCScreenshotConfiguration` | `SCScreenshotOutput` |
| [`captureScreenshot(contentFilter:configuration:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/capturescreenshot(contentfilter:configuration:completionhandler:)) | macOS 26.0 | `SCContentFilter` + `SCScreenshotConfiguration` | `SCScreenshotOutput` |
| [`captureImage(in:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(in:completionhandler:)) | macOS 15.2 | `CGRect` in screen points | `CGImage` |
| [`captureImage(contentFilter:configuration:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:completionhandler:)) | macOS 14.0 | filter + `SCStreamConfiguration` | `CGImage` |
| [`captureSampleBuffer(contentFilter:configuration:)`](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/capturesamplebuffer(contentfilter:configuration:completionhandler:)) | macOS 14.0 | filter + `SCStreamConfiguration` | `CMSampleBuffer` |

- All five are async class methods, so no manager instance is needed ([WWDC23 10136](https://developer.apple.com/videos/play/wwdc2023/10136/)).
- The SDK header documents the `rect` variants as "the rect for the region in points on the screen space ... this is display agnostic and supports multiple displays" (`SCScreenshotManager.h`; [docs](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(in:completionhandler:))). The June 2024 ScreenCaptureKit updates list "Capture screenshots across multiple displays" ([updates](https://developer.apple.com/documentation/updates/screencapturekit)).
- [`SCScreenshotConfiguration`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration) (macOS 26) "provides a default image capture configuration"; you set its properties only to customize. Properties:
  - [`width`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/width) and [`height`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/height): pixels. Default is the size of the captured content.
  - [`sourceRect`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/sourcerect): points, in the display's logical coordinate system.
  - [`destinationRect`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/destinationrect): pixels. Ignored for single-window captures.
  - [`showsCursor`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/showscursor): default **true**.
  - [`ignoreShadows`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/ignoreshadows) and [`ignoreClipping`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/ignoreclipping).
  - [`includeChildWindows`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/includechildwindows): default **true**, so alerts, popovers and sheets are included.
  - [`displayIntent`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/displayintent-swift.property): `.local` or `.canonical`.
  - [`dynamicRange`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/dynamicrange-swift.property): `.sdr`, `.hdr` or `.bothSDRAndHDR`.
  - [`contentType`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/contenttype) and [`fileURL`](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/fileurl): optional save to HEIC, JPEG or PNG. These are not needed, because the Rust engine owns encoding.
- [`SCScreenshotOutput`](https://developer.apple.com/documentation/screencapturekit/scscreenshotoutput) has `sdrImage`, `hdrImage` and `fileURL`.

### Screenshot API or stream

- The screenshot API "brings the benefits of ScreenCaptureKit streaming to screenshots" (filtering by app or window, pixel formats, color spaces, cursor visibility). It is the documented path for a still image ([WWDC23 10136](https://developer.apple.com/videos/play/wwdc2023/10136/)).
- Running an `SCStream` costs surfaces in a server-side pool. The pool size is `queueDepth`, 3–8. "More surfaces in the pool ... results in higher system memory usage" ([WWDC22 10155](https://developer.apple.com/videos/play/wwdc2022/10155/)). Apple's sample notes that a deeper queue increases "the memory footprint of WindowServer" ([Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)).
- A stream delivers frames continuously, which conflicts with 0% idle CPU. snapit has no use for a stream in v1. Screen recording is out of scope.

### Legacy Core Graphics capture is gone

- `CGWindowListCreateImage`, `CGWindowListCreateImageFromArray` and `CGDisplayCreateImage` are marked `SCREEN_CAPTURE_OBSOLETE(..., 14.0/14.4, 15.0)`, which expands to `availability(macos, deprecated=14.x, obsoleted=15.0, message="Please use ScreenCaptureKit instead.")`. They are therefore unavailable to an app targeting macOS 26 (SDK header `CoreGraphics.framework/Headers/CGWindow.h`, `CGDirectDisplay.h`; [docs](https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage)).
- The macOS 15 release notes say apps using deprecated capture APIs "can trigger system alerts" and should migrate to ScreenCaptureKit and `SCContentSharingPicker` ([macOS 15 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes)).
- On **macOS 27**, `CGWindowListCreateImage` returns a gray image. Apple DTS confirmed this and said "I don't have a way to get the earlier result on macOS 27" ([forum 847998](https://developer.apple.com/forums/thread/847998), [forum 849969](https://developer.apple.com/forums/thread/849969)).

## 2. Retina scale, color space, multiple displays

### Scale

- `SCScreenshotConfiguration.width` and `height` are in **pixels** and default to the captured content's size. A default config should therefore give native-resolution output ([width](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/width), [height](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/height)). **Verify in prototype** that the default is native pixels on a 2x display.
- **Trap with the older API:** `SCStreamConfiguration.width` defaults to **1920 on macOS** (SDK header `SCStream.h`; [docs](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)). `SCDisplay.width` and `height` are in **points** ([SCDisplay](https://developer.apple.com/documentation/screencapturekit/scdisplay)). Copying the display's width into a stream config gives a half-resolution, blurry image on Retina ([forum 739593](https://developer.apple.com/forums/thread/739593), community answer). If `captureImage(contentFilter:configuration:)` is ever used, set `width = contentRect.width × pointPixelScale` and `captureResolution = .best`.
- `SCContentFilter` exposes [`contentRect`](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/contentrect) in points and [`pointPixelScale`](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/pointpixelscale). [`SCShareableContent.info(for:)`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent/info(for:)) returns the same for any filter. Use these for point↔pixel maths instead of assuming 2x.
- A scale factor of 2 means "every one point onscreen equals four pixels". When the frame and target display differ, scale by the scale factor ([WWDC22 10155](https://developer.apple.com/videos/play/wwdc2022/10155/)).

### Color space and pixel format

- `sdrImage` "uses the same color space as the content capture display". `hdrImage` "uses the extended sRGB color space" ([sdrImage](https://developer.apple.com/documentation/screencapturekit/scscreenshotoutput/sdrimage), [hdrImage](https://developer.apple.com/documentation/screencapturekit/scscreenshotoutput/hdrimage)).
- **Consequence for the Rust engine:** pixels arrive in the display's color space (often Display P3 on Apple displays), not sRGB. Carry the `CGColorSpace` alongside the buffer and embed the ICC profile on Export, or convert on purpose. Do not assume sRGB.
- `captureImage(contentFilter:configuration:)` returns BGRA for SDR and RGhA (half-float) for HDR (`SCScreenshotManager.h`). `SCStreamConfiguration.colorSpaceName` defaults to the display's color space ([colorSpaceName](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration/colorspacename)).
- HDR: `.local` "optimiz[es] output for presentation on the capture display". `.canonical` optimizes "for presentation on a high dynamic range display" ([DisplayIntent](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/displayintent-swift.enum); [WWDC24 10088](https://developer.apple.com/videos/play/wwdc2024/10088/)). Interop is still fragile: macOS 27 fixed "HDR screenshots might appear garbled when sent in Messages" ([macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)). **Recommendation: SDR only in v1.**

### Multiple displays with different scales

- The `rect` variants are "display agnostic and support multiple displays" (`SCScreenshotManager.h`).
- Apple does not document the output pixel density when a rectangle spans a 1x and a 2x display. **Verify in prototype**, or capture per display and stitch in Rust.
- The display-filter route captures one `SCDisplay` at a time ([SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)).
- For Screen mode, capturing the display under the pointer avoids the mixed-scale question entirely.

## 3. Window enumeration for hover-to-pick

There are two sources of window data.

**`CGWindowListCopyWindowInfo`** ([docs](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)))

- With `kCGWindowListOptionOnScreenOnly` it lists "all on-screen windows in this user session, ordered from front to back" (`CGWindow.h`).
- It is **not deprecated** (`API_AVAILABLE(macos(10.5))`).
- It "never triggers an authorization prompt". Window names are withheld until Screen Recording is granted, but bounds, window ID, owner name and PID are always returned ([WWDC19 701](https://developer.apple.com/videos/play/wwdc2019/701/)).
- Apple warns that "generating the dictionaries for system windows is a relatively expensive operation". Call it once per Capture, not on every mouse move.

**`SCShareableContent`** ([docs](https://developer.apple.com/documentation/screencapturekit/scshareablecontent))

- [`excludingDesktopWindows(_:onScreenWindowsOnly:)`](https://developer.apple.com/documentation/screencapturekit/scshareablecontent/getexcludingdesktopwindows(_:onscreenwindowsonly:completionhandler:)) returns `SCWindow`s with `windowID`, `frame`, `windowLayer`, `owningApplication` and `isOnScreen` ([SCWindow](https://developer.apple.com/documentation/screencapturekit/scwindow)).
- **The order of the `windows` array is not documented**, so it cannot drive front-most hit-testing on its own.
- It is required to build the `SCContentFilter` for a Window Capture.
- Fetching it can be slow. A developer reported 5+ seconds with no Apple answer ([forum 804083](https://developer.apple.com/forums/thread/804083)). Treat that as anecdotal and measure it.

**Recommended flow**

1. When the Shortcut fires, call `CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)` and keep windows at layer 0 (normal app windows). Exclude snapit's own PID. This gives the z-ordered list.
2. Start an `SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)` fetch at the same moment, while the user is still aiming.
3. Hit-test the pointer against the cached frames locally to highlight the window. There are no window-server calls per mouse move.
4. On click, map `CGWindowID` to `SCWindow.windowID` and capture with `SCContentFilter(desktopIndependentWindow:)`.
5. Throw everything away afterwards.

**Coordinates:** CG window bounds use a top-left-origin global space. AppKit uses bottom-left. Convert carefully. `sourceRect` is "points in the display's logical coordinate system" ([sourceRect](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/sourcerect)).

## 4. Screen Recording permission

### Flow

- Add `NSScreenCaptureUsageDescription` to Info.plist ([ScreenCaptureKit overview](https://developer.apple.com/documentation/screencapturekit)).
- [`CGPreflightScreenCaptureAccess()`](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()) checks without prompting.
- [`CGRequestScreenCaptureAccess()`](https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()) prompts only if the user has not decided yet. "A previously denied process is not re-prompted; the user must enable access in System Settings > Privacy & Security > Screen Recording" (`CGWindow.h`). Onboarding must deep-link to that pane after a denial. The user manages the toggle there ([Apple Support](https://support.apple.com/guide/mac-help/mchld6aa7d23/26/mac/26)).
- Apple's sample says: "After you grant permission, you need to restart the app to enable capture" ([sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)). DTS repeated this in Oct 2026 ([forum 847998](https://developer.apple.com/forums/thread/847998)). Onboarding should offer a "Relaunch snapit" step.
- Calling `SCShareableContent` itself triggers the Screen Recording request ([forum 849969](https://developer.apple.com/forums/thread/849969), DTS). A declined capture surfaces as `SCStreamError.userDeclined` (−3801) (`SCError.h`).
- `SCContentSharingPicker` is the consent path that avoids a blanket grant, but it is a system picker for choosing content ([docs](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker)). It cannot do Area Captures or Shortcut-driven Captures, so it does not fit snapit.

### Periodic alerts and notifications

- macOS 15 added system alerts for apps using deprecated capture APIs. macOS 15.1 says "users will see fewer dialogs if they regularly use apps in which they have already acknowledged and accepted the risks" ([15.0](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes), [15.1](https://developer.apple.com/documentation/macos-release-notes/macos-15_1-release-notes) release notes).
- Managed Macs can suppress them with the MDM restriction `forceBypassScreenCaptureAlert`: "the system bypasses the presentation of a screen capture alert", macOS 15.1+ ([Restrictions](https://developer.apple.com/documentation/devicemanagement/restrictions)). Apps have no equivalent.
- An app calling `SCScreenshotManager` repeatedly triggered a system notification of the form "'App' has accessed your screen and system audio N times in the past 30 days". DTS said: "There's no supported way for you to disable this alert with the APIs currently available" ([forum 784467](https://developer.apple.com/forums/thread/784467)).
- Apple does not document how often the periodic re-approval appears. Press coverage from the macOS 15 betas describes a monthly "Allow For One Month" prompt ([9to5Mac, secondary](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/)). **Observe the macOS 26/27 behavior in the prototype.** Onboarding copy should warn that macOS may occasionally ask again.

### Ad-hoc signing: the grant probably does not survive updates

- TN3127: macOS records the app's designated requirement (DR) with a privacy grant, then checks each launch against it. "Ad hoc signed code ... has a DR but it's tied to that specific version of the code ... macOS can't reliably track the identity of the code ... Without a DR, macOS can't track this authorization across versions of your app" ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).
- The requirement-language guide adds that an ad-hoc signature "identifies exactly and only the one program being signed" ([Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)).
- **Consequence:** after each update through "Check for Updates", snapit is very likely a different identity to TCC. The Screen Recording toggle may still look on in System Settings but will not match the new build. The user has to remove or re-toggle the entry and relaunch. The same thing happens on every local rebuild during development; `tccutil reset ScreenCapture <bundle-id>` clears it (`man 1 tccutil`).
- **Possible mitigation (unverified):** sign every release with the same **self-signed certificate** and an explicit DR such as `identifier "<bundle id>" and certificate leaf = H"<sha1>"`. The requirement language supports leaf-certificate hashes, and for self-signed code "the leaf and root refer to the same single certificate" ([requirement language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)). That would give TCC a stable identity without a paid account. Apple does not document TCC honoring non-Apple-anchored DRs for Screen Recording, so **verify in prototype** (grant, update, check that capture still works).

## 5. Hotkey-to-pixels latency

- **Apple publishes no latency figures** for `SCScreenshotManager`. WWDC sessions describe the API as asynchronous and say it can "efficiently grab an image" ([WWDC23 10136](https://developer.apple.com/videos/play/wwdc2023/10136/)). Capture, scaling and color conversion are hardware-accelerated into GPU-backed `IOSurface`s ([WWDC22 10155](https://developer.apple.com/videos/play/wwdc2022/10155/)).
- The likely slow step is the `SCShareableContent` fetch ([forum 804083](https://developer.apple.com/forums/thread/804083), unanswered). The `rect` variants need no fetch. That makes Screen and Area Captures independent of it, and for Window Captures the fetch overlaps the user's aiming time.
- **Measure in the prototype:** Shortcut → `CGImage` for each mode, on a 1-display and a 2-display mixed-scale setup.

## 6. Idle cost (0% idle CPU, low memory)

- The `SCScreenshotManager` methods are one-shot class methods with nothing to start or stop ([docs](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager)). Nothing runs between Captures.
- **Do not** keep shareable content "warm". An `SCShareableContent` object is a snapshot, so keeping it current would need polling. That breaks 0% idle CPU, and a stale snapshot gives wrong window frames anyway. Fetch at Shortcut time.
- **Do not** keep an `SCStream` open to cut latency. It holds `queueDepth` surfaces in WindowServer and delivers frames continuously ([WWDC22 10155](https://developer.apple.com/videos/play/wwdc2022/10155/); [sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)).
- Memory during a Capture is transient. A full-resolution BGRA frame is width × height × 4 bytes, about 59 MB for a 5120×2880 display. A freeze-frame Area flow holds one per display until the selection is made. Release it once the Editor owns the cropped image.

## Recommended APIs per Capture mode

| Capture mode | Recommended call | Notes |
|---|---|---|
| **Screen** | `SCScreenshotManager.captureScreenshot(rect: <display frame in global points>, configuration: SCScreenshotConfiguration())` | No `SCShareableContent` fetch. Pick the display under the pointer. Set `showsCursor = false` unless a setting says otherwise. If snapit's own windows must be excluded, fall back to `captureScreenshot(contentFilter: SCContentFilter(display:excludingApplications:[snapit], exceptingWindows: []), ...)`. |
| **Area** | Freeze-frame: when the Shortcut fires, `captureScreenshot(rect:)` for each display (in parallel), show the frozen image in a selection overlay, then crop in pixels in Rust. | What you see is what you get, and the overlay never appears in the Capture. The alternative, a live overlay followed by `captureScreenshot(rect: selection)`, would capture snapit's own overlay: the `rect` call has no filter, and `NSWindow.sharingType = .none` is "a legacy constant that macOS no longer uses" ([docs](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none)). |
| **Window** | `CGWindowListCopyWindowInfo` for hover-to-pick, then `captureScreenshot(contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration:)` | A single-window filter captures the full window "even when the source window is off-screen or occluded" ([WWDC22 10155](https://developer.apple.com/videos/play/wwdc2022/10155/)). The open shadow decision maps to `ignoreShadows`. `includeChildWindows` defaults to true (sheets, popovers). |

For all modes: `dynamicRange = .sdr`, keep the output `CGImage`'s color space, and hand the pixels plus color space to the Rust engine.

## Gotchas

1. **Ad-hoc signing will likely cost the Screen Recording grant on every update** (TN3127). This is the biggest UX risk for a non-notarized DMG.
2. **Restart after grant:** capture may not work until snapit relaunches after the user enables Screen Recording ([sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)).
3. **Denied is sticky:** `CGRequestScreenCaptureAccess()` will not prompt again. Send the user to System Settings (`CGWindow.h`).
4. **Periodic system re-approval and "accessed your screen N times" notifications** exist, and apps cannot disable them ([forum 784467](https://developer.apple.com/forums/thread/784467)).
5. **Points vs pixels:** `SCDisplay` sizes are points. `SCStreamConfiguration.width` defaults to 1920. Prefer `SCScreenshotConfiguration`, which defaults to content size.
6. **Color space is the display's**, not sRGB ([sdrImage](https://developer.apple.com/documentation/screencapturekit/scscreenshotoutput/sdrimage)).
7. **Cursor is visible by default** in both config types ([showsCursor](https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration/showscursor)).
8. **`SCShareableContent.windows` order is undocumented.** Use `CGWindowListCopyWindowInfo` for z-order.
9. **`NSWindow.sharingType = .none` does not hide windows from capture** ([docs](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none)). Exclude snapit's windows with a content filter, or use freeze-frame.
10. **Legacy `CGWindowListCreateImage` / `CGDisplayCreateImage`** are obsoleted at macOS 15 and return gray images on macOS 27 ([forum 847998](https://developer.apple.com/forums/thread/847998)).
11. **Coordinate spaces:** CG/ScreenCaptureKit global rects use a top-left origin, while AppKit uses bottom-left.
12. **Mixed-scale multi-display `rect` captures** are undocumented. Verify in the prototype or capture per display.

## Open questions surfaced

- **Distribution / updates:** should releases be signed with a stable self-signed certificate and explicit DR, so the Screen Recording grant survives updates? This needs a prototype check and a decision on how CI keeps the private key.
- **Area capture model:** freeze-frame or live overlay? Freeze-frame is recommended; it is a product decision for the Capture-flow ticket.
- **Area across displays:** allow a selection that spans displays with different scales, or limit it to one display?
- **HDR:** SDR-only in v1 (recommended)? HDR Export is a later effort.
- **Measure in prototype:** Shortcut-to-pixels latency per mode, the `SCShareableContent` fetch time, and how often macOS 26/27 re-prompts.

## Sources

- ScreenCaptureKit: <https://developer.apple.com/documentation/screencapturekit>, updates <https://developer.apple.com/documentation/updates/screencapturekit>
- SCScreenshotManager / SCScreenshotConfiguration / SCScreenshotOutput: <https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager>, <https://developer.apple.com/documentation/screencapturekit/scscreenshotconfiguration>, <https://developer.apple.com/documentation/screencapturekit/scscreenshotoutput>
- SCShareableContent / SCWindow / SCDisplay / SCContentFilter / SCStreamConfiguration / SCContentSharingPicker: <https://developer.apple.com/documentation/screencapturekit/scshareablecontent>, <https://developer.apple.com/documentation/screencapturekit/scwindow>, <https://developer.apple.com/documentation/screencapturekit/scdisplay>, <https://developer.apple.com/documentation/screencapturekit/sccontentfilter>, <https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration>, <https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker>
- Sample: Capturing screen content in macOS: <https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos>
- Core Graphics: <https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)>, <https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess()>, <https://developer.apple.com/documentation/coregraphics/cgrequestscreencaptureaccess()>, <https://developer.apple.com/documentation/coregraphics/cgwindowlistcreateimage>
- SDK headers (Xcode / Command Line Tools, macOS 27.2 SDK): `ScreenCaptureKit.framework/Headers/{SCScreenshotManager,SCShareableContent,SCStream,SCError}.h`, `CoreGraphics.framework/Headers/{CGWindow,CGDirectDisplay}.h`
- AppKit: <https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none>
- WWDC: [WWDC19 701](https://developer.apple.com/videos/play/wwdc2019/701/), [WWDC22 10155](https://developer.apple.com/videos/play/wwdc2022/10155/), [WWDC23 10136](https://developer.apple.com/videos/play/wwdc2023/10136/), [WWDC24 10088](https://developer.apple.com/videos/play/wwdc2024/10088/)
- Release notes: [macOS 15](https://developer.apple.com/documentation/macos-release-notes/macos-15-release-notes), [macOS 15.1](https://developer.apple.com/documentation/macos-release-notes/macos-15_1-release-notes), [macOS 27](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)
- Device management: <https://developer.apple.com/documentation/devicemanagement/restrictions>
- Code signing: [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements), [Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)
- Apple Support: <https://support.apple.com/guide/mac-help/mchld6aa7d23/26/mac/26>
- Developer Forums (Apple DTS answers): [784467](https://developer.apple.com/forums/thread/784467), [847998](https://developer.apple.com/forums/thread/847998), [849969](https://developer.apple.com/forums/thread/849969); community, no Apple answer: [804083](https://developer.apple.com/forums/thread/804083), [739593](https://developer.apple.com/forums/thread/739593)
- Secondary (labelled where used): [9to5Mac, Aug 2024](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/)
