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
        /// Screen Recording is not granted; macOS was asked to show its prompt.
        case permissionNeeded
        /// Another Capture is still running.
        case busy
        case failed(String)
    }

    private static var isRunning = false

    @discardableResult
    static func run() async -> Outcome {
        guard !isRunning else { return .busy }
        isRunning = true
        defer { isRunning = false }
        return await capture()
    }

    private static func capture() async -> Outcome {
        guard ScreenRecordingPermission.current.isGranted else {
            ScreenRecordingPermission.current.request()
            return .permissionNeeded
        }
        do {
            let screen = try await CaptureSources.current.captureDisplayUnderPointer()
            let number = try await CaptureHandoff.publish(screen)
            try await EditorHelperLauncher.open(capture: number)
            return .opened(number: number)
        } catch {
            NSLog("snapit: Screen Capture failed: \(error)")
            return .failed("\(error)")
        }
    }
}
