import CoreGraphics

/// One of snapit's own windows that is on screen while a Timed Capture counts down.
struct OwnWindow: Equatable {
    enum Kind: String {
        case border, badge, tooltip
    }

    /// The window's number: the same number is the window server's and ScreenCaptureKit's window ID.
    let number: Int
    /// The window's frame in AppKit's global space.
    let frame: CGRect
    let kind: Kind
}

/// What a fresh Capture at zero is asked for: the display the Area is on, and what to keep out of it.
struct FreshCaptureRequest {
    let displayID: CGDirectDisplayID
    /// The display's frame in AppKit's global space.
    let displayFrame: CGRect
    /// snapit's windows on screen now: the border, the badge and its tooltip.
    let ownWindows: [OwnWindow]
    /// The windows the content filter excludes, by window number.
    let excluding: Set<Int>
}

/// Where a Timed Capture's pixels come from at zero: a new one-shot Capture of the whole display,
/// never the frozen frame the Area was chosen on, with snapit's own windows excluded through the
/// content filter. The real source is ScreenCaptureKit; the scripted run swaps in a fixture whose
/// frames change per call (`FixtureTimedCaptureSource`). Always go through
/// `TimedCaptureSources.current`.
@MainActor
protocol TimedCaptureSource {
    /// Takes the Capture. `hideOwnWindows` takes snapit's windows off screen; a source calls it
    /// only when it cannot exclude them by filter (the system has not listed them yet).
    func captureFresh(_ request: FreshCaptureRequest, hideOwnWindows: @MainActor () -> Void) async throws
        -> CapturedScreen
}

@MainActor
enum TimedCaptureSources {
    static let current: any TimedCaptureSource =
        TestMode.isActive ? FixtureTimedCaptureSource.shared : ScreenCaptureKitTimedSource()
}
