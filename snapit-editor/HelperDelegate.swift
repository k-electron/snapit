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
        // An Editor with unexported edits is asked about first (the user may keep snapit open). The
        // same preparation the `quit` command makes (the Last Capture stops writing its state) goes
        // next; the menu bar app then removes the files and quits the helper.
        Task {
            guard await QuitPreparation.confirm() else { return }
            await QuitPreparation.run()
            CommandSocketClient.sendBeforeExit(.quit, to: AppIdentity.appSocketPath)
            NSApplication.shared.terminate(nil)
        }
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
            if CommandLine.arguments.contains(AppIdentity.warmArgument) { WarmHelper.warmUp(menuBarPID: WarmHelper.launchPID) }
        } catch {
            NSLog("snapit Editor: command socket failed to start: \(error)")
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // A quit that nobody has been asked about (the Dock's Quit, a logout, an AppleEvent) with
        // Editors holding unexported edits is "Quit snapit": the same question, the same preparation,
        // and the menu bar app quits with the helper. The system waits for the answer, so a logout
        // the user cancels is cancelled. The helper's own quits (the last window closed, a warm-up
        // cancelled, the `quit` command) have asked already or have nothing to ask about.
        if !QuitPreparation.hasRun, !EditorSessions.shared.editorsAtRisk().isEmpty {
            Task {
                let agreed = await QuitPreparation.confirm()
                if agreed {
                    await QuitPreparation.run()
                    stopServing()
                    CommandSocketClient.sendBeforeExit(.quit, to: AppIdentity.appSocketPath)
                }
                let mainLoop = CFRunLoopGetMain()
                CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue) {
                    NSApplication.shared.reply(toApplicationShouldTerminate: agreed)
                }
                CFRunLoopWakeUp(mainLoop)
            }
            return .terminateLater
        }
        // Stop answering first: a menu bar app that sends a Capture from here on starts a
        // new helper instead of handing it to this dying one.
        stopServing()
        return .terminateNow
    }

    /// Stops answering commands and removes the socket. A connection already accepted still gets
    /// its reply.
    func stopServing() {
        commandServer?.stop()
        commandServer = nil
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
