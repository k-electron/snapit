import Foundation

/// What the user sees when a Save fails after it was handed over (the disk filled up, the folder
/// went away, the final rename failed). The Editor that asked for the Save may be gone by then, so
/// the notice cannot be the Editor's: the menu bar app never opens a window either, so it asks the
/// Editor helper, which starts if it is not running, to show the folder Permission guide's window
/// with the reason in words. The helper quits again when that window closes.
///
/// A Save that fails the writability check never gets here: that one is answered to the Editor,
/// which stays open and shows the same guide with a retry.
@MainActor
enum SaveFailureNotice {
    /// True once the menu bar app is quitting (waiting for its last Saves to end).
    static var isQuitting = false

    /// Registers with `SaveService` once, at launch.
    static func register() {
        SaveService.shared.observeWriteFailures { failure in
            Task { @MainActor in await show(failure) }
        }
    }

    /// `show-permission-guide folder <errno|none> <folder>`: no Editor is named, so the guide offers
    /// no retry (the pixels were handed over and are gone from the Editor's side of the Save).
    static func show(_ failure: SaveWriteFailure) async {
        // Quitting waits for pending Saves; a window for a failure that ends the process helps no one.
        guard !isQuitting else { return }
        await OnboardingLauncher.showPermissionGuide(
            .folder, details: [failure.code.map(String.init) ?? "none", failure.folder])
    }
}
