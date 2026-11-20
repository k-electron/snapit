import AppKit

extension SocketCommandRegistry {
    /// The commands the menu bar app sends the Editor helper about Captures.
    func registerEditorCommands() {
        register(.openCapture) { request in
            guard let number = request.arguments.first.flatMap(Int.init) else { return "error open-capture <number>" }
            do {
                try EditorSessions.shared.open(captureNumber: number)
                // The window is on screen when the reply goes out, not just ordered front.
                CATransaction.flush()
                return "ok"
            } catch {
                // A helper that never showed a window has nothing left to do: quit rather than
                // sit there with no window and no way for the user to close it.
                if !HelperLifecycle.hasShownWindow {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NSApplication.shared.terminate(nil) }
                }
                return "error \(error)"
            }
        }
    }
}
