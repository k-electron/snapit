import KeyboardShortcuts

/// The real registrar: KeyboardShortcuts 3.x, which wraps Carbon hot keys (no Accessibility
/// prompt) and keeps working while the menu bar menu is open. It stores the user's choice in
/// `UserDefaults.standard`, so test mode never touches this type.
@MainActor
struct KeyboardShortcutsRegistrar: ShortcutRegistrar {
    func register(_ shortcut: AppShortcut, handler: @escaping @MainActor () async -> Void) {
        let name = KeyboardShortcuts.Name(
            shortcut.id,
            initial: KeyboardShortcuts.Shortcut(
                KeyboardShortcuts.Key(rawValue: shortcut.defaultKeyCode), modifiers: shortcut.defaultModifiers))
        KeyboardShortcuts.onKeyDown(for: name) {
            Task { @MainActor in await handler() }
        }
    }
}
