import Observation
import SwiftUI

/// Turns key presses into actions. The real registrar is KeyboardShortcuts (Carbon hot
/// keys); the scripted run swaps in `InjectedShortcuts`, so a test never registers a real
/// hot key and never collides with the user's own snapit or another run. Always go through
/// `Shortcuts.current`.
///
/// KeyboardShortcuts stores the user's choice in the menu bar app's own
/// `UserDefaults.standard`, so it only works in that process. The Editor helper's Settings and
/// Onboarding use a binding-based recorder, store the choice through `AppDefaults.store`, and
/// send a socket command; the menu bar app then calls `setShortcut(_:for:)`.
@MainActor
protocol ShortcutRegistrar {
    /// Runs `handler` each time `shortcut` is pressed, until the process ends.
    func register(_ shortcut: AppShortcut, handler: @escaping @MainActor () async -> Void)
    /// The key combination `shortcut` currently has; nil when it is unassigned.
    func combo(for shortcut: AppShortcut) -> ShortcutCombo?
    /// Gives `shortcut` a new key combination, or unassigns it with nil.
    func setCombo(_ combo: ShortcutCombo?, for shortcut: AppShortcut)
    /// The menu item key equivalent that displays the current combination; nil when unassigned.
    func menuShortcut(for shortcut: AppShortcut) -> KeyboardShortcut?
}

@MainActor
enum Shortcuts {
    static let current: any ShortcutRegistrar =
        ObservedShortcuts(TestMode.isActive ? InjectedShortcuts.shared : KeyboardShortcutsRegistrar())
}

/// The registrar every caller sees: it passes everything to the real (or injected) one and makes
/// the menu follow a rebound Shortcut. A menu section that reads `menuShortcut(for:)` while the
/// menu renders is observing `revision`, which a `setCombo` bumps, so the menu glyphs change the
/// moment a Shortcut is rebound, by Settings or by anything else.
@MainActor
@Observable
final class ObservedShortcuts: ShortcutRegistrar {
    @ObservationIgnored private let base: any ShortcutRegistrar
    private var revision = 0

    init(_ base: any ShortcutRegistrar) { self.base = base }

    func register(_ shortcut: AppShortcut, handler: @escaping @MainActor () async -> Void) {
        base.register(shortcut, handler: handler)
    }

    func combo(for shortcut: AppShortcut) -> ShortcutCombo? {
        _ = revision
        return base.combo(for: shortcut)
    }

    func setCombo(_ combo: ShortcutCombo?, for shortcut: AppShortcut) {
        base.setCombo(combo, for: shortcut)
        revision += 1
    }

    func menuShortcut(for shortcut: AppShortcut) -> KeyboardShortcut? {
        _ = revision
        return base.menuShortcut(for: shortcut)
    }
}
