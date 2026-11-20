import AppKit

/// Process-level lifecycle of the Editor helper.
final class HelperDelegate: NSObject, NSApplicationDelegate {
    private var commandServer: CommandSocketServer?

    func applicationWillFinishLaunching(_ notification: Notification) {
        HelperMainMenu.install(quitTarget: self, quitAction: #selector(quitSnapit(_:)))
    }

    /// "Quit snapit" in the helper's menu quits snapit, not just the helper: to the user there
    /// is one app. The menu bar app quits the helper with it.
    @objc func quitSnapit(_ sender: Any?) {
        CommandSocketClient.sendBeforeExit(.quit, to: AppIdentity.appSocketPath)
        NSApplication.shared.terminate(nil)
    }

    /// LaunchServices re-opens the running helper when the menu bar app brings it forward;
    /// that must not make anything of its own happen.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Stop answering first: a menu bar app that sends a Capture from here on starts a
        // new helper instead of handing it to this dying one.
        commandServer?.stop()
        commandServer = nil
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        commandServer?.stop()
    }

    /// The helper quits when its last window closes. Before any window has shown (a helper
    /// started with `start-editor`, or warming up) it stays.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        HelperLifecycle.hasShownWindow
    }
}
