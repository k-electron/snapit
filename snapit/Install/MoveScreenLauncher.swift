import Foundation

/// Asks the Editor helper to show the "Move snapit to Applications" screen. The menu bar app
/// never opens a window itself.
@MainActor
enum MoveScreenLauncher {
    static func show(reason: String, replaces: String) async throws {
        try await EditorHelperLauncher.ensureRunning(activates: EditorActivation.current.activateAtLaunch)
        let reply = try await CommandSocketClient.send(
            .showMoveToApplications, arguments: [reason, replaces], to: AppIdentity.editorSocketPath,
            timeoutSeconds: 10)
        guard reply == "ok" else { throw EditorHelperError.refused(reply) }
        await EditorHelperLauncher.bringForward()
    }
}
