import CoreGraphics
import Foundation

/// One Capture's pixels as the system produced them, before they move into engine memory.
nonisolated struct CapturedScreen: @unchecked Sendable {
    /// Native pixels, in the display's color space.
    let image: CGImage
    /// Pixels per point: 2 on a Retina display, 1 otherwise.
    let scale: Double

    /// Test mode only: an object that lives exactly as long as this frame does (every copy of
    /// the struct shares it), so the scripted run can tell when the frame is gone.
    let lifetimeProbe: AnyObject?

    init(image: CGImage, scale: Double) {
        self.image = image
        self.scale = scale
        lifetimeProbe = TestMode.isActive ? NSObject() : nil
    }

    /// The resolution the PNG records: 72 dpi at 1x, 144 on Retina.
    var dpi: Int { Int((72 * scale).rounded()) }
}

/// Where Capture pixels come from. The real source is ScreenCaptureKit; the scripted run
/// swaps in fixture images (`FixtureCaptureSource`). Always go through
/// `CaptureSources.current`.
///
/// A Capture mode that needs a different question (a window, a region of a frozen display)
/// adds its own protocol and `current` in its own file, with a real and a fixture
/// implementation beside it.
@MainActor
protocol CaptureSource {
    /// Captures the whole display under the pointer: native pixels, SDR, in the display's
    /// color space, without the cursor.
    func captureDisplayUnderPointer() async throws -> CapturedScreen
}

@MainActor
enum CaptureSources {
    static let current: any CaptureSource =
        TestMode.isActive ? FixtureCaptureSource.shared : ScreenCaptureKitSource()
}
