import AppKit

extension SocketCommandRegistry {
    /// The commands the menu bar app sends the Editor helper when a Capture starts or is cancelled.
    func registerWarmUpCommands() {
        register(.warmUp) { _ in
            guard !HelperLifecycle.isQuitting else { return "error the helper is quitting" }
            EditorSessions.shared.warmUp()
            return "ok"
        }
        register(.cancelWarmUp) { _ in
            EditorSessions.shared.cancelWarmUp()
            // A helper that never showed a window has nothing left to do: quit, so no helper
            // process exists at rest. One with an Editor open stays.
            if !HelperLifecycle.hasShownWindow && EditorSessions.shared.sessions.isEmpty {
                HelperLifecycle.isQuitting = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApplication.shared.terminate(nil) }
            }
            return "ok"
        }
    }
}
