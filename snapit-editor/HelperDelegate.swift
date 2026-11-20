import AppKit

/// Process-level lifecycle of the Editor helper.
final class HelperDelegate: NSObject, NSApplicationDelegate {
    private var commandServer: CommandSocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched on its own (for example from a Dock pin): start the menu bar app and quit.
        guard CommandSocketClient.isListening(at: AppIdentity.appSocketPath) else {
            MenuBarAppLauncher.startMenuBarAppThenQuit()
            return
        }

        let registry = SocketCommandRegistry()
        registry.registerBuiltinCommands()
        registry.registerHelperCommands()

        let server = CommandSocketServer(path: AppIdentity.editorSocketPath, registry: registry)
        do {
            try server.start()
            commandServer = server
        } catch {
            NSLog("snapit Editor: command socket failed to start: \(error)")
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandServer?.stop()
    }

    // The helper quits when its last window closes (a later feature), never before.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
