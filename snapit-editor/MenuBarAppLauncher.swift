import AppKit

/// Starts the menu bar app that contains this helper.
enum MenuBarAppLauncher {
    /// `snapit.app/Contents/Helpers/snapit Editor.app` -> `snapit.app`.
    static var menuBarAppURL: URL {
        var url = Bundle.main.bundleURL
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url
    }

    @MainActor
    static func startMenuBarAppThenQuit() {
        let configuration = NSWorkspace.OpenConfiguration()
        if let root = TestMode.root {
            configuration.environment = [TestMode.rootVariable: root.path]
            // Parallel scripted runs must never activate another copy of the menu bar app.
            configuration.createsNewApplicationInstance = true
        }
        NSWorkspace.shared.openApplication(at: menuBarAppURL, configuration: configuration) { _, error in
            if let error { NSLog("snapit Editor: could not start snapit: \(error)") }
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
    }
}
