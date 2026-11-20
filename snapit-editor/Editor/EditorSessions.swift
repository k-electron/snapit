import AppKit

/// The Editors open in the helper, by Capture number. Opening the first one turns the helper
/// into a regular app (Dock icon, Cmd-Tab, its own menus); the helper quits when the last
/// window closes (`HelperDelegate`).
///
/// A helper that warms up (`warmUp()`) builds one Editor ahead of its Capture, hidden: the
/// window, toolbars and canvas layers. The next `open` gives it the Capture and shows it.
@MainActor
final class EditorSessions {
    static let shared = EditorSessions()

    private(set) var sessions: [Int: EditorSession] = [:]
    /// An Editor built ahead of its Capture, not on screen.
    private(set) var warm: EditorSession?

    /// Numbers of the open Editors, lowest first.
    var captureNumbers: [Int] { sessions.keys.sorted() }

    func session(captureNumber: Int) -> EditorSession? { sessions[captureNumber] }

    /// Builds the next Editor now, without a Capture and without showing anything, so `open`
    /// has only the Capture to map. The helper stays an agent: no Dock icon, no window.
    func warmUp() {
        guard warm == nil else { return }
        let session = EditorSession()
        session.wasWarmedUp = true
        warm = session
    }

    /// Throws the warm Editor away (the Capture was cancelled).
    func cancelWarmUp() {
        warm?.discard()
        warm = nil
    }

    /// Opens Capture N in an Editor, or brings its Editor forward when it is already open.
    func open(captureNumber: Int) throws {
        ExportFiles.removeStaleDragOut()
        if let existing = sessions[captureNumber] {
            existing.bringForward()
            return
        }
        let capture = try CaptureFiles.open(number: captureNumber)
        let session = warm ?? EditorSession()
        warm = nil
        session.onClosed = { [weak self] _ in self?.sessions[captureNumber] = nil }
        session.attach(EditorDocument(captureNumber: captureNumber, capture: capture))
        sessions[captureNumber] = session

        HelperLifecycle.windowWillShow()
        session.show()
        HelperLifecycle.windowDidShow()
    }
}
