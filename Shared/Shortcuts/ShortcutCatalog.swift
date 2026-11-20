import AppKit
import Carbon.HIToolbox

/// The Shortcuts the user can record in Settings, in the order Settings lists them. Both
/// processes read it: the Editor helper's Settings window draws a recorder for each entry and
/// the menu bar app applies the recorded combination (`apply-shortcut`) to the entry's
/// `AppShortcut`.
///
/// A combination recorded for the Window or Pick Color Shortcut before its feature binds a
/// handler (`ShortcutBindings`) is kept and used the moment the handler is registered.
enum ShortcutCatalog {
    struct Entry {
        let shortcut: AppShortcut
        /// What Settings calls it.
        let title: String
    }

    static let entries: [Entry] = [
        Entry(shortcut: .area, title: "Area"),
        Entry(shortcut: .window, title: "Window"),
        Entry(shortcut: .screen, title: "Screen"),
        Entry(shortcut: .pickColor, title: "Pick Color"),
    ]

    static func entry(id: String) -> Entry? { entries.first { $0.shortcut.id == id } }
}

extension ShortcutCombo {
    private static let modifierNames: [(NSEvent.ModifierFlags, String)] = [
        (.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command"),
    ]

    /// The combination as words, `<key code> [<modifier>,...]`, the form the socket and the
    /// stored setting use. Nil (unassigned) is `none`.
    static func wire(_ combo: ShortcutCombo?) -> String {
        guard let combo else { return "none" }
        let names = modifierNames.filter { combo.modifiers.contains($0.0) }.map(\.1)
        return "\(combo.keyCode) \(names.joined(separator: ","))".trimmingCharacters(in: .whitespaces)
    }

    /// Reads `wire(_:)` back: `none`, or a key code with optional comma separated modifiers
    /// (the words may also come as separate arguments). The outer nil means it was not valid.
    static func parse(wire words: [String]) -> ShortcutCombo?? {
        guard let first = words.first else { return nil }
        if first == "none" { return .some(nil) }
        guard let keyCode = Int(first) else { return nil }
        var modifiers: NSEvent.ModifierFlags = []
        for name in words.dropFirst().flatMap({ $0.split(separator: ",").map(String.init) }) {
            guard let match = modifierNames.first(where: { $0.1 == name }) else { return nil }
            modifiers.insert(match.0)
        }
        return .some(ShortcutCombo(keyCode: keyCode, modifiers: modifiers))
    }

    static func parse(wire text: String) -> ShortcutCombo?? {
        parse(wire: text.split(separator: " ").map(String.init))
    }
}
