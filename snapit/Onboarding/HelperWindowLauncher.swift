import Foundation

/// Asks the Editor helper to show a window of its own (starting the helper when it is not
/// running). The menu bar app never opens a window itself.
@MainActor
enum HelperWindowLauncher {
    /// Sends `command` and brings the helper forward. Tries twice: a helper that was quitting
    /// when the first send arrived is replaced by a new one. Returns whether the window shows.
    @discardableResult
    static func show(_ command: SocketCommand, arguments: [String] = []) async -> Bool {
        var failure: Error = EditorHelperError.didNotStart
        for _ in 0..<2 {
            do {
                try await EditorHelperLauncher.ensureRunning(activates: EditorActivation.current.activateAtLaunch)
                let reply = try await CommandSocketClient.send(
                    command, arguments: arguments, to: AppIdentity.editorSocketPath, timeoutSeconds: 10)
                guard reply == "ok" else { throw EditorHelperError.refused(reply) }
                await EditorHelperLauncher.bringForward()
                return true
            } catch {
                failure = error
            }
        }
        NSLog("snapit: could not show \(command.name): \(failure)")
        return false
    }
}
