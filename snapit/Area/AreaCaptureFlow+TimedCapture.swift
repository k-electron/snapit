import AppKit

/// Timed Capture: the Action bar's "Capture in N s". The overlay goes and the desktop is the
/// user's again; a click-through border around the Area and a countdown badge with a ✕ show while
/// the seconds run. At zero a fresh Capture is taken, with snapit's own windows excluded through
/// the content filter, cropped to the Area, and opened in the Editor.
///
/// The Capture stays under way (the gate is held, the Editor helper warms up) until it opens or
/// ends. The ✕, the Area Shortcut (and the menu item) cancel; so does a change of displays. A
/// countdown holds only the Area's display and pixel rectangle, never the frozen frame.
extension AreaCaptureFlow {
    /// The countdown that is running, if any.
    private(set) static var countdown: TimedCountdown?
    /// When the latest countdown started, for the scripted run.
    private(set) static var lastStartedAt: ContinuousClock.Instant?

    /// The overlay ended with a Timed Capture: the frozen frames go and the countdown starts.
    static func beginTimedCapture(from controller: AreaOverlayController, area: ChosenArea, seconds: Int) {
        let frozen = controller.displays[area.displayIndex]
        let target = TimedCountdown.Target(
            displayID: frozen.displayID, frame: frozen.frame, scale: frozen.scale, pixels: area.pixels)
        controller.teardown()
        // The desktop is the user's again, and what they switch to during the countdown is theirs.
        if let previous = previousApp {
            previous.activate()
        } else if !TestMode.isActive {
            NSApp.deactivate()
        }
        previousApp = nil

        let timed = TimedCountdown(target: target, seconds: seconds)
        timed.onCancel = { cancelTimedCapture() }
        timed.onZero = { fireTimedCapture() }
        // The helper that warmed up for this Capture may have quit while the seconds ran: one
        // second before the Capture it is asked again (the Capture's warm-up began at the Shortcut).
        timed.onLastSecond = { EditorWarmUp.revalidate() }
        countdown = timed
        timed.start()
        lastStartedAt = timed.startedAt
    }

    /// The ✕, the Area Shortcut or a change of displays: nothing is captured.
    static func cancelTimedCapture() {
        guard let timed = countdown else { return }
        countdown = nil
        timed.close()
        conclude(.cancelled)
    }

    /// The seconds ran out: a fresh Capture of the display, then the usual crop and Editor.
    private static func fireTimedCapture() {
        guard let timed = countdown else { return }
        let request = FreshCaptureRequest(
            displayID: timed.target.displayID, displayFrame: timed.target.frame, ownWindows: timed.ownWindows)
        Task {
            do {
                let screen = try await TimedCaptureSources.current.captureFresh(request) { timed.hideWindows() }
                // Cancelled (the ✕ pressed while the Capture was being taken): the pixels go unused.
                guard countdown === timed else { return }
                countdown = nil
                timed.close()
                conclude(await capture(screen, area: timed.target.pixels))
            } catch {
                guard countdown === timed else { return }
                NSLog("snapit: Timed Capture failed: \(error)")
                countdown = nil
                timed.close()
                conclude(.failed("\(error)"))
            }
        }
    }
}
