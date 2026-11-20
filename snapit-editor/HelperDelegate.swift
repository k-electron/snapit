import AppKit

/// Process-level lifecycle of the Editor helper.
final class HelperDelegate: NSObject, NSApplicationDelegate {
    private var commandServer: CommandSocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started by snapit: serve commands. Anything else (for example a Dock pin)
        // launched the helper on its own: start the menu bar app and quit.
        guard CommandLine.arguments.contains(AppIdentity.startedBySnapitArgument) else {
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

    // The helper quits through its `quit` command or when its last window closes, never before.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
