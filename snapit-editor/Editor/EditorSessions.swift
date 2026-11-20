import AppKit

/// Why a Reopen did nothing.
enum ReopenError: Error {
    /// A newer Capture is the Last Capture now, or the Capture was deleted.
    case superseded
}

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
    /// The highest Capture number any Editor was made the Last Capture's for. Capture numbers only
    /// grow, so a Reopen of a lower one that has no Editor open is out of date.
    private var newestLastCaptureNumber = 0
    private var deletedNumbers: Set<Int> = []

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
    ///
    /// Throws `ReopenError.superseded` when a newer Capture has become the Last Capture since the
    /// menu bar app asked (Capture numbers only grow), or Capture N was deleted: reopening it would
    /// demote the new Last Capture, and the menu bar app is about to remove N's files.
    func reopen(captureNumber: Int) async throws {
        ExportFiles.removeStaleDragOut()
        if bringForwardIfOpen(captureNumber) { return }
        try ensureNotSuperseded(captureNumber)
        let capture = try CaptureFiles.open(number: captureNumber)
        // No state file is not damage: the Editor writes one only after the first change. It is
        // read and decoded on the store's queue, after any write queued before it.
        let stored = try await LastCaptureStore.shared.read(number: captureNumber)
        // Time has passed: another Capture or a Delete may have happened meanwhile.
        if bringForwardIfOpen(captureNumber) { return }
        try ensureNotSuperseded(captureNumber)
        let document = EditorDocument(
            captureNumber: captureNumber, capture: capture, history: stored?.history ?? AnnotationHistory(),
            exported: stored?.exported ?? false)
        show(document, in: EditorSession())
    }

    /// Capture N is being deleted: a Reopen that is already on its way must not report it damaged.
    func markDeleted(captureNumber: Int) {
        deletedNumbers.insert(captureNumber)
    }

    private func bringForwardIfOpen(_ number: Int) -> Bool {
        guard let existing = sessions[number] else { return false }
        existing.bringForward()
        return true
    }

    private func ensureNotSuperseded(_ number: Int) throws {
        if number < newestLastCaptureNumber || deletedNumbers.contains(number) { throw ReopenError.superseded }
    }

    private func show(_ document: EditorDocument, in session: EditorSession) {
        let number = document.captureNumber
        newestLastCaptureNumber = max(newestLastCaptureNumber, number)
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
