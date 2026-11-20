import AppKit

enum EditorHelperError: Error, CustomStringConvertible {
    case didNotStart
    case refused(String)

    var description: String {
        switch self {
        case .didNotStart: "the Editor helper did not start"
        case .refused(let reply): "the Editor helper refused: \(reply)"
        }
    }
}

/// Starts the Editor helper nested in this bundle, marked as started by snapit, and tells it
/// what to open.
@MainActor
enum EditorHelperLauncher {
    static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/snapit Editor.app", isDirectory: true)
    }

    /// Starts the helper. `activates` asks macOS to bring it forward as it launches; a helper
    /// that only warms up, hidden, does not.
    static func start(activates: Bool = false, warm: Bool = false) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments =
            [AppIdentity.startedBySnapitArgument, AppIdentity.menuBarPIDArgumentPrefix + String(getpid())]
            + (warm ? [AppIdentity.warmArgument] : [])
        configuration.activates = activates
        // Always a new instance: a helper that is still terminating (a Cancel just before) would
        // otherwise be "launched" by merely activating it, and no new helper would come up. A
        // helper that finds a live socket quits at once, so two never serve at the same time.
        configuration.createsNewApplicationInstance = true
        if let root = TestMode.root {
            configuration.environment = [TestMode.rootVariable: root.path]
        }
        _ = try await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
    }

    /// Opens Capture N in the Editor: reuses the running helper, or starts one first. Returns
    /// once the Editor window is showing and the helper has been asked to come forward.
    ///
    /// `command` is `open-capture` for a Capture just taken (it uses the warm Editor and ends the
    /// warm-up) or `reopen-capture` for the Last Capture (it restores the stored Annotations and
    /// leaves a warm-up alone).
    static func open(capture number: Int, command: SocketCommand = .openCapture) async throws {
        var failure: Error = EditorHelperError.didNotStart
        let isNew = command == .openCapture
        // A helper being warmed up is the one to use: never start a second.
        await EditorWarmUp.settle()
        // Twice: a helper that was quitting when the first send arrived is replaced by a new one.
        for _ in 0..<2 {
            do {
                try await ensureRunning(activates: EditorActivation.current.activateAtLaunch)
                let reply = try await CommandSocketClient.send(
                    command, arguments: [String(number)], to: AppIdentity.editorSocketPath, timeoutSeconds: 10)
                guard reply == "ok" else { throw EditorHelperError.refused(reply) }
                if isNew { EditorWarmUp.didOpen() }
                await bringForward()
                return
            } catch let error as EditorHelperError {
                if case .refused = error { throw error }
                failure = error
            } catch {
                failure = error
            }
        }
        throw failure
    }

    /// Asks LaunchServices to activate the running helper (see `EditorActivation`). Reaches a
    /// helper that was already running; its reopen handler does nothing of its own.
    static func bringForward() async {
        guard EditorActivation.current.activateAfterOpen else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
    }

    /// Waits until the helper's socket answers, starting the helper when it is not running.
    /// The wait is bounded and happens only while a Capture opens, never at rest.
    static func ensureRunning(activates: Bool, warm: Bool = false) async throws {
        let path = AppIdentity.editorSocketPath
        if await CommandSocketClient.isListening(at: path) { return }
        try await start(activates: activates, warm: warm)
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await CommandSocketClient.isListening(at: path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw EditorHelperError.didNotStart
    }
}
