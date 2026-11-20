import AppKit

/// The System Settings pages snapit links to. Always open one through `SystemSettingsLinks.open`:
/// a scripted run records the link in `<root>/system-settings-links` instead of opening System
/// Settings.
enum SystemSettingsLinks {
    enum Page: String {
        /// The Keyboard page, where Keyboard Shortcuts… › Screenshots holds ⌘⇧3, ⌘⇧4 and ⌘⇧5.
        case screenshotShortcuts = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        /// Login Items, where a login item that needs approval is approved.
        case loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    }

    static func open(_ page: Page) {
        guard let root = TestMode.root else {
            if let url = URL(string: page.rawValue) { NSWorkspace.shared.open(url) }
            return
        }
        let log = root.appendingPathComponent("system-settings-links")
        let line = Data((page.rawValue + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: log)
        }
    }
}
