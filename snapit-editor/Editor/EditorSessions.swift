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

    /// The Editor of the Last Capture, when it is open.
    private(set) var lastCaptureSession: EditorSession?

    /// Opens Capture N, just taken, in an Editor, or brings its Editor forward when it is already
    /// open. It becomes the Last Capture: the Editor before it keeps its Capture in memory only.
    func open(captureNumber: Int) throws {
        ExportFiles.removeStaleDragOut()
        if let existing = sessions[captureNumber] {
            existing.bringForward()
            return
        }
        let capture = try CaptureFiles.open(number: captureNumber)
        show(
            EditorDocument(captureNumber: captureNumber, capture: capture), in: warm ?? EditorSession())
        warm = nil
    }

    /// Reopens the Last Capture, Capture N: its pixels from the Capture file, mapped as they are,
    /// and its Annotations, crop and Undo history from the state file. An Editor already open for
    /// it comes forward. Throws when the stored Capture is damaged.
    func reopen(captureNumber: Int) throws {
        ExportFiles.removeStaleDragOut()
        if let existing = sessions[captureNumber] {
            existing.bringForward()
            return
        }
        let capture = try CaptureFiles.open(number: captureNumber)
        // No state file is not damage: the Editor writes one only after the first change.
        let stored = try LastCaptureStateFile.read(number: captureNumber)
        let document = EditorDocument(
            captureNumber: captureNumber, capture: capture, history: stored?.history ?? AnnotationHistory(),
            exported: stored?.exported ?? false)
        show(document, in: EditorSession())
    }

    private func show(_ document: EditorDocument, in session: EditorSession) {
        let number = document.captureNumber
        lastCaptureSession?.stopBeingLastCapture()
        session.onClosed = { [weak self] closed in
            self?.sessions[number] = nil
            if self?.lastCaptureSession === closed { self?.lastCaptureSession = nil }
        }
        session.attach(document)
        session.becomeLastCapture()
        sessions[number] = session
        lastCaptureSession = session

        HelperLifecycle.windowWillShow()
        session.show()
        HelperLifecycle.windowDidShow()
    }
}
