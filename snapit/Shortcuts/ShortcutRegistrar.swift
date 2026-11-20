/// Turns key presses into actions. The real registrar is KeyboardShortcuts (Carbon hot
/// keys); the scripted run swaps in `InjectedShortcuts`, so a test never registers a real
/// hot key and never collides with the user's own snapit or another run. Always go through
/// `Shortcuts.current`.
@MainActor
protocol ShortcutRegistrar {
    /// Runs `handler` each time `shortcut` is pressed, until the process ends.
    func register(_ shortcut: AppShortcut, handler: @escaping @MainActor () async -> Void)
}

@MainActor
enum Shortcuts {
    static let current: any ShortcutRegistrar =
        TestMode.isActive ? InjectedShortcuts.shared : KeyboardShortcutsRegistrar()
}
