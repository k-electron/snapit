import Carbon.HIToolbox
import SwiftUI

/// Test mode's registrar: keeps the handlers in a dictionary and runs a handler when the scripted
/// run "presses" the Shortcut (`press-shortcut`). The key combinations are kept in the run's
/// defaults, so a recorded Shortcut survives a relaunch of the menu bar app as it does through
/// KeyboardShortcuts. No hot key is registered with the system and KeyboardShortcuts (which
/// writes `UserDefaults.standard`) is never touched.
@MainActor
final class InjectedShortcuts: ShortcutRegistrar {
    static let shared = InjectedShortcuts()

    private var handlers: [String: @MainActor () async -> Void] = [:]
    private var bound: [String: AppShortcut] = [:]

    private func key(_ shortcut: AppShortcut) -> String { "test.shortcut.\(shortcut.id)" }

    func register(_ shortcut: AppShortcut, handler: @escaping @MainActor () async -> Void) {
        handlers[shortcut.id] = handler
        bound[shortcut.id] = shortcut
    }

    func combo(for shortcut: AppShortcut) -> ShortcutCombo? {
        guard let text = AppDefaults.store.string(forKey: key(shortcut)), let stored = ShortcutCombo.parse(wire: text)
        else { return shortcut.defaultCombo }
        return stored
    }

    func setCombo(_ combo: ShortcutCombo?, for shortcut: AppShortcut) {
        AppDefaults.store.set(ShortcutCombo.wire(combo), forKey: key(shortcut))
    }

    func menuShortcut(for shortcut: AppShortcut) -> KeyboardShortcut? {
        guard let combo = combo(for: shortcut), let character = Self.characters[combo.keyCode] else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: EventModifiers(combo.modifiers))
    }

    /// Runs the handler bound to `id` and returns when it has finished. False when none is bound.
    func press(_ id: String) async -> Bool {
        guard let handler = handlers[id] else { return false }
        await handler()
        return true
    }

    /// The Shortcut registered under `id`, for the test commands.
    func shortcut(id: String) -> AppShortcut? { bound[id] }

    var boundIDs: [String] { handlers.keys.sorted() }

    /// The characters of the digit keys, enough for the menu glyphs the tests look at.
    private static let characters: [Int: Character] = [
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
    ]
}
