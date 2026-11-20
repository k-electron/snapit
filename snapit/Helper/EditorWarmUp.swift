import Foundation

/// Warms the Editor helper up while a Capture is being taken, so the Editor appears about 50 ms
/// after the Capture.
///
/// Every Capture mode calls `begin()` the moment it starts (its Shortcut was pressed and its UI,
/// if any, appears) and `cancel()` if it ends without a Capture. Opening the Capture
/// (`EditorHelperLauncher.open`) uses the warm helper and ends the warm-up itself.
///
/// `begin()` never waits: it starts the helper hidden (an agent, no Dock icon, no window) and
/// tells it to build an Editor. `cancel()` makes a helper that never showed anything quit, so no
/// helper process exists at rest. The helper work runs in order, so a `cancel()` right after a
/// `begin()` still reaches the helper once it is up.
@MainActor
enum EditorWarmUp {
    enum State: String {
        /// No warm-up in progress.
        case idle
        /// The helper is starting or building its Editor.
        case starting
        /// The helper has an Editor built, hidden.
        case warm
    }

    private(set) static var state = State.idle
    private static var generation = 0
    private static var tail: Task<Void, Never>?

    static var isWarm: Bool { state == .warm }

    /// A Capture started: start the helper hidden and have it prepare an Editor. Does nothing
    /// when a warm-up is already under way.
    static func begin() {
        guard state == .idle else { return }
        state = .starting
        generation += 1
        let mine = generation
        enqueue {
            let ready = await prepare()
            if generation == mine && state == .starting { state = ready ? .warm : .idle }
        }
    }

    /// The Capture ended without a Capture: the helper throws its Editor away and, when it never
    /// showed a window, quits.
    static func cancel() {
        guard state != .idle else { return }
        state = .idle
        generation += 1
        enqueue { await release() }
    }

    /// Waits for the warm-up in progress to finish, so a Capture opens in the helper that was
    /// started for it instead of starting another.
    static func settle() async {
        await tail?.value
    }

    /// The Capture opened in the warm Editor: the warm-up is over.
    static func didOpen() {
        state = .idle
        generation += 1
    }

    private static func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Starts the helper when it is not running and has it build an Editor. A helper that is
    /// quitting (a cancel just before) is replaced by a new one. Bounded: only runs during a Capture.
    private static func prepare() async -> Bool {
        for _ in 0..<5 {
            do {
                try await EditorHelperLauncher.ensureRunning(activates: false, warm: true)
                let reply = try await CommandSocketClient.send(.warmUp, to: AppIdentity.editorSocketPath)
                if reply == "ok" { return true }
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                NSLog("snapit: Editor warm-up failed: \(error)")
                return false
            }
        }
        return false
    }

    /// Tells a running helper the Capture was cancelled. Never starts a helper to say so.
    private static func release() async {
        guard await CommandSocketClient.isListening(at: AppIdentity.editorSocketPath) else { return }
        _ = try? await CommandSocketClient.send(.cancelWarmUp, to: AppIdentity.editorSocketPath)
    }
}
