import Foundation

nonisolated extension SocketCommand {
    /// Replies with the titles of the menu bar menu, one per line ("-" for a separator).
    /// The scripted run reads the menu through it.
    static let menuTitles = SocketCommand("menu-titles")
    /// Starts the Editor helper, marked as started by snapit, and replies `ok`.
    static let startEditor = SocketCommand("start-editor")
}

extension SocketCommandRegistry {
    /// Registers the commands only the menu bar app answers. A feature adds its own
    /// `register…Commands()` in its own file and calls it here with one line.
    func registerAppCommands() {
        registerMenuCommands()
        registerEditorHelperCommands()
    }

    private func registerMenuCommands() {
        register(.menuTitles) { _ in
            MenuModel.shared.entries.map { $0.title ?? "-" }.joined(separator: "\n")
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
