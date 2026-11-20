import AppKit

/// The pasteboard snapit writes Copies to. Always go through `AppPasteboard.current`,
/// never `NSPasteboard.general`.
///
/// Test mode uses a private named pasteboard, derived from the run's root, so the scripted
/// run never touches the user's clipboard and two runs never share one.
enum AppPasteboard {
    static let current: NSPasteboard = {
        guard let runID = TestMode.runID else { return .general }
        return NSPasteboard(name: NSPasteboard.Name("dev.snapit.test.\(runID)"))
    }()

    /// True when `current` is the private test pasteboard.
    static var isPrivate: Bool { current !== NSPasteboard.general }

    /// Puts `data` on the pasteboard as the only item, of the given type.
    static func write(_ data: Data, as type: NSPasteboard.PasteboardType) {
        current.clearContents()
        current.setData(data, forType: type)
    }

    /// Frees the private pasteboard when the process ends. Does nothing for the general one.
    static func releaseIfPrivate() {
        if isPrivate { current.releaseGlobally() }
    }
}
