import AppKit
import Carbon.HIToolbox

/// A key combination: a Carbon virtual key code and its modifiers.
struct ShortcutCombo: Equatable {
    let keyCode: Int
    let modifiers: NSEvent.ModifierFlags
}

/// A global Shortcut snapit offers, with its default key combination (nil when it is
/// unassigned by default, like Pick Color). A feature adds its own in its own file:
///
///     extension AppShortcut { static let area = AppShortcut(id: "capture-area", ...) }
///
/// and binds it in `ShortcutBindings`.
struct AppShortcut {
    /// Stable name the Shortcut is stored under (and that the scripted run presses it by).
    let id: String
    /// Carbon virtual key code of the default key; nil when unassigned by default.
    let defaultKeyCode: Int?
    let defaultModifiers: NSEvent.ModifierFlags

    var defaultCombo: ShortcutCombo? {
        defaultKeyCode.map { ShortcutCombo(keyCode: $0, modifiers: defaultModifiers) }
    }
}

extension AppShortcut {
    /// Screen Capture, ⌃⌥⌘3 by default.
    static let screen = AppShortcut(
        id: "capture-screen", defaultKeyCode: kVK_ANSI_3, defaultModifiers: [.control, .option, .command])
}
