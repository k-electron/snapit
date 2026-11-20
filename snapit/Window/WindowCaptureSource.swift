import CoreGraphics

/// Choices a Window Capture makes that the spec leaves open.
enum WindowCapture {
    /// Whether a Window Capture includes the window's shadow. It does not: the Capture is exactly
    /// the window's frame, with transparent rounded corners. One line to flip. Flipping it also
    /// needs the requested size to grow by the shadow's margin (ScreenCaptureKit scales the
    /// window plus its shadow into whatever size is asked for): see docs/manual-checks.md.
    static let includesShadow = false
}

/// Where a Window Capture's pixels come from. The real source is ScreenCaptureKit's one-shot
/// capture through a single-window content filter; the scripted run swaps in a fixture window
/// image with transparent corners (`FixtureWindowCaptureSource`). Always go through
/// `WindowCaptureSources.current`.
@MainActor
protocol WindowCaptureSource {
    /// The overlay is up and the user is choosing: starts whatever the real capture needs (the
    /// list of shareable windows), so the click has less to wait for.
    func prepare()

    /// Lets go of what `prepare` fetched.
    func release()

    /// Captures `window` alone, at the display's native pixels, SDR, in the display's color space,
    /// without the cursor and without whatever is in front of it. Pixels are premultiplied BGRA:
    /// the window's rounded corners are transparent.
    func captureWindow(_ window: OnScreenWindow) async throws -> CapturedScreen
}

@MainActor
enum WindowCaptureSources {
    static let current: any WindowCaptureSource =
        TestMode.isActive ? FixtureWindowCaptureSource.shared : ScreenCaptureKitWindowSource()
}
