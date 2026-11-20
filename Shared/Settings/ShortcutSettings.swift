import Foundation

/// The Shortcuts section of Settings: the combination each Shortcut has, kept through
/// `AppDefaults.store` so Settings (in the Editor helper) and Onboarding show what the user
/// chose. The menu bar app applies a change through `Shortcuts.current`; KeyboardShortcuts keeps
/// its own copy in the menu bar app's defaults.
enum ShortcutSettings {
    static func key(for shortcut: AppShortcut) -> String { "shortcut.\(shortcut.id)" }

    /// The combination chosen for `shortcut`, its default while none is stored, nil when the
    /// user unassigned it.
    static func combo(for shortcut: AppShortcut) -> ShortcutCombo? {
        guard let text = AppDefaults.store.string(forKey: key(for: shortcut)),
            let stored = ShortcutCombo.parse(wire: text)
        else { return shortcut.defaultCombo }
        return stored
    }

    static func store(_ combo: ShortcutCombo?, for shortcut: AppShortcut) {
        AppDefaults.store.set(ShortcutCombo.wire(combo), forKey: key(for: shortcut))
    }
}
