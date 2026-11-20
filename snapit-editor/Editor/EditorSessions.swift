import AppKit

/// The Editors open in the helper, by Capture number. Opening the first one turns the helper
/// into a regular app (Dock icon, Cmd-Tab, its own menus); the helper quits when the last
/// window closes (`HelperDelegate`).
@MainActor
final class EditorSessions {
    static let shared = EditorSessions()

    private(set) var sessions: [Int: EditorSession] = [:]

    /// Numbers of the open Editors, lowest first.
    var captureNumbers: [Int] { sessions.keys.sorted() }

    func session(captureNumber: Int) -> EditorSession? { sessions[captureNumber] }

    /// Opens Capture N in an Editor, or brings its Editor forward when it is already open.
    func open(captureNumber: Int) throws {
        if let existing = sessions[captureNumber] {
            existing.bringForward()
            return
        }
        let capture = try CaptureFiles.open(number: captureNumber)
        let session = EditorSession(document: EditorDocument(captureNumber: captureNumber, capture: capture))
        session.onClosed = { [weak self] closed in
            self?.sessions[closed.document.captureNumber] = nil
        }
        sessions[captureNumber] = session

        HelperLifecycle.windowWillShow()
        session.show()
        HelperLifecycle.windowDidShow()
    }
}
