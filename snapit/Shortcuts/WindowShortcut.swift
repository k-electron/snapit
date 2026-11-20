import Carbon.HIToolbox

extension AppShortcut {
    /// Window Capture, ⌃⌥⌘5 by default.
    static let window = AppShortcut(
        id: "capture-window", defaultKeyCode: kVK_ANSI_5, defaultModifiers: [.control, .option, .command])
}
