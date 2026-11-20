import Foundation

/// A Screen Capture: the display under the pointer, opened in the Editor.
///
/// The Shortcut and the "Capture Screen" menu item both run this. The pixels go to the Editor
/// helper through a Capture file (`CaptureHandoff`); this process keeps nothing afterwards.
@MainActor
enum ScreenCaptureFlow {
    enum Outcome: Equatable {
        /// Capture N is showing in the Editor.
        case opened(number: Int)
        /// Screen Recording is not granted: nothing was captured and the Permission guide shows.
        case permissionNeeded
        /// Another Capture is still running.
        case busy
        case failed(String)
    }

    @discardableResult
    static func run() async -> Outcome {
        guard CaptureGate.enter() else { return .busy }
        let outcome = await capture()
        CaptureGate.leave()
        // After the gate opens: the guide's window may take a moment to appear, and a second press
        // meanwhile must reach the same check, not a silent `.busy`.
        if outcome == .permissionNeeded { await OnboardingLauncher.screenRecordingMissing() }
        return outcome
    }

    private static func capture() async -> Outcome {
        guard ScreenRecordingPermission.current.isGranted else { return .permissionNeeded }
        // The Capture has started: the Editor helper warms up while the pixels are taken.
        EditorWarmUp.begin()
        do {
            let screen = try await CaptureSources.current.captureDisplayUnderPointer()
            let clock = CaptureTiming.Clock()
            let number = try await CaptureHandoff.publish(screen)
            do {
                try await EditorHelperLauncher.open(capture: number)
            } catch {
                CaptureHandoff.discard(number: number)
                throw error
            }
            clock.stop()
            CaptureHandoff.didOpen(number: number)
            return .opened(number: number)
        } catch {
            EditorWarmUp.cancel()
            NSLog("snapit: Screen Capture failed: \(error)")
            return .failed("\(error)")
        }
    }
}
