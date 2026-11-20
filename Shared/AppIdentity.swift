import Foundation

/// Names both processes agree on.
nonisolated enum AppIdentity {
    static let mainBundleIdentifier = "dev.snapit.snapit"
    static let editorBundleIdentifier = "dev.snapit.snapit.editor"

    /// Launch argument the menu bar app passes to every Editor helper it starts. A helper
    /// started without it was launched on its own (for example from a Dock pin).
    static let startedBySnapitArgument = "--started-by-snapit"
    /// Launch argument for a helper started at a Shortcut press: it builds an Editor window,
    /// hidden, as soon as it is up, so the Capture only has to be attached and shown.
    static let warmArgument = "--warm"
    /// Launch argument carrying the menu bar app's process ID (`--menu-bar-pid=<n>`): a helper
    /// that has shown nothing quits when that process exits.
    static let menuBarPIDArgumentPrefix = "--menu-bar-pid="

    /// snapit's private cache folder (mode 0700). Holds the sockets, and later the Last Capture.
    /// In test mode it is the per-run temporary root.
    static var cacheFolder: URL {
        if let root = TestMode.root { return root }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent(mainBundleIdentifier, isDirectory: true)
    }

    /// The menu bar app's command socket.
    static var appSocketPath: String { cacheFolder.appendingPathComponent("app.sock").path }
    /// The Editor helper's command socket.
    static var editorSocketPath: String { cacheFolder.appendingPathComponent("editor.sock").path }
}
