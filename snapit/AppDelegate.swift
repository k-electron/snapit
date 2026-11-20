import AppKit

/// Owns the menu bar app's process-level lifecycle: its command socket and the helper's quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var commandServer: CommandSocketServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Whether macOS has snapit granted Screen Recording is recorded now: it can use the grant only from
        // its next launch on.
        _ = ScreenRecordingPermission.current
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
            SaveFailureNotice.register()
            SocketOwnership.adopt(server)
            // Where this copy runs from: a mounted disk image or a translocated path needs a move.
            Task {
                let outcome = await InstallCheck.runAtLaunch()
                LoginItemDefault.applyIfEligible()
                // Onboarding (or the update's Permission guide) only once this copy is where it
                // belongs: a Move to Applications screen, or a relaunch in place, comes first and the
                // relaunched copy follows. A copy macOS has not approved yet is left where it is.
                if outcome != .moveScreenShown && outcome != .fixedInPlace { await OnboardingLauncher.runAtLaunch() }
            }
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
        // Quitting for good from here on (the quit has been agreed to): a Save that fails while the last ones finish
        // opens no window. A quit that is deferred or cancelled later must set this back to false.
        SaveFailureNotice.isQuitting = true
        return wait ? .terminateLater : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A copy that never owned the menu bar owns nothing: it must not quit the owner's Editor
        // helper, free the owner's private pasteboard or remove the owner's Capture files.
        guard commandServer != nil else { return }
        // The Editor helper never outlives the menu bar app. The process is ending, so a short
        // blocking send is fine here. It goes first: the helper stops writing the Last Capture's
        // state before it answers, so nothing recreates a file after the removal below.
        // Only a helper that is this copy's: one it started, or one whose owner is gone (a crashed copy's)
        // that this copy has been using. A relaunched copy may be serving a helper of its own on that socket.
        if HelperOwnership.isOurs(CommandSocketClient.queryBeforeExit(.helperOwner, to: AppIdentity.editorSocketPath)) {
            CommandSocketClient.sendBeforeExit(.quit, to: AppIdentity.editorSocketPath)
        }
        AppPasteboard.releaseIfPrivate()
        CaptureHandoff.removeAll()
        ExportFiles.removeAll()
        commandServer?.stop()
    }
}
