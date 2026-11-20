import Foundation

nonisolated extension SocketCommand {
    /// Replies with the titles of the menu bar menu, one per line ("-" for a separator).
    /// The scripted run reads the menu through it.
    static let menuTitles = SocketCommand("menu-titles")
    /// `menu-click <id>`: runs the action of the menu item with that id, as choosing it
    /// does, and replies `ok` when the action has finished. Test mode only.
    static let menuClick = SocketCommand("menu-click")
    /// Starts the Editor helper, marked as started by snapit, and replies `ok`.
    static let startEditor = SocketCommand("start-editor")
}

extension SocketCommandRegistry {
    /// Registers the commands only the menu bar app answers. A feature adds its own
    /// `register…Commands()` in its own file and calls it here with one line.
    func registerAppCommands() {
        registerMenuCommands()
        registerEditorHelperCommands()
        registerCaptureTestCommands()
        registerShortcutTestCommands()
    }

    private func registerMenuCommands() {
        register(.menuTitles) { _ in
            MenuModel.shared.entries.map { $0.title ?? "-" }.joined(separator: "\n")
        }
        guard TestMode.isActive else { return }
        register(.menuClick) { request in
            guard let id = request.arguments.first,
                let entry = MenuModel.shared.entries.first(where: { $0.id == id })
            else { return "error no menu item \(request.arguments.first ?? "")" }
            guard entry.isEnabled, let run = entry.run else { return "error menu item is disabled" }
            await run()
            return "ok"
        }
    }

    private func registerEditorHelperCommands() {
        register(.startEditor) { _ in
            do {
                try await EditorHelperLauncher.start()
                return "ok"
            } catch {
                return "error \(error)"
            }
        }
    }
}
