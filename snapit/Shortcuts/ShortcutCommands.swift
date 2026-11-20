import AppKit

nonisolated extension SocketCommand {
    /// `press-shortcut <id>`: presses the injected Shortcut and replies `ok` once the action
    /// has finished. Test mode only.
    static let pressShortcut = SocketCommand("press-shortcut")
    /// Replies with the ids of the Shortcuts bound so far, one per line. Test mode only.
    static let boundShortcuts = SocketCommand("bound-shortcuts")
    /// `shortcut-combo <id>`: replies `<key code> <modifiers, comma separated>` (modifiers drawn
    /// from control, option, shift, command) or `none` when unassigned. Test mode only.
    static let shortcutCombo = SocketCommand("shortcut-combo")
    /// `shortcut-set <id> none` or `shortcut-set <id> <key code> [<modifier> ...]`: gives a
    /// Shortcut a new key combination, as the Settings recorder will. Test mode only.
    static let shortcutSet = SocketCommand("shortcut-set")
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
        register(.shortcutCombo) { request in
            guard let id = request.arguments.first, let shortcut = InjectedShortcuts.shared.shortcut(id: id) else {
                return "error no shortcut \(request.arguments.first ?? "")"
            }
            guard let combo = Shortcuts.current.combo(for: shortcut) else { return "none" }
            let names: [(NSEvent.ModifierFlags, String)] = [
                (.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command"),
            ]
            let modifiers = names.filter { combo.modifiers.contains($0.0) }.map(\.1)
            return "\(combo.keyCode) \(modifiers.joined(separator: ","))"
        }
        register(.shortcutSet) { request in
            let arguments = request.arguments
            guard arguments.count >= 2, let shortcut = InjectedShortcuts.shared.shortcut(id: arguments[0]) else {
                return "error no shortcut \(arguments.first ?? "")"
            }
            if arguments[1] == "none" {
                Shortcuts.current.setCombo(nil, for: shortcut)
                return "ok"
            }
            guard let keyCode = Int(arguments[1]) else { return "error key code must be a number" }
            var modifiers: NSEvent.ModifierFlags = []
            for name in arguments.dropFirst(2) {
                switch name {
                case "control": modifiers.insert(.control)
                case "option": modifiers.insert(.option)
                case "shift": modifiers.insert(.shift)
                case "command": modifiers.insert(.command)
                default: return "error unknown modifier \(name)"
                }
            }
            Shortcuts.current.setCombo(ShortcutCombo(keyCode: keyCode, modifiers: modifiers), for: shortcut)
            return "ok"
        }
    }
}
