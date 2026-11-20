import SwiftUI

/// What a Permission guide's window shows: the Screen Recording guide (`PermissionGuideModel`) and
/// the folder guide (`FolderGuideModel`). `PermissionGuideWindow` hosts any of them, one window per
/// kind, and the scripted run's `guide-…` commands read and press whichever it names.
@MainActor
protocol GuideContent: AnyObject {
    var kind: PermissionGuideKind { get }
    var windowTitle: String { get }
    /// The permission is in place: the window's own button says Done instead of Close.
    var isResolved: Bool { get }
    var closeTooltip: String { get }
    /// The guide is on the page its window shows.
    var isShown: Bool { get set }
    /// The window is on screen: not hidden, minimised or fully covered.
    var isVisible: Bool { get set }
    /// Asked to close its own window (the guide has done its job).
    var onFinished: (() -> Void)? { get set }
    /// The window became active (or the guide just appeared in an active window).
    func windowBecameActive() async
    /// The window lost focus.
    func windowResigned()
    /// Does what the button with this id does; false when there is none.
    func press(_ id: String) async -> Bool
    /// What the scripted run reads of the guide: `key=value` lines, then `button <id>|<title>|<tooltip>`.
    func facts() -> [String]
    func makeView() -> AnyView
}
