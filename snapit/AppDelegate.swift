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
            // Capture files left by a crashed run are of no use to anyone.
            CaptureHandoff.removeAll()
            // Only the copy that owns the menu bar listens for Shortcuts.
            ShortcutBindings.registerAll()
            SocketOwnership.adopt(server)
            // Where this copy runs from: a mounted disk image or a translocated path needs a move.
            Task { await InstallCheck.runAtLaunch() }
        } catch SocketError.alreadyRunning {
            // Another snapit owns the menu bar; this copy has nothing to do.
            NSApplication.shared.terminate(nil)
        } catch {
            NSLog("snapit: command socket failed to start: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A copy that never owned the menu bar must not free the owner's private pasteboard or
        // remove the owner's Capture files.
        if commandServer != nil {
            AppPasteboard.releaseIfPrivate()
            CaptureHandoff.removeAll()
        }
        commandServer?.stop()
        // The Editor helper never outlives the menu bar app. The process is ending, so a
        // short blocking send is fine here.
        CommandSocketClient.sendBeforeExit(.quit, to: AppIdentity.editorSocketPath)
    }
}
