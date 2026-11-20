import Foundation

/// Holds an Export between taking its snapshot and finishing, so a scripted run can edit the
/// Capture while a Copy or Save is "still running" (as a Save waiting on a folder prompt is) and
/// check that the edit still counts as unexported. Never held outside test mode.
@MainActor
final class ExportTestGate {
    static let shared = ExportTestGate()

    private(set) var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func setHeld(_ held: Bool) {
        isHeld = held && TestMode.isActive
        if !isHeld { release() }
    }

    func wait() async {
        guard isHeld else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        let released = waiters
        waiters = []
        released.forEach { $0.resume() }
    }
}
