import Foundation

nonisolated extension SocketCommand {
    /// `activation-plan test|normal`: how the helper would be brought forward when a Capture
    /// opens, in test mode or in a normal run, as `activate-at-launch=<bool>` and
    /// `activate-after-open=<bool>` lines. Test mode only.
    static let activationPlan = SocketCommand("activation-plan")
}

extension SocketCommandRegistry {
    func registerEditorActivationTestCommands() {
        guard TestMode.isActive else { return }
        register(.activationPlan) { request in
            guard let mode = request.arguments.first, mode == "test" || mode == "normal" else {
                return "error activation-plan test|normal"
            }
            let plan = EditorActivation.plan(testMode: mode == "test")
            return "activate-at-launch=\(plan.activateAtLaunch)\nactivate-after-open=\(plan.activateAfterOpen)"
        }
    }
}
