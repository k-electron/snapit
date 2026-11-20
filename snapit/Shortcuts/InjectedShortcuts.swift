/// Test mode's registrar: keeps the handlers and runs one when the scripted run "presses"
/// the Shortcut (`press-shortcut`). No hot key is registered with the system.
@MainActor
final class InjectedShortcuts: ShortcutRegistrar {
    static let shared = InjectedShortcuts()

    private var handlers: [String: @MainActor () async -> Void] = [:]

    func register(_ shortcut: AppShortcut, handler: @escaping @MainActor () async -> Void) {
        handlers[shortcut.id] = handler
    }

    /// Runs the handler bound to `id` and returns when it has finished. False when none is bound.
    func press(_ id: String) async -> Bool {
        guard let handler = handlers[id] else { return false }
        await handler()
        return true
    }

    var boundIDs: [String] { handlers.keys.sorted() }
}
