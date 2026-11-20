import Foundation

/// Asks the Editor helper to show Settings (starting it when it is not running). The menu bar
/// app never opens a window itself.
@MainActor
enum SettingsLauncher {
    static func show() async {
        do {
            try await EditorHelperLauncher.ensureRunning(activates: EditorActivation.current.activateAtLaunch)
            let reply = try await CommandSocketClient.send(
                .showSettings, to: AppIdentity.editorSocketPath, timeoutSeconds: 10)
            guard reply == "ok" else { throw EditorHelperError.refused(reply) }
            await EditorHelperLauncher.bringForward()
        } catch {
            NSLog("snapit: could not show Settings: \(error)")
        }
    }
}
