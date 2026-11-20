import Foundation

/// How the Editor helper gets to be the active app when a Capture opens.
///
/// macOS 14 and later activate cooperatively: an app that is not frontmost can refuse to be
/// activated by another, and `NSRunningApplication.activate(from:)` or `yieldActivation` only
/// work when the calling app is itself active. The menu bar app is not (a Shortcut is a hot key,
/// and the app is an agent), so those can't be relied on. What does not depend on either app's
/// state is asking LaunchServices to open the helper's bundle with `activates` on, the same
/// request the Dock and Finder make: the system brings the app forward, running or not. So:
///
/// - starting the helper asks for activation at launch, and
/// - once the Editor window shows, the menu bar app asks LaunchServices again, which reaches a
///   helper that was already running (a second Capture, a warm helper).
///
/// The helper also calls `NSApp.activate()` itself when its window shows (`HelperLifecycle`).
/// A scripted run never takes focus from what the user is doing, so test mode does neither.
enum EditorActivation {
    struct Plan: Equatable {
        /// Ask LaunchServices to activate the helper as it launches.
        var activateAtLaunch: Bool
        /// Ask LaunchServices to activate the helper once the Editor window shows.
        var activateAfterOpen: Bool
    }

    static func plan(testMode: Bool) -> Plan {
        Plan(activateAtLaunch: !testMode, activateAfterOpen: !testMode)
    }

    static var current: Plan { plan(testMode: TestMode.isActive) }
}
