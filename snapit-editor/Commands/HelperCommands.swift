import Foundation

extension SocketCommandRegistry {
    /// Registers the commands only the Editor helper answers. A feature adds its own
    /// `register…Commands()` in its own file and calls it here with one line.
    func registerHelperCommands() {
        registerEditorCommands()
        registerEditorTestCommands()
    }
}
