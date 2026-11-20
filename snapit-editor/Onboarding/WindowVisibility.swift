import AppKit

extension NSWindow {
    /// Whether a person can see the window: on screen, not minimised, not completely covered. The
    /// Permission guide's animation plays only while this is true.
    ///
    /// A scripted run never activates the helper (and may run with the display asleep), and macOS then
    /// reports every window as covered, so test mode goes by "on screen and not minimised" alone.
    var isSeenByUser: Bool {
        isVisible && !isMiniaturized && (TestMode.isActive || occlusionState.contains(.visible))
    }
}
