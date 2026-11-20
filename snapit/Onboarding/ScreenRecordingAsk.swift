import Foundation

/// What the Permission guide asks of the menu bar app: ask macOS for Screen Recording, afresh
/// after an update.
@MainActor
enum ScreenRecordingAsk {
    struct Outcome {
        let state: ScreenRecordingState
        /// Why snapit's own old entry could not be cleared; nil when it was, or needed no clearing.
        let resetFailure: String?

        /// The reply to `screen-recording-request`.
        var reply: String {
            state.rawValue + (resetFailure.map { "\nreset-failed \($0)" } ?? "")
        }
    }

    /// - granted: nothing to ask.
    /// - denied: macOS does not ask again, so nothing is asked.
    /// - grantedStale (an update): clears snapit's own old entry, forgets the history, and asks
    ///   afresh. The history is forgotten only after the reset worked, so a failed reset is tried
    ///   again at the next launch, and a worked one never again: a user who answers "Don't Allow"
    ///   is not asked at every launch. When the reset fails nothing is asked: macOS would not show
    ///   a prompt for the old entry.
    /// - notDetermined: asks.
    static func run() async -> Outcome {
        let permission = ScreenRecordingPermission.current
        var failure: String?
        switch permission.state {
        case .granted, .denied:
            break
        case .grantedStale:
            do {
                try await ScreenRecordingResets.current.reset()
                permission.forgetHistory()
                permission.request()
            } catch {
                failure = "\(error)"
                NSLog("snapit: could not reset its Screen Recording entry: \(error)")
            }
        case .notDetermined:
            permission.request()
        }
        return Outcome(state: permission.state, resetFailure: failure)
    }
}
