import Foundation

extension SocketCommandRegistry {
    /// The commands the menu bar app sends the Editor helper about Captures.
    func registerEditorCommands() {
        register(.openCapture) { request in
            guard let number = request.arguments.first.flatMap(Int.init) else { return "error open-capture <number>" }
            do {
                try EditorSessions.shared.open(captureNumber: number)
                return "ok"
            } catch {
                return "error \(error)"
            }
        }
    }
}
