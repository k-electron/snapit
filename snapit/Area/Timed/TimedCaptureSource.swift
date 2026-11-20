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
    /// The window's level, which is its layer in the window list.
    let layer: Int
    let kind: Kind
}

/// What a fresh Capture leaves out of the screen. The content filter excludes snapit's whole
/// application, so a window that opens after the list was fetched (the ✕'s tooltip) is out too;
/// only its menu bar icon, which is part of the screen, stays in.
///
/// `plan` is the one function that decides this: the real source builds its `SCContentFilter` from
/// it and the scripted run's fixture decides what to paint from it, so a run tests the real
/// decision.
nonisolated enum OwnWindowExclusion: Equatable {
    /// Exclude snapit's application, except these windows (by number).
    case application(excepting: Set<Int>)
    /// snapit's application is not in the shareable content (the system has not listed it yet), so
    /// a filter cannot name it: its windows go off screen first and the content is fetched again.
    case hideWindows

    struct Window: Equatable {
        let number: Int
        let layer: Int
    }

    /// `ownWindows` are snapit's windows in the content; `applicationListed` is whether snapit's
    /// application is.
    static func plan(applicationListed: Bool, ownWindows: [Window]) -> OwnWindowExclusion {
        guard applicationListed else { return .hideWindows }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        return .application(excepting: Set(ownWindows.filter { $0.layer == statusLayer }.map(\.number)))
    }

    /// True when a window of snapit's is kept out of the Capture.
    func excludes(_ window: Window) -> Bool {
        switch self {
        case .application(let excepting): !excepting.contains(window.number)
        case .hideWindows: true
        }
    }
}

/// What a fresh Capture at zero is asked for: the display the Area is on.
struct FreshCaptureRequest {
    let displayID: CGDirectDisplayID
    /// The display's frame in AppKit's global space.
    let displayFrame: CGRect
    /// snapit's windows on screen now: the border, the badge and its tooltip.
    let ownWindows: [OwnWindow]
}

/// Where a Timed Capture's pixels come from at zero: a new one-shot Capture of the whole display,
/// never the frozen frame the Area was chosen on, with snapit's own windows excluded through the
/// content filter (`OwnWindowExclusion`). The real source is ScreenCaptureKit; the scripted run
/// swaps in a fixture whose frames change per call (`FixtureTimedCaptureSource`). Always go
/// through `TimedCaptureSources.current`.
@MainActor
protocol TimedCaptureSource {
    /// Takes the Capture. `hideOwnWindows` takes snapit's windows off screen; a source calls it
    /// only when it cannot exclude them by filter (the system has not listed snapit yet).
    func captureFresh(_ request: FreshCaptureRequest, hideOwnWindows: @MainActor () -> Void) async throws
        -> CapturedScreen
}

@MainActor
enum TimedCaptureSources {
    static let current: any TimedCaptureSource =
        TestMode.isActive ? FixtureTimedCaptureSource.shared : ScreenCaptureKitTimedSource()
}
