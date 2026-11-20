import CoreGraphics

/// One display, frozen: what the Area overlay shows while the user selects, and what the engine
/// crops afterwards. Its pixels are the one-shot capture itself, shared by the overlay's layers and
/// the loupe; nothing copies them, so they go when the overlay lets go of them.
struct FrozenDisplay {
    /// The display's `CGDirectDisplayID` (a fixed fake one for each fixture display in test mode).
    let displayID: CGDirectDisplayID
    /// The display's frame in AppKit's global space (points, origin at the bottom left of the
    /// primary display).
    let frame: CGRect
    /// The display's top-left corner in the global space the window list uses (points, origin at
    /// the top left of the primary display).
    let cgOrigin: CGPoint
    /// Native pixels, SDR, in the display's color space.
    let screen: CapturedScreen

    var image: CGImage { screen.image }
    /// Pixels per point.
    var scale: Double { screen.scale }
    /// The display's size in points, with its origin at the top left (the overlay's own space).
    var bounds: CGRect { CGRect(origin: .zero, size: frame.size) }
}

/// Where the Area overlay's frozen frames come from. The real source is ScreenCaptureKit's
/// one-shot capture of every display; the scripted run swaps in fixture images
/// (`FixtureAreaCaptureSource`, built on the same fixture as `FixtureCaptureSource`). Always go
/// through `AreaCaptureSources.current`.
@MainActor
protocol AreaCaptureSource {
    /// Freezes every display at once: one capture each, native pixels, SDR, in the display's
    /// color space, without the cursor, without snapit's own windows. Never a stream.
    func freezeDisplays() async throws -> [FrozenDisplay]

    /// Where the pointer is now, in AppKit's global space.
    var pointerLocation: CGPoint { get }
}

@MainActor
enum AreaCaptureSources {
    static let current: any AreaCaptureSource =
        TestMode.isActive ? FixtureAreaCaptureSource.shared : ScreenCaptureKitAreaSource()
}
