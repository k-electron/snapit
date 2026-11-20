import AppKit

extension SocketCommandRegistry {
    /// The commands the menu bar app sends the Editor helper when a Capture starts or is cancelled.
    func registerWarmUpCommands() {
        // `warm-up [<menu bar app pid>]`: the pid is the app the helper quits with while it has
        // shown nothing; a restarted snapit that adopts a running helper sends its own.
        register(.warmUp) { request in
            WarmHelper.warmUp(menuBarPID: request.arguments.first.flatMap { pid_t($0) })
            return "ok"
        }
        register(.cancelWarmUp) { _ in
            EditorSessions.shared.cancelWarmUp()
            // A helper that never showed a window has nothing left to do: quit, so no helper
            // process exists at rest. One with an Editor open stays.
            WarmHelper.quitIfNothingOpen()
            return "ok"
        }
    }
}
