import KeyboardShortcuts
import SwiftUI

/// The real registrar: KeyboardShortcuts 3.x, which wraps Carbon hot keys (no Accessibility
/// prompt) and keeps working while the menu bar menu is open. It stores the user's choice in
/// `UserDefaults.standard` of the process it runs in (the menu bar app), so test mode never
/// touches this type.
@MainActor
struct KeyboardShortcutsRegistrar: ShortcutRegistrar {
    private func name(for shortcut: AppShortcut) -> KeyboardShortcuts.Name {
        let initial = shortcut.defaultCombo.map {
            KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: $0.keyCode), modifiers: $0.modifiers)
        }
        return KeyboardShortcuts.Name(shortcut.id, initial: initial)
    }

    func register(_ shortcut: AppShortcut, handler: @escaping @MainActor () async -> Void) {
        KeyboardShortcuts.onKeyDown(for: name(for: shortcut)) {
            Task { @MainActor in await handler() }
        }
    }

    func combo(for shortcut: AppShortcut) -> ShortcutCombo? {
        KeyboardShortcuts.getShortcut(for: name(for: shortcut)).map {
            ShortcutCombo(keyCode: $0.carbonKeyCode, modifiers: $0.modifiers)
        }
    }

    func setCombo(_ combo: ShortcutCombo?, for shortcut: AppShortcut) {
        let value = combo.map {
            KeyboardShortcuts.Shortcut(KeyboardShortcuts.Key(rawValue: $0.keyCode), modifiers: $0.modifiers)
        }
        KeyboardShortcuts.setShortcut(value, for: name(for: shortcut))
    }

    func menuShortcut(for shortcut: AppShortcut) -> KeyboardShortcut? {
        guard let stored = KeyboardShortcuts.getShortcut(for: name(for: shortcut)),
            let character = stored.nsMenuItemKeyEquivalent?.first
        else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: EventModifiers(stored.modifiers))
    }
}

extension EventModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: EventModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}
