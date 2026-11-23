import Foundation

/// The Last Capture's Editor keeps its state file current (`LastCapturePersistence`). Every other
/// Editor keeps its Capture in memory only.
extension EditorSession {
    /// True while this Editor is the Last Capture's.
    var isLastCapture: Bool { lastCapture != nil }

    /// Makes this Editor the Last Capture's. A new generation starts, so anything an earlier Last
    /// Capture's Editor queued is dropped, and this Editor's changes are stored from now on.
    func becomeLastCapture() {
        guard let document else { return }
        lastCapture?.stop()
        let generation = LastCaptureStore.shared.supersede()
        let persistence = LastCapturePersistence(document: document, generation: generation)
        lastCapture = persistence
        document.onPersistableChange = { [weak persistence] in persistence?.documentDidChange() }
    }

    /// A newer Capture replaced this one as the Last Capture: it is now in memory only.
    func stopBeingLastCapture() {
        lastCapture?.stop()
        lastCapture = nil
        document?.onPersistableChange = nil
    }

    /// Writes the state file now when a change is still waiting for its delay. The Editor goes on
    /// being the Last Capture's.
    func writeLastCaptureNow() {
        lastCapture?.flush()
    }

    /// The Editor is closing: the Last Capture's Editor writes its state one last time, so
    /// Reopen brings it back exactly as it was. Never asks anything.
    func saveLastCaptureOnClose() {
        lastCapture?.close()
        lastCapture = nil
        document?.onPersistableChange = nil
    }
}
