import AppKit

/// Owns the menu bar app's process-level lifecycle: its command socket and the helper's quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var commandServer: CommandSocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let registry = SocketCommandRegistry()
        registry.registerBuiltinCommands()
        registry.registerAppCommands()

        let server = CommandSocketServer(path: AppIdentity.appSocketPath, registry: registry)
        do {
            try server.start()
            commandServer = server
        } catch {
            NSLog("snapit: command socket failed to start: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Editor helper never outlives the menu bar app.
        if CommandSocketClient.isListening(at: AppIdentity.editorSocketPath) {
            _ = try? CommandSocketClient.send(.quit, to: AppIdentity.editorSocketPath)
        }
        commandServer?.stop()
    }
}
