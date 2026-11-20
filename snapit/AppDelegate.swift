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
        } catch SocketError.alreadyRunning {
            // Another snapit owns the menu bar; this copy has nothing to do.
            NSApplication.shared.terminate(nil)
        } catch {
            NSLog("snapit: command socket failed to start: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandServer?.stop()
        // The Editor helper never outlives the menu bar app. The process is ending, so a
        // short blocking send is fine here.
        CommandSocketClient.sendBeforeExit(.quit, to: AppIdentity.editorSocketPath)
    }
}
