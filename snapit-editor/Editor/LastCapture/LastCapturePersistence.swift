import Foundation

/// Keeps the Last Capture's state file current for the Editor that edits it.
///
/// The Editor works in memory. About half a second after a change (a one-shot delay that the
/// first change starts and later changes ride along with, never a repeating timer) it hands the
/// store a snapshot of the history, and it hands it one more when the Editor closes. A snapshot is
/// skipped when the revision and the exported flag are the same as the last one written. The
/// writes are made under the generation the Editor became the Last Capture with, so once a newer
/// Capture or Delete Capture supersedes it nothing it queued can land.
@MainActor
final class LastCapturePersistence {
    /// How long after a change the state file is written.
    static let delay: TimeInterval = 0.5

    private struct Key: Equatable {
        let revision: Int
        let exported: Bool
    }

    let number: Int
    private let generation: Int
    private let store: LastCaptureStore
    private unowned let document: EditorDocument
    /// The revision and exported flag of the state file as it is now (or would be: a Capture with
    /// no state file starts at an untouched one).
    private var lastKey: Key?
    private var pending: DispatchWorkItem?
    private var isStopped = false

    init(document: EditorDocument, generation: Int, store: LastCaptureStore = .shared) {
        self.document = document
        self.generation = generation
        self.store = store
        number = document.captureNumber
        lastKey = Key(revision: document.revision, exported: !document.hasUnexportedChanges)
    }

    private var currentKey: Key { Key(revision: document.revision, exported: !document.hasUnexportedChanges) }

    /// The history or the exported flag changed: schedule the write, unless nothing is different
    /// or one is already scheduled.
    func documentDidChange() {
        guard !isStopped, pending == nil, currentKey != lastKey else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pending = nil
            write(wait: false)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: item)
    }

    /// The Editor is closing: writes the final state now (the helper may quit right after).
    func close() {
        guard !isStopped else { return }
        pending?.cancel()
        pending = nil
        write(wait: true)
        isStopped = true
    }

    /// This Editor is no longer the Last Capture's: nothing more is written.
    func stop() {
        pending?.cancel()
        pending = nil
        isStopped = true
    }

    private func write(wait: Bool) {
        let key = currentKey
        guard key != lastKey else { return }
        let state = LastCaptureState(history: document.history, exported: key.exported)
        let previous = lastKey
        lastKey = key
        if wait {
            _ = store.writeNow(state, number: number, generation: generation)
        } else {
            store.enqueue(state, number: number, generation: generation) { [weak self] outcome in
                // A write that failed is tried again at the next change.
                if outcome == .failed, self?.lastKey == key { self?.lastKey = previous }
            }
        }
    }
}
