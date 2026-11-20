import Foundation

nonisolated extension SocketCommand {
    /// `press-shortcut <id>`: presses the injected Shortcut and replies `ok` once the action
    /// has finished. Test mode only.
    static let pressShortcut = SocketCommand("press-shortcut")
    /// Replies with the ids of the Shortcuts bound so far, one per line. Test mode only.
    static let boundShortcuts = SocketCommand("bound-shortcuts")
}

extension SocketCommandRegistry {
    func registerShortcutTestCommands() {
        guard TestMode.isActive else { return }
        register(.pressShortcut) { request in
            guard let id = request.arguments.first else { return "error missing shortcut id" }
            return await InjectedShortcuts.shared.press(id) ? "ok" : "error no shortcut \(id)"
        }
        register(.boundShortcuts) { _ in
            InjectedShortcuts.shared.boundIDs.joined(separator: "\n")
        }
    }
}
