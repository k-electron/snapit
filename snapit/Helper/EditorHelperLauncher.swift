import AppKit

/// Starts the Editor helper nested in this bundle, marked as started by snapit.
@MainActor
enum EditorHelperLauncher {
    static var helperURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/snapit Editor.app", isDirectory: true)
    }

    static func start() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [AppIdentity.startedBySnapitArgument]
        configuration.activates = false
        if let root = TestMode.root {
            configuration.environment = [TestMode.rootVariable: root.path]
            // Parallel scripted runs must never activate another copy of the helper.
            configuration.createsNewApplicationInstance = true
        }
        _ = try await NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
    }
}
