import Foundation

nonisolated extension SocketCommand {
    /// `editor-warm-up begin|cancel|state|settle`: does what a Capture does when it starts (`begin`)
    /// or is cancelled (`cancel`), and replies `ok`; `state` replies `idle`, `starting` or `warm`;
    /// `settle` waits until every helper start and cancel queued so far has reached the helper,
    /// then replies `ok`. Test mode only.
    static let editorWarmUp = SocketCommand("editor-warm-up")
    /// Replies `capture-to-editor-ms=<n> warm=yes|no` for the last Capture: how long it took from
    /// its pixels being ready to the Editor window showing, and whether the helper had an Editor
    /// built ahead of it. `none` before the first Capture. Test mode only.
    static let captureTiming = SocketCommand("capture-timing")
    /// `fixture-delay <ms>`: how long the fixture Capture source takes to return, standing in for
    /// the time spent choosing an Area. Test mode only.
    static let fixtureDelay = SocketCommand("fixture-delay")
    /// `fixture-fail on|off`: makes the fixture Capture fail, so the run exercises what a Capture
    /// that ends without a Capture does. Test mode only.
    static let fixtureFail = SocketCommand("fixture-fail")
}

extension SocketCommandRegistry {
    func registerEditorWarmUpTestCommands() {
        guard TestMode.isActive else { return }
        register(.editorWarmUp) { request in
            switch request.arguments.first {
            case "begin":
                EditorWarmUp.begin()
                return "ok"
            case "cancel":
                EditorWarmUp.cancel()
                return "ok"
            case "state":
                return EditorWarmUp.state.rawValue
            case "settle":
                await EditorWarmUp.settle()
                return "ok"
            default:
                return "error editor-warm-up begin|cancel|state|settle"
            }
        }
        register(.captureTiming) { _ in
            guard let sample = CaptureTiming.last else { return "none" }
            return "capture-to-editor-ms=\(String(format: "%.1f", sample.milliseconds)) warm=\(sample.wasWarm ? "yes" : "no")"
        }
        register(.fixtureDelay) { request in
            guard let milliseconds = request.arguments.first.flatMap(Int.init), milliseconds >= 0 else {
                return "error fixture-delay <milliseconds>"
            }
            FixtureCaptureSource.shared.delay = .milliseconds(milliseconds)
            return "ok"
        }
        register(.fixtureFail) { request in
            guard let mode = request.arguments.first, mode == "on" || mode == "off" else {
                return "error fixture-fail on|off"
            }
            FixtureCaptureSource.shared.fails = mode == "on"
            return "ok"
        }
    }
}
