import AppKit

/// Web pages snapit opens in the user's browser (the release page behind the update window's
/// Download button, a link in the release notes). Always open one through `BrowserLinks.open`:
/// a scripted run appends the link to `<root>/browser-links` instead of opening a browser. Only
/// `https` links open.
enum BrowserLinks {
    @discardableResult
    static func open(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { return false }
        guard let root = TestMode.root else { return NSWorkspace.shared.open(url) }
        let log = root.appendingPathComponent("browser-links")
        let line = Data((url.absoluteString + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: log)
        }
        return true
    }
}
