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
            ExportFiles.removeAll()
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

    /// A Save the user already made still lands when they quit: quitting waits for the write.
    ///
    /// The reply is queued on the main run loop in the common modes. `reply(toApplicationShouldTerminate:)`
    /// through `DispatchQueue.main.async` never runs when `terminate` was called from inside a main
    /// queue block (which is how the socket `quit` calls it).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let wait = SaveService.shared.waitForSavesBeforeQuit {
            let mainLoop = CFRunLoopGetMain()
            CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue) {
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
            CFRunLoopWakeUp(mainLoop)
        }
        return wait ? .terminateLater : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A copy that never owned the menu bar must not free the owner's private pasteboard or
        // remove the owner's Capture files.
        if commandServer != nil {
            AppPasteboard.releaseIfPrivate()
            CaptureHandoff.removeAll()
            ExportFiles.removeAll()
        }
        commandServer?.stop()
        // The Editor helper never outlives the menu bar app. The process is ending, so a
        // short blocking send is fine here.
        CommandSocketClient.sendBeforeExit(.quit, to: AppIdentity.editorSocketPath)
    }
}
