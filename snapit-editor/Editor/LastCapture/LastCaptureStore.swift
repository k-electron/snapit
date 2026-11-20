import Darwin
import Foundation
import os

/// Writes the Last Capture's state file, off the main thread.
///
/// Every write goes through one serial queue, so two writes never overlap, and each carries the
/// generation it was made under. The generation is bumped on the main thread (`supersede()`)
/// when a new Capture becomes the Last Capture, when the Capture is deleted and when snapit quits;
/// a write that was queued under an older generation is dropped when its turn comes, and checked
/// again just before its rename. `fence()` waits until everything queued so far has run, so the
/// helper can tell the menu bar app "done" only when no stale write can still land. The menu bar
/// app removes the Capture's files after that.
nonisolated final class LastCaptureStore: Sendable {
    static let shared = LastCaptureStore()

    /// How a queued write ended.
    enum Outcome: Sendable {
        case written
        /// Superseded (a newer Capture, Delete Capture, quit) or its Capture's files are gone.
        case dropped
        case failed
    }

    private struct Counters {
        var generation = 0
        var written = 0
        var dropped = 0
        var held = false
    }

    private let counters = OSAllocatedUnfairLock(initialState: Counters())
    private let queue = DispatchQueue(label: "dev.snapit.last-capture-state", qos: .utility, autoreleaseFrequency: .workItem)
    /// Test mode: a write waits here while `held`.
    private let gate = NSCondition()

    var generation: Int { counters.withLock { $0.generation } }
    /// State files written by this process.
    var writtenCount: Int { counters.withLock { $0.written } }
    /// Queued writes that were dropped because they were stale.
    var droppedCount: Int { counters.withLock { $0.dropped } }

    /// A new generation: every write made under an earlier one is dropped. Returns the new one.
    @discardableResult
    func supersede() -> Int {
        counters.withLock {
            $0.generation += 1
            return $0.generation
        }
    }

    /// Queues the write of `state` as Capture N's state file, made under `generation`. `completion`
    /// runs on the main actor.
    func enqueue(
        _ state: LastCaptureState, number: Int, generation: Int,
        completion: @escaping @MainActor @Sendable (Outcome) -> Void
    ) {
        queue.async { [self] in
            let outcome = perform(state, number: number, generation: generation)
            Task { @MainActor in completion(outcome) }
        }
    }

    /// Writes now and waits (the Editor is closing, and the helper may quit as soon as its last
    /// window has closed).
    @discardableResult
    func writeNow(_ state: LastCaptureState, number: Int, generation: Int) -> Outcome {
        queue.sync { perform(state, number: number, generation: generation) }
    }

    /// Reads and decodes Capture N's state file on the queue, after every write queued before this
    /// call (see `LastCaptureStateFile.read`).
    func read(number: Int) async throws -> LastCaptureState? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try LastCaptureStateFile.read(number: number) }) }
        }
    }

    /// Returns once every write queued before this call has run or been dropped.
    func fence() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    private func perform(_ state: LastCaptureState, number: Int, generation: Int) -> Outcome {
        waitWhileHeld()
        guard self.generation == generation else { return count(.dropped) }
        let pixels = CaptureFiles.url(number: number).path
        guard access(pixels, F_OK) == 0 else { return count(.dropped) }
        do {
            let data = try LastCaptureStateFile.encode(state)
            let wanted = try LastCaptureStateFile.write(data, number: number) {
                self.generation == generation && access(pixels, F_OK) == 0
            }
            return count(wanted ? .written : .dropped)
        } catch {
            NSLog("snapit Editor: could not write the Last Capture's state: \(error)")
            return .failed
        }
    }

    private func count(_ outcome: Outcome) -> Outcome {
        counters.withLock {
            if outcome == .written { $0.written += 1 }
            if outcome == .dropped { $0.dropped += 1 }
        }
        return outcome
    }

    // MARK: Test mode

    /// Holds every write (the queue blocks in front of it) until released, so a run can make a
    /// write stale while it waits. Test mode only.
    func setHeld(_ held: Bool) {
        gate.lock()
        counters.withLock { $0.held = held }
        gate.broadcast()
        gate.unlock()
    }

    private func waitWhileHeld() {
        gate.lock()
        while counters.withLock({ $0.held }) { gate.wait() }
        gate.unlock()
    }
}
