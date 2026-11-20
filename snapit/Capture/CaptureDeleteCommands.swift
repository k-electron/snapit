import Foundation

extension SocketCommandRegistry {
    /// The commands the Editor helper sends the menu bar app about Captures.
    func registerCaptureDeleteCommands() {
        register(.deleteCapture) { request in
            guard let number = request.arguments.first.flatMap(Int.init) else { return "error delete-capture <number>" }
            CaptureHandoff.delete(number: number)
            return "ok"
        }
    }
}
