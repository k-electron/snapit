import Foundation

/// A Screen Capture: the display under the pointer, onto the clipboard as a PNG.
///
/// The Shortcut and the "Capture Screen" menu item both run this. The pixels live in
/// engine-owned memory only while the flow runs; nothing is kept afterwards.
@MainActor
enum ScreenCaptureFlow {
    enum Outcome: Equatable {
        /// The PNG is on the pasteboard.
        case copied(width: Int, height: Int, byteCount: Int)
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
            let encoded = try await encode(screen)
            AppPasteboard.write(encoded.png, as: .png)
            return .copied(width: encoded.width, height: encoded.height, byteCount: encoded.png.count)
        } catch {
            NSLog("snapit: Screen Capture failed: \(error)")
            return .failed("\(error)")
        }
    }

    /// Moves the pixels into engine memory and Fast-encodes them, off the main thread. Both
    /// the pixel buffer and the CGImage are gone when this returns; only the PNG is left.
    @concurrent
    private static func encode(_ screen: CapturedScreen) async throws -> (png: Data, width: Int, height: Int) {
        let pixels = try PixelBuffer(copying: screen.image)
        let png = try pixels.encodePNG(level: .fast, dpi: screen.dpi)
        return (png, pixels.width, pixels.height)
    }
}
