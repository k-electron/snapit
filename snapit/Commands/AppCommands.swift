import Foundation

extension SocketCommand {
    /// Replies with the titles of the menu bar menu, one per line ("-" for a separator).
    /// The scripted run reads the menu through it.
    static let menuTitles = SocketCommand("menu-titles")
}

extension SocketCommandRegistry {
    /// Registers the commands only the menu bar app answers. A feature adds its own
    /// `register…Commands()` in its own file and calls it here with one line.
    func registerAppCommands() {
        registerMenuCommands()
    }

    private func registerMenuCommands() {
        register(.menuTitles) { _ in
            MenuModel.entries.map { $0.title ?? "-" }.joined(separator: "\n")
        }
    }
}
