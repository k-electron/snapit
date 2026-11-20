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

    /// The reply to `screen-recording-state`: the state, then `turned-off` on a second line when the
    /// user turned Screen Recording off for this same build (that is not an update).
    static func stateReply() -> String {
        let permission = ScreenRecordingPermission.current
        let state = permission.state
        return state.rawValue + (state == .denied && permission.wasTurnedOff ? "\nturned-off" : "")
    }

    /// - granted, or granted but waiting for a relaunch: nothing to ask.
    /// - denied: asks anyway. macOS ignores it while its entry exists, and a user who removed the
    ///   entry in System Settings gets its message again.
    /// - grantedStale (an update): clears snapit's own old entry, forgets the history, and asks
    ///   afresh. The history is forgotten only after the reset worked, so a failed reset is tried
    ///   again at the next launch, and a worked one never again: a user who answers "Don't Allow"
    ///   is not asked at every launch. When the reset fails snapit still asks: that does nothing
    ///   while the old entry exists, and shows macOS's message once the user has removed it by hand,
    ///   so the relaunch the guide asks for ends in a grant, not in the same failure.
    /// - notDetermined: asks.
    static func run() async -> Outcome {
        let permission = ScreenRecordingPermission.current
        var failure: String?
        switch permission.state {
        case .granted, .grantedNeedsRelaunch:
            break
        case .denied:
            permission.request()
        case .grantedStale:
            do {
                try await ScreenRecordingResets.current.reset()
                permission.forgetHistory()
            } catch {
                failure = "\(error)"
                NSLog("snapit: could not reset its Screen Recording entry: \(error)")
            }
            permission.request()
        case .notDetermined:
            permission.request()
        }
        return Outcome(state: permission.state, resetFailure: failure)
    }
}
