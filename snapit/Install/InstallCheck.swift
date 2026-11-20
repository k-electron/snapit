import Foundation

/// The check every launch of the menu bar app runs: where does this copy run from?
///
/// - A normal place: nothing happens.
/// - A mounted disk image (or a translocated path whose original is elsewhere): the Editor
///   helper shows the "Move snapit to Applications" screen. The menu bar app never opens a window.
/// - Translocated, with its original copy in Applications: strip quarantine from that copy and
///   relaunch it in place.
///
/// A copy macOS has not approved yet (no Open Anyway) is left alone.
@MainActor
enum InstallCheck {
    /// What a run of the check did, for the scripted run.
    enum Outcome: String {
        case none
        case moveScreenShown = "move-screen-shown"
        case fixedInPlace = "fixed-in-place"
        case notApproved = "not-approved"
    }

    private static var isMoving = false

    static func location(environment: any InstallEnvironment = InstallEdge.current) -> InstallLocation {
        InstallLocation.detect(
            bundlePath: environment.bundlePath, volumes: environment.volumes, volumesFolder: environment.volumesFolder)
    }

    static func plan(environment: any InstallEnvironment = InstallEdge.current) -> InstallPlan {
        location(environment: environment).plan(applicationsFolder: environment.applicationsFolder)
    }

    /// Runs the check. Called once per launch by `AppDelegate`.
    @discardableResult
    static func runAtLaunch(environment: any InstallEnvironment = InstallEdge.current) async -> Outcome {
        switch plan(environment: environment) {
        case .stay:
            return .none
        case .fixInPlace(let copy):
            guard Quarantine.isApproved(at: copy.path) else { return .notApproved }
            // Nothing to strip: a relaunch cannot change anything, and would repeat on every launch.
            guard Quarantine.flaggedCount(under: copy) > 0 else { return .none }
            do {
                try await MoveToApplications.fixInPlace(copy: copy, environment: environment)
                return .fixedInPlace
            } catch {
                NSLog("snapit: \(error)")
                return .none
            }
        case .move(let source):
            guard Quarantine.isApproved(at: source.path) else { return .notApproved }
            let reason = location(environment: environment).onDiskImage ? "disk-image" : "temporary"
            let destination = environment.applicationsFolder.appendingPathComponent(source.lastPathComponent)
            let replaces = FileManager.default.fileExists(atPath: destination.path) ? "replace" : "new"
            do {
                try await MoveScreenLauncher.show(reason: reason, replaces: replaces)
                return .moveScreenShown
            } catch {
                NSLog("snapit: could not show the Move to Applications screen: \(error)")
                return .none
            }
        }
    }

    /// The user chose Move to Applications on the screen. Returns when the copy is relaunched
    /// (the app quits a moment later) and throws what went wrong.
    static func moveChosen(environment: any InstallEnvironment = InstallEdge.current) async throws {
        guard !isMoving else { return }
        guard case .move(let source) = plan(environment: environment) else {
            throw InstallError.copyFailed("snapit is not running from a disk image.")
        }
        isMoving = true
        do {
            try await MoveToApplications.move(source: source, environment: environment)
        } catch {
            isMoving = false
            throw error
        }
    }
}
