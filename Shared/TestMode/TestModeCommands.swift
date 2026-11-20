import AppKit

nonisolated extension SocketCommand {
    /// Replies with one `key=value` line per test-mode seam, so the scripted run can check
    /// that every edge is the test one before it drives anything.
    static let testSeams = SocketCommand("test-seams")
    /// Replies with the type identifiers on the private pasteboard, one per line.
    static let pasteboardTypes = SocketCommand("pasteboard-types")
    /// `pasteboard-dump-png <path>`: writes the PNG on the private pasteboard to `<path>` (inside
    /// the run's root) and replies `ok <byte count>`.
    static let pasteboardDumpPNG = SocketCommand("pasteboard-dump-png")
    /// `defaults-set <key> <value>`: stores a string through `AppDefaults.store`. Replies `ok`.
    static let defaultsSet = SocketCommand("defaults-set")
    /// `defaults-get <key>`: replies with the string `AppDefaults.store` holds, or `none`. The
    /// scripted run writes in one process and reads in the other to prove they share defaults.
    static let defaultsGet = SocketCommand("defaults-get")
    /// Empties the private pasteboard.
    static let pasteboardClear = SocketCommand("pasteboard-clear")
    /// Sends this process the quit AppleEvent, as the system does at logout and `osascript` does
    /// (a quit nobody was asked about), and replies `ok` at once. Test mode only.
    static let quitEvent = SocketCommand("quit-event")
}

extension SocketCommandRegistry {
    /// The test-mode commands both processes answer. They exist only while test mode is on,
    /// so a normal run exposes nothing that reads the clipboard.
    ///
    /// A feature adds commands for its own edge in its own file (a `register…TestCommands()`
    /// in that feature's target) rather than here.
    func registerTestModeCommands() {
        guard TestMode.isActive else { return }

        register(.engineProbePanic) { _ in
            Engine.probePanic().map { "\($0)" } ?? "unknown"
        }
        register(.echo) { request in
            request.arguments.joined(separator: "\n")
        }
        register(.quitEvent) { _ in
            // After the reply, and from the run loop itself, not from inside a main queue block: the
            // system delivers a quit that way, and a `terminate` made inside a block cannot be answered
            // later (`AppDelegate.applicationShouldTerminate`).
            let mainLoop = CFRunLoopGetMain()
            CFRunLoopPerformBlock(mainLoop, CFRunLoopMode.commonModes.rawValue) {
                let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
                let event = NSAppleEventDescriptor(
                    eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication),
                    targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                    transactionID: AETransactionID(kAnyTransactionID))
                AESendMessage(event.aeDesc!, nil, AESendMode(kAENoReply), kAEDefaultTimeout)
            }
            CFRunLoopWakeUp(mainLoop)
            return "ok"
        }
        register(.testSeams) { _ in
            [
                "root=\(TestMode.root?.path ?? "")",
                "pasteboard=\(AppPasteboard.current.name.rawValue)",
                "save=\(SaveLocation.folder.path)",
                "cache=\(AppIdentity.cacheFolder.path)",
                "permission=\(ScreenRecordingPermission.current.isGranted ? "granted" : "denied")",
            ].joined(separator: "\n")
        }
        register(.pasteboardTypes) { _ in
            (AppPasteboard.current.types ?? []).map(\.rawValue).joined(separator: "\n")
        }
        register(.pasteboardDumpPNG) { request in
            guard let path = request.arguments.first, Self.isInsideRoot(path) else {
                return "error path must be inside the test root"
            }
            guard let data = AppPasteboard.current.data(forType: .png) else {
                return "error no png on the pasteboard"
            }
            do {
                try data.write(to: URL(fileURLWithPath: path))
                return "ok \(data.count)"
            } catch {
                return "error \(error)"
            }
        }
        register(.defaultsSet) { request in
            guard request.arguments.count == 2 else { return "error defaults-set <key> <value>" }
            AppDefaults.store.set(request.arguments[1], forKey: request.arguments[0])
            return "ok"
        }
        register(.defaultsGet) { request in
            guard let key = request.arguments.first else { return "error defaults-get <key>" }
            return AppDefaults.store.string(forKey: key) ?? "none"
        }
        register(.pasteboardClear) { _ in
            AppPasteboard.current.clearContents()
            return "ok"
        }
    }

    private static func isInsideRoot(_ path: String) -> Bool {
        guard let root = TestMode.root?.standardizedFileURL.path else { return false }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardized.hasPrefix(root + "/")
    }
}
