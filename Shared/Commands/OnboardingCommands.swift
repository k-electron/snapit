import Foundation

/// Commands of Onboarding and the Permission guide. The menu bar app never opens a window: it
/// asks the Editor helper to show them, and the helper asks the menu bar app about Screen
/// Recording, which only the menu bar app may ask macOS about.
nonisolated extension SocketCommand {
    /// The menu bar app asks the Editor helper to show Onboarding at its stored step, or to bring
    /// it forward when it is open. Replies `ok` once the window is on screen.
    static let showOnboarding = SocketCommand("show-onboarding")
    /// `show-permission-guide <kind>`: the menu bar app asks the helper to show one Permission
    /// guide on its own (`screen-recording`, or `folder <errno|none> <folder>` for a Save that failed after its hand-over). Replies `ok` once the window is on screen.
    static let showPermissionGuide = SocketCommand("show-permission-guide")
    /// The helper asks where Screen Recording stands. Replies `notDetermined`, `denied`,
    /// `granted` or `grantedStale`. Never shows a prompt.
    static let screenRecordingState = SocketCommand("screen-recording-state")
    /// The helper asks the menu bar app to ask macOS for Screen Recording afresh: after an update
    /// (`grantedStale`) it first resets snapit's own entry. Replies the state that follows, then
    /// `reset-failed <why>` on a second line when the reset did not work. A denied snapit is not
    /// asked again: macOS would not show a prompt.
    static let screenRecordingRequest = SocketCommand("screen-recording-request")
    /// The helper asks the menu bar app to relaunch itself (the "Relaunch snapit" button). Replies
    /// `ok` just before it quits, or `error <why>`.
    static let relaunchSnapit = SocketCommand("relaunch-snapit")
    /// The helper replies with the process ID of the menu bar app that started it, or `none`. A
    /// menu bar app that finds a helper of another copy on its socket (the old copy, still quitting
    /// after a relaunch) retires it, and a quitting copy leaves a helper that is not its own alone.
    static let helperOwner = SocketCommand("helper-owner")
}

/// The Permission guides there are. A guide for another permission adds a case, its drawing and
/// its model beside the Screen Recording ones.
nonisolated enum PermissionGuideKind: String, Sendable {
    case screenRecording = "screen-recording"
    /// Access to the Save location: a write there failed. Details after the kind:
    /// `<errno|none> <folder>`, sent by the menu bar app for a Save that failed after its hand-over.
    case folder
}
