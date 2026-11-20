import AppKit
import Carbon.HIToolbox

/// A global Shortcut snapit offers, with its default key combination. A feature adds its
/// own in its own file:
///
///     extension AppShortcut { static let area = AppShortcut(id: "capture-area", ...) }
///
/// and binds it in `ShortcutBindings`.
struct AppShortcut {
    /// Stable name the Shortcut is stored under (and that the scripted run presses it by).
    let id: String
    /// Carbon virtual key code of the default key.
    let defaultKeyCode: Int
    let defaultModifiers: NSEvent.ModifierFlags
}

extension AppShortcut {
    /// Screen Capture, ⌃⌥⌘3 by default.
    static let screen = AppShortcut(
        id: "capture-screen", defaultKeyCode: kVK_ANSI_3, defaultModifiers: [.control, .option, .command])
}
