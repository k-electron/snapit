import Foundation

/// When Onboarding and the Permission guide appear. The windows are the Editor helper's.
///
/// - First launch (after the install location check passed), and every Shortcut press until
///   Onboarding is finished: Onboarding, at the step the user got to.
/// - Launch after Onboarding finished, with Screen Recording gone after it was granted (an
///   update): the Screen Recording Permission guide alone.
@MainActor
enum OnboardingLauncher {
    /// What a launch showed, for the scripted run.
    enum Outcome: String {
        case onboarding
        case permissionGuide = "permission-guide"
        case none
    }

    @discardableResult
    static func runAtLaunch() async -> Outcome {
        if !OnboardingProgress.isFinished {
            await showOnboarding()
            return .onboarding
        }
        if ScreenRecordingPermission.current.state == .grantedStale {
            await showPermissionGuide(.screenRecording)
            return .permissionGuide
        }
        return .none
    }

    static func showOnboarding() async {
        await HelperWindowLauncher.show(.showOnboarding)
    }

    /// Shows one Permission guide on its own: after an update, and (a later ticket) when a Shortcut
    /// is pressed without the permission.
    static func showPermissionGuide(_ kind: PermissionGuideKind) async {
        await HelperWindowLauncher.show(.showPermissionGuide, arguments: [kind.rawValue])
    }

    /// Runs a Shortcut's action once Onboarding is finished. A Shortcut pressed before that opens
    /// Onboarding at its stored step instead: the Capture would need what Onboarding sets up.
    static func whenSetUp(_ action: @MainActor () async -> Void) async {
        guard OnboardingProgress.isFinished else {
            await showOnboarding()
            return
        }
        await action()
    }
}
