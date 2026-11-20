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
    static func start(activates: Bool = false) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [AppIdentity.startedBySnapitArgument]
        configuration.activates = activates
        if let root = TestMode.root {
            configuration.environment = [TestMode.rootVariable: root.path]
            // Parallel scripted runs must never activate another copy of the helper.
            configuration.createsNewApplicationInstance = true
        }
        _ = try await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
    }

    /// Opens Capture N in the Editor: reuses the running helper, or starts one first. Returns
    /// once the Editor window is showing.
    static func open(capture number: Int) async throws {
        var failure: Error = EditorHelperError.didNotStart
        // Twice: a helper that was quitting when the first send arrived is replaced by a new one.
        for _ in 0..<2 {
            do {
                try await ensureRunning()
                let reply = try await CommandSocketClient.send(
                    .openCapture, arguments: [String(number)], to: AppIdentity.editorSocketPath, timeoutSeconds: 10)
                guard reply == "ok" else { throw EditorHelperError.refused(reply) }
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

    /// Waits until the helper's socket answers, starting the helper when it is not running.
    /// The wait is bounded and happens only while a Capture opens, never at rest.
    private static func ensureRunning() async throws {
        let path = AppIdentity.editorSocketPath
        if await CommandSocketClient.isListening(at: path) { return }
        // A scripted run never takes focus from what the user is doing.
        try await start(activates: !TestMode.isActive)
        let deadline = ContinuousClock.now + .seconds(10)
        while ContinuousClock.now < deadline {
            if await CommandSocketClient.isListening(at: path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw EditorHelperError.didNotStart
    }
}
