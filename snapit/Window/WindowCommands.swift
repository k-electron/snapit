import Foundation

nonisolated extension SocketCommand {
    /// `fixture-window-fail on|off`: makes the fixture window Capture fail, as if the picked
    /// window had closed since the overlay showed. Replies `ok`. Test mode only.
    static let fixtureWindowFail = SocketCommand("fixture-window-fail")
}

extension SocketCommandRegistry {
    /// The Window Capture's test-mode commands (the overlay's own are `overlay-*`, in
    /// `AreaCommands.swift`).
    func registerWindowTestCommands() {
        guard TestMode.isActive else { return }
        register(.fixtureWindowFail) { request in
            guard let state = request.arguments.first, ["on", "off"].contains(state) else {
                return "error fixture-window-fail on|off"
            }
            FixtureWindowCaptureSource.shared.fails = state == "on"
            return "ok"
        }
    }
}
