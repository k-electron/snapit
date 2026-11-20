import Carbon.HIToolbox

extension AppShortcut {
    /// Area Capture, ⌃⌥⌘4 by default.
    static let area = AppShortcut(
        id: "capture-area", defaultKeyCode: kVK_ANSI_4, defaultModifiers: [.control, .option, .command])
}
