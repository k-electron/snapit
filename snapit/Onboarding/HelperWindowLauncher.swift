import Foundation

/// Asks the Editor helper to show a window of its own (starting the helper when it is not
/// running). The menu bar app never opens a window itself.
@MainActor
enum HelperWindowLauncher {
    /// Sends `command` and brings the helper forward. Tries twice: a helper that was quitting
    /// when the first send arrived is replaced by a new one. Returns whether the window shows.
    @discardableResult
    static func show(_ command: SocketCommand, arguments: [String] = []) async -> Bool {
        await retireHelperOfAnotherCopy()
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

    /// A helper on the socket that another copy of snapit started and that copy is still running (the old
    /// copy, quitting after a relaunch or a Move to Applications) goes away with that copy: it is told to
    /// quit and waited for, and a helper of this copy starts in its place. A helper whose copy is gone
    /// (it crashed or was killed) is used as it is: its Editors are the user's, and this copy now owns it.
    private static func retireHelperOfAnotherCopy() async {
        let path = AppIdentity.editorSocketPath
        guard let owner = try? await CommandSocketClient.send(.helperOwner, to: path), !HelperOwnership.isOurs(owner)
        else { return }
        await quitRunningHelper()
    }

    /// Tells the helper on the socket to quit and waits (briefly) until its socket is gone.
    static func quitRunningHelper() async {
        let path = AppIdentity.editorSocketPath
        guard await CommandSocketClient.isListening(at: path) else { return }
        _ = try? await CommandSocketClient.send(.quit, to: path)
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline, await CommandSocketClient.isListening(at: path) {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
